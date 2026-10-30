"""Rebuild regressions with temporary homes and mocked system/network commands."""

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')


class RebuiltMachineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='rebuild-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / 'desktop user'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'calls'
        self.config = self.home / 'config'
        self.data = self.home / 'data'
        self.backup = self.home / 'backups/test'
        self.backup.mkdir(parents=True)
        self.cron = self.root / 'crontab'
        self.cron.write_text('MAILTO=owner\n# manual reminder\n2 3 * * * /opt/backup.sh\n')
        self.env = {**os.environ, 'HOME': str(self.home),
                    'XDG_CONFIG_HOME': str(self.config), 'XDG_DATA_HOME': str(self.data),
                    'PATH': str(self.bin) + ':' + os.environ['PATH'],
                    'REBUILD_TEST_LOG': str(self.log), 'REBUILD_TEST_CRON': str(self.cron),
                    'REBUILT_MACHINE_BACKUP_DIR': str(self.backup),
                    'REBUILT_MACHINE_REBOOT': '0'}
        # These commands never delegate to the real system.
        self.stub('sudo', 'printf "sudo %s\\n" "$*" >> "$REBUILD_TEST_LOG"\n')
        self.stub('curl', 'echo UNEXPECTED_NETWORK >&2; exit 99\n')
        self.stub('wget', 'echo UNEXPECTED_NETWORK >&2; exit 99\n')
        self.stub('cinnamon', 'echo UNEXPECTED_CINNAMON_RESTART >&2; exit 99\n')
        self.stub('gsettings', '''printf 'gsettings %s\n' "$*" >> "$REBUILD_TEST_LOG"
if [ "$1" = get ]; then
  case "$2" in
    org.cinnamon) printf '%s\n' "${REBUILD_TEST_APPLETS:-[]}" ;;
    org.gnome.Terminal.ProfilesList) echo "'11111111-2222-3333-4444-555555555555'" ;;
  esac
fi
''')
        self.stub('crontab', '''if [ "$1" = -l ]; then
  if [ "${REBUILD_TEST_CRON_ERROR:-0}" = 1 ]; then echo 'permission denied' >&2; exit 1; fi
  cat "$REBUILD_TEST_CRON"
else
  cp "$1" "$REBUILD_TEST_CRON"
  echo 'crontab installed' >> "$REBUILD_TEST_LOG"
fi
''')
        self.stub('xdg-mime', 'printf "mime %s\\n" "$*" >> "$REBUILD_TEST_LOG"\n')
        self.stub('dconf', '''printf 'dconf %s\n' "$*" >> "$REBUILD_TEST_LOG"
if [ "$1" = dump ]; then echo '[old]'; else cat >> "$REBUILD_TEST_LOG"; fi
''')
        self.stub('update-desktop-database', 'exit 0\n')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f'#!{BASH}\nset -eu\n' + body)
        path.chmod(0o755)

    def bash(self, code, success=True, extra_env=None):
        result = subprocess.run([BASH, '-c', 'source "$REBUILD_SCRIPT"\n' + code],
                                env={**self.env, 'REBUILD_SCRIPT': str(ROOT / 'rebuilt-machine.sh'),
                                     **(extra_env or {})},
                                capture_output=True, text=True, timeout=20)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('UNEXPECTED_', result.stdout + result.stderr)
        return result

    def menu_schema(self):
        schema = {
            'layout': {'type': 'layout', 'pages': ['modern-layout']},
            'menu-icon-size': {'type': 'spinbutton', 'default': 32, 'min': 16, 'max': 96},
            'menu-icon': {'type': 'iconfilechooser', 'default': 'cinnamon-symbolic'},
            'menu-custom': {'type': 'switch', 'default': False},
            'menu-label': {'type': 'entry', 'default': 'Menu'},
            'new-version-setting': {'type': 'generic', 'default': 12},
        }
        path = self.root / 'menu-schema/settings-schema.json'
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(schema))
        self.env['CINNAMON_MENU_SCHEMA'] = str(path)
        return path

    def apply_menu(self, applets):
        return self.bash('bash "$MENU_HELPER" --menu-only', extra_env={
            'MENU_HELPER': str(ROOT / 'apply-cinnamon-settings.sh'),
            'REBUILD_TEST_APPLETS': repr(applets)})

    def test_menu_migrates_schema_and_all_enabled_instances_at_40px(self):
        schema = self.menu_schema()
        for instance in ('3', '9'):
            target = self.config / f'cinnamon/spices/menu@cinnamon.org/{instance}.json'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps({'new-version-setting': {'value': 99},
                                          'menu-icon-size': {'value': 50}}))
        applets = ['panel1:left:0:menu@cinnamon.org:3', 'panel2:left:0:menu@cinnamon.org:9']
        self.apply_menu(applets)
        self.apply_menu(applets)
        for instance in ('3', '9'):
            target = self.config / f'cinnamon/spices/menu@cinnamon.org/{instance}.json'
            actual = json.loads(target.read_text())
            self.assertEqual(actual['menu-icon-size']['value'], 40)
            self.assertEqual(actual['menu-icon']['value'], 'qortal-menu-button-2')
            self.assertEqual(actual['new-version-setting']['value'], 99)
            self.assertEqual(actual['layout']['pages'], ['modern-layout'])
            self.assertNotIn('menu-height', actual)
            self.assertEqual(actual['__md5__'], hashlib.md5(schema.read_bytes()).hexdigest())
        self.assertEqual(len(list(self.backup.glob('menu-*.json'))), 2)
        self.assertFalse((self.config / 'cinnamon/spices/menu@cinnamon.org/0.json').exists())

    def test_menu_migrates_legacy_instance_settings(self):
        self.menu_schema()
        legacy = self.home / '.cinnamon/configs/menu@cinnamon.org/4.json'
        legacy.parent.mkdir(parents=True)
        legacy.write_text(json.dumps({'new-version-setting': {'value': 78}}))
        self.apply_menu(['panel1:left:0:menu@cinnamon.org:4'])
        target = self.config / 'cinnamon/spices/menu@cinnamon.org/4.json'
        self.assertEqual(json.loads(target.read_text())['new-version-setting']['value'], 78)
        self.assertTrue(legacy.exists())

    def test_disabled_menu_is_not_reenabled_or_given_instance_zero(self):
        self.menu_schema()
        self.apply_menu(['panel1:left:0:other@cinnamon.org:2'])
        self.assertFalse((self.config / 'cinnamon').exists())

    def test_schema_overrides_match_cinnamon_checksum(self):
        schema = self.menu_schema()
        override = schema.with_name('settings-override.json')
        override.write_text(json.dumps({'new-version-setting': {'override-props': True, 'default': 87}}))
        self.apply_menu(['panel1:left:0:menu@cinnamon.org:1'])
        target = self.config / 'cinnamon/spices/menu@cinnamon.org/1.json'
        result = json.loads(target.read_text())
        self.assertEqual(result['new-version-setting']['value'], 87)
        self.assertEqual(result['__md5__'], hashlib.md5(schema.read_bytes()).hexdigest() +
                         hashlib.md5(override.read_bytes()).hexdigest())

    def test_package_fallback_continues_after_install_failure(self):
        self.bash('''package_available() { [ "$1" != unavailable ]; }
sudo() { printf '%s\n' "$*" >> "$REBUILD_TEST_LOG"; [[ "$*" == *good ]]; }
install_first_available_package unavailable broken good''')
        result = self.log.read_text()
        self.assertIn('install -y broken', result)
        self.assertIn('install -y good', result)
        self.assertNotIn('install -y unavailable', result)

    def test_failed_package_candidates_return_failure(self):
        self.bash('''package_available() { return 0; }
sudo() { return 1; }
install_first_available_package broken bad''', success=False)

    def test_cron_preserves_jobs_and_is_idempotent_in_both_modes(self):
        original = self.cron.read_text()
        self.bash('''BACKUP_DIR="$REBUILT_MACHINE_BACKUP_DIR"
HEADLESS_MODE=true
install_rebuilt_cron
install_rebuilt_cron''')
        headless = self.cron.read_text()
        self.assertIn(original, headless)
        self.assertEqual(headless.count('start-qortal-core.sh'), 1)
        self.assertEqual(headless.count('auto-fix-qortal.sh'), 2)
        self.bash('''BACKUP_DIR="$REBUILT_MACHINE_BACKUP_DIR"
HEADLESS_MODE=false
install_rebuilt_cron
install_rebuilt_cron''')
        gui = self.cron.read_text()
        self.assertIn(original, gui)
        self.assertNotIn('@reboot', gui)
        self.assertEqual(gui.count('auto-fix-qortal.sh'), 1)

    def test_cron_read_error_does_not_replace_schedule(self):
        original = self.cron.read_text()
        self.bash('HEADLESS_MODE=false; install_rebuilt_cron', success=False,
                  extra_env={'REBUILD_TEST_CRON_ERROR': '1'})
        self.assertEqual(self.cron.read_text(), original)
        self.assertFalse(self.log.exists())

    def test_download_rejects_bad_scripts_and_keeps_installed_file(self):
        target = self.home / 'helper.sh'
        target.write_text('#!/bin/bash\necho original\n')
        self.bash('''curl() { printf '<html>error</html>' > "${@: -2:1}"; }
wget() { return 1; }
download_with_retry https://example.invalid/helper.sh "$HOME/helper.sh" 1''', success=False)
        self.assertEqual(target.read_text(), '#!/bin/bash\necho original\n')
        self.assertFalse(list(self.home.glob('*.part.*')))

    def test_repository_helper_prefers_checkout_without_network(self):
        self.bash('install_repo_file start-qortal-core.sh "$HOME/start-qortal-core.sh"')
        self.assertEqual((self.home / 'start-qortal-core.sh').read_text(),
                         (ROOT / 'start-qortal-core.sh').read_text())

    def test_applet_archive_installs_without_extra_nested_folder(self):
        archive = self.root / 'applet.zip'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('Sensors@claudiux/metadata.json', '{}')
            z.writestr('Sensors@claudiux/applet.js', 'applet')
        self.bash('''download_with_retry() { cp "$TEST_ARCHIVE" "$2"; }
install_sensors_applet''', extra_env={'TEST_ARCHIVE': str(archive)})
        target = self.data / 'cinnamon/applets/Sensors@claudiux'
        self.assertTrue((target / 'applet.js').is_file())
        self.assertFalse((target / 'Sensors@claudiux').exists())

    def test_machine_bundle_only_installs_artwork(self):
        archive = self.root / 'machine.zip'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('Machine-files/Pictures/wallpapers/qortal.png', 'artwork')
            z.writestr('Machine-files/auto-fix-qortal.sh', 'old helper')
            z.writestr('Machine-files/.config/autostart/old.desktop', 'old launcher')
        installed = self.home / 'auto-fix-qortal.sh'
        installed.write_text('new helper')
        self.bash('''download_with_retry() { cp "$TEST_ARCHIVE" "$2"; }
install_machine_artwork''', extra_env={'TEST_ARCHIVE': str(archive)})
        self.assertEqual(installed.read_text(), 'new helper')
        self.assertTrue((self.home / 'Pictures/wallpapers/qortal.png').is_file())
        self.assertFalse((self.home / '.config').exists())

    def test_core_launcher_works_from_unrelated_directory(self):
        core = self.home / 'qortal'
        core.mkdir()
        start = core / 'start.sh'
        start.write_text(f'#!{BASH}\npwd\nprintf "%s\\n" "$@"\n')
        start.chmod(0o755)
        result = subprocess.run([BASH, str(ROOT / 'start-qortal-core.sh'), 'one argument'],
                                env=self.env, cwd='/', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [str(core), 'one argument'])

    def test_launchers_validate_with_spaces_in_home(self):
        self.bash('install_desktop_launchers')
        if shutil.which('desktop-file-validate'):
            for path in list(self.data.rglob('*.desktop')) + list(self.config.rglob('*.desktop')):
                result = subprocess.run(['desktop-file-validate', str(path)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        auto = (self.config / 'autostart/auto-fix-qortal-GUI.desktop').read_text()
        self.assertIn('"--delay" "420"', auto)
        self.assertNotIn('X-GNOME-Autostart-Delay', auto)
        self.assertIn('OnlyShowIn=X-Cinnamon;', (self.config / 'autostart/apply-cinnamon-settings.desktop').read_text())

    def test_desktop_exec_launches_reserved_path_characters_through_gio(self):
        target = self.home / 'record $cash %percent "quote".py'
        target.write_text(f'#!{sys.executable}\nimport os,json,sys\n'
                          'open(os.environ["EXEC_RESULT"],"w").write(json.dumps(sys.argv))\n')
        target.chmod(0o755)
        command = self.bash('desktop_exec "$TEST_TARGET" "two words"',
                            extra_env={'TEST_TARGET': str(target)}).stdout
        desktop = self.home / 'check.desktop'
        desktop.write_text('[Desktop Entry]\nType=Application\nName=Check\nTerminal=false\nExec=' + command)
        verify = '''import sys
try:
    import gi
    from gi.repository import Gio
except (ImportError, ValueError):
    sys.exit(77)
import time, pathlib, json, os
app = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
assert app
app.launch([], None)
path = pathlib.Path(os.environ['EXEC_RESULT'])
for _ in range(50):
    if path.exists(): break
    time.sleep(.02)
assert json.loads(path.read_text()) == [os.environ['TEST_TARGET'], 'two words']
'''
        result = subprocess.run(['/usr/bin/python3', '-c', verify, str(desktop)],
                                env={**self.env, 'TEST_TARGET': str(target),
                                     'EXEC_RESULT': str(self.home / 'result.json')},
                                text=True, capture_output=True, timeout=5)
        if result.returncode == 77:
            self.skipTest('GIO bindings are unavailable')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_preferences_use_installed_apps_and_active_terminal_profile(self):
        apps = self.data / 'applications'
        apps.mkdir(parents=True)
        for name in ('org.gnome.TextEditor.desktop', 'org.gnome.Papers.desktop',
                     'org.gnome.Loupe.desktop', 'org.gnome.gedit.desktop', 'nemo.desktop'):
            (apps / name).touch()
        self.bash('bash "$PREFERENCES_HELPER"', extra_env={
            'PREFERENCES_HELPER': str(ROOT / 'configure-terminal-and-more.sh'),
            'XDG_DATA_DIRS': str(self.root / 'empty')})
        calls = self.log.read_text()
        self.assertIn('mime default org.gnome.TextEditor.desktop text/plain', calls)
        self.assertIn('mime default org.gnome.Papers.desktop application/pdf', calls)
        self.assertIn('dconf load /org/gnome/gedit/\n', calls)
        self.assertNotIn('/org/gnome/gedit/preferences/', calls)
        self.assertIn('dconf load /org/gnome/terminal/legacy/profiles:/:11111111-2222-3333-4444-555555555555/', calls)
        self.assertNotIn('mime default vlc.desktop', calls)

    def test_complete_headless_rebuild_with_mocked_system_commands(self):
        checkout = self.root / 'checkout'
        checkout.mkdir()
        for name in ('rebuilt-machine.sh', 'auto-fix-qortal.sh', 'refresh-qortal.sh',
                     'check-qortal-status.sh', 'start-qortal-core.sh'):
            shutil.copy2(ROOT / name, checkout / name)
        (checkout / 'Qortal-Setup-Linux.sh').write_text(
            '#!/bin/bash\nprintf "setup automation=%s\\n" "$QSL_INSTALL_AUTOMATION" >> "$REBUILD_TEST_LOG"\n')
        (checkout / 'create-icon-theme-uni.sh').write_text('#!/bin/bash\nexit 0\n')
        self.bash('''source "$TEST_CHECKOUT/rebuilt-machine.sh"
id() { echo 1000; }
package_available() { return 0; }
install_machine_artwork() { return 0; }
main''', extra_env={'TEST_CHECKOUT': str(checkout), 'REBUILT_MACHINE_HEADLESS': '1'})
        calls = self.log.read_text()
        self.assertIn('setup automation=0', calls)
        self.assertNotIn('sudo reboot', calls)
        self.assertNotIn('gsettings', calls)
        self.assertFalse((self.config / 'autostart').exists())
        self.assertIn('@reboot', self.cron.read_text())

    def test_complete_desktop_rebuild_and_first_login_with_mocked_commands(self):
        self.menu_schema()
        checkout = self.root / 'checkout'
        checkout.mkdir()
        for name in ('rebuilt-machine.sh', 'apply-cinnamon-settings.sh', 'cinnamon-settings.json',
                     'configure-terminal-and-more.sh', 'auto-fix-qortal.sh', 'refresh-qortal.sh',
                     'check-qortal-status.sh', 'start-qortal-core.sh'):
            shutil.copy2(ROOT / name, checkout / name)
        (checkout / 'Qortal-Setup-Linux.sh').write_text('#!/bin/bash\nexit 0\n')
        (checkout / 'create-icon-theme-uni.sh').write_text('#!/bin/bash\nexit 0\n')
        self.bash('''source "$TEST_CHECKOUT/rebuilt-machine.sh"
id() { echo 1000; }
package_available() { return 0; }
install_machine_artwork() { return 0; }
install_sensors_applet() { return 0; }
install_desktop_themes() { return 0; }
main''', extra_env={'TEST_CHECKOUT': str(checkout), 'REBUILT_MACHINE_HEADLESS': '0',
                    'REBUILD_TEST_APPLETS': "['panel1:left:0:menu@cinnamon.org:7']"})
        self.assertIn('Session = cinnamon', (self.home / '.dmrc').read_text())
        once = self.config / 'autostart/apply-cinnamon-settings.desktop'
        self.assertTrue(once.exists())
        self.assertTrue((self.config / 'autostart/auto-fix-qortal-GUI.desktop').exists())
        self.stub('sleep', 'exit 0\n')
        self.bash('bash "$HOME/apply-cinnamon-settings.sh" --first-login', extra_env={
            'REBUILD_TEST_APPLETS': "['panel1:left:0:menu@cinnamon.org:7']"})
        self.assertFalse(once.exists())
        settings = self.config / 'cinnamon/spices/menu@cinnamon.org/7.json'
        self.assertEqual(json.loads(settings.read_text())['menu-icon-size']['value'], 40)
        self.assertNotIn('sudo reboot', self.log.read_text())

    def test_failed_required_update_stops_before_core_setup(self):
        self.bash('''id() { echo 1000; }
sudo() { [[ "$*" != *update* ]]; }
ensure_qortal_setup_script() { echo UNEXPECTED_CORE_SETUP; }
main''', success=False, extra_env={'REBUILT_MACHINE_HEADLESS': '1'})
        self.assertNotIn('auto-fix-qortal.sh', self.cron.read_text())

    def test_hub_launcher_retains_fuse_extraction_fallback(self):
        # Exercise the real installer launcher-writing section without installing Core/Hub.
        script = (ROOT / 'Qortal-Setup-Linux.sh').read_text()
        section = script.split('HUB_LAUNCHER_PREFIX=""', 1)[1].split(
            'echo -e "${CYAN}🧩 Creating Qortal Core launcher', 1)[0]
        apps = self.home / '.local/share/applications'
        apps.mkdir(parents=True)
        self.bash('''QORTAL_HUB_DIR="$HOME/qortal-hub"
SANDBOX_FLAG=" --no-sandbox"
HUB_LAUNCHER_PREFIX=""
''' + section, extra_env={'APPIMAGE_EXTRACT_AND_RUN': '1'})
        launcher = apps / 'qortal-hub.desktop'
        self.assertIn(f'Exec=env APPIMAGE_EXTRACT_AND_RUN=1 "{self.home}/qortal-hub/Qortal-Hub" --no-sandbox',
                      launcher.read_text())
        if shutil.which('desktop-file-validate'):
            result = subprocess.run(['desktop-file-validate', str(launcher)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
