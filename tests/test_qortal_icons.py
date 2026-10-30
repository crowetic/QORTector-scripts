"""Isolated launcher icon regressions: no network or desktop settings changes."""

import configparser
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
NAMES = ('qortal', 'qortal-hub', 'qortal-ui', 'qortal-menu-button',
         'qortal-menu-button-2', 'qortal-menu-button-3', 'qortal-menu-button-4')
BASH = shutil.which('bash')


@unittest.skipUnless(BASH and shutil.which('rsync') and shutil.which('unzip'),
                     'bash, rsync and unzip are required')
class QortalIconTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='qortal-icons-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / 'desktop user'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.system = self.root / 'system-icons'
        (self.system / 'Yaru-dark').mkdir(parents=True)
        (self.system / 'Yaru-dark/index.theme').write_text(
            '[Icon Theme]\nName=Yaru-dark\nInherits=Yaru,hicolor\nDirectories=\n')
        self.script = self.root / 'helper.sh'
        self.script.write_text((ROOT / 'create-icon-theme-uni.sh').read_text().replace(
            '/usr/share/icons', str(self.system)))
        self.source = self.home / 'Pictures/icons/icons_theme'
        self.theme = self.home / '.icons/Yaru-blue-qortal'
        self.data = self.home / 'custom data'
        self.fallback = self.data / 'icons/hicolor/48x48/apps'
        self.log = self.root / 'calls.log'
        self.archive = self.root / 'complete.zip'
        self.make_archive(self.archive)
        # Restrict PATH so the ImageMagick 7 case genuinely has no convert.
        for command in ('rsync', 'unzip', 'mktemp', 'rm', 'mkdir', 'install',
                        'cat', 'tr', 'touch', 'cp'):
            (self.bin / command).symlink_to(shutil.which(command))
        self.stub('magick', 'printf "magick\\n" >> "$ICON_TEST_LOG"\n'
                  'cp "$1" "${@: -1}"\n')
        self.stub('gsettings', 'printf "%s\\n" "$*" >> "$ICON_TEST_LOG"\n'
                  'exit "${ICON_TEST_SETTINGS_STATUS:-0}"\n')
        self.stub('gtk-update-icon-cache', 'exit 0\n')
        self.stub('curl', '''printf 'download\n' >> "$ICON_TEST_LOG"
out=""
url="${*: -1}"
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out="$2"; shift; fi
  shift
done
case "$url" in
  *cloud.qortal.org*) archive="$ICON_TEST_PRIMARY" ;;
  *) archive="$ICON_TEST_BACKUP" ;;
esac
cp "$archive" "$out"
''')
        self.env = {**os.environ, 'HOME': str(self.home), 'PATH': str(self.bin),
                    'XDG_DATA_HOME': str(self.data), 'XDG_CURRENT_DESKTOP': 'ubuntu:GNOME',
                    'TMPDIR': str(self.root), 'ICON_TEST_LOG': str(self.log),
                    'ICON_TEST_PRIMARY': str(self.archive),
                    'ICON_TEST_BACKUP': str(self.archive)}

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f'#!{BASH}\nset -eu\n' + body)
        path.chmod(0o755)

    def make_archive(self, path, names=NAMES):
        with zipfile.ZipFile(path, 'w') as archive:
            for name in names:
                archive.writestr(f'Pictures/icons/icons_theme/{name}.png', b'artwork')

    def local_sources(self):
        self.source.mkdir(parents=True, exist_ok=True)
        for name in NAMES:
            (self.source / f'{name}.png').write_bytes(b'artwork')

    def run_helper(self, success=True, **env):
        result = subprocess.run([BASH, str(self.script)], env={**self.env, **env},
                                capture_output=True, text=True, timeout=10)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def assert_icons(self):
        for name in NAMES:
            for directory in (self.theme / '48x48/apps', self.fallback):
                self.assertTrue((directory / f'{name}.png').stat().st_size)
        index = configparser.ConfigParser(interpolation=None, strict=True)
        index.read(self.theme / 'index.theme')
        self.assertIn('48x48/apps', index['Icon Theme']['Directories'].split(','))
        self.assertEqual(index['48x48/apps']['Context'], 'Applications')
        self.assertEqual(index['48x48/apps']['Size'], '48')
        self.assertIn('hicolor', index['Icon Theme']['Inherits'].split(','))
        self.assertFalse(list(self.root.glob('qortal-icons.*')))

    def test_imagemagick7_without_convert_and_composite_gnome(self):
        self.local_sources()
        self.run_helper()
        self.assert_icons()
        self.assertIn('set org.gnome.desktop.interface icon-theme Yaru-blue-qortal',
                      self.log.read_text())
        self.assertNotIn('download', self.log.read_text())

    def test_imagemagick6_and_cinnamon(self):
        (self.bin / 'magick').rename(self.bin / 'convert')
        self.local_sources()
        self.run_helper(XDG_CURRENT_DESKTOP='X-Cinnamon')
        self.assert_icons()
        self.assertIn('set org.cinnamon.desktop.interface icon-theme Yaru-blue-qortal',
                      self.log.read_text())

    def test_fresh_home_download_creates_pictures(self):
        self.assertFalse(self.source.exists())
        self.run_helper()
        self.assert_icons()
        self.assertTrue(self.source.is_dir())

    def test_partial_source_merges_existing_directories(self):
        self.source.mkdir(parents=True)
        (self.source / 'qortal.png').touch()
        unrelated = self.home / 'Pictures/icons/my-own-icon.png'
        unrelated.write_bytes(b'keep')
        self.run_helper()
        self.assert_icons()
        self.assertEqual(unrelated.read_bytes(), b'keep')

    def test_html_primary_uses_backup(self):
        invalid = self.root / 'html-response'
        invalid.write_text('<html>Service unavailable</html>')
        self.run_helper(ICON_TEST_PRIMARY=str(invalid))
        self.assert_icons()
        self.assertEqual(self.log.read_text().count('download'), 2)

    def test_incomplete_archive_uses_backup(self):
        incomplete = self.root / 'incomplete.zip'
        self.make_archive(incomplete, NAMES[:1])
        self.run_helper(ICON_TEST_PRIMARY=str(incomplete))
        self.assert_icons()
        self.assertEqual(self.log.read_text().count('download'), 2)

    def test_failed_download_preserves_installed_theme_and_settings(self):
        self.theme.mkdir(parents=True)
        original = self.theme / 'index.theme'
        original.write_text('previous theme')
        invalid = self.root / 'invalid.zip'
        invalid.write_text('not a ZIP')
        self.run_helper(success=False, ICON_TEST_PRIMARY=str(invalid),
                        ICON_TEST_BACKUP=str(invalid))
        self.assertEqual(original.read_text(), 'previous theme')
        self.assertNotIn('set org.', self.log.read_text())
        self.assertFalse(self.fallback.exists())

    def test_conversion_failure_does_not_select_or_replace_theme(self):
        self.local_sources()
        self.theme.mkdir(parents=True)
        original = self.theme / 'index.theme'
        original.write_text('previous theme')
        self.stub('magick', 'exit 2\n')
        self.run_helper(success=False)
        self.assertEqual(original.read_text(), 'previous theme')
        self.assertFalse(self.log.exists())
        self.assertFalse(self.fallback.exists())

    def test_rerun_repairs_broken_index_and_preserves_unrelated_icons(self):
        self.local_sources()
        self.theme.mkdir(parents=True)
        (self.theme / 'index.theme').write_text('[Icon Theme]\nDirectories=\n')
        self.fallback.mkdir(parents=True)
        unrelated = self.fallback / 'another-app.png'
        unrelated.write_bytes(b'keep')
        self.run_helper()
        self.run_helper()
        self.assert_icons()
        self.assertEqual(unrelated.read_bytes(), b'keep')

    def test_headless_or_failed_settings_still_installs_fallback(self):
        self.local_sources()
        for desktop in ('', 'ubuntu:GNOME', 'X-Cinnamon'):
            with self.subTest(desktop=desktop):
                self.run_helper(XDG_CURRENT_DESKTOP=desktop, ICON_TEST_SETTINGS_STATUS='1')
                self.assert_icons()

    def test_absent_yaru_uses_hicolor(self):
        shutil.rmtree(self.system)
        self.local_sources()
        self.run_helper(XDG_CURRENT_DESKTOP='')
        self.assert_icons()
        self.assertIn('Inherits=hicolor\n', (self.theme / 'index.theme').read_text())

    def test_rebuild_propagates_download_and_helper_failures(self):
        functions = self.root / 'rebuild-functions.sh'
        functions.write_text((ROOT / 'rebuilt-machine.sh').read_text())
        for install in ('return 1', 'printf "exit 7\\n" > "$2"'):
            with self.subTest(install=install):
                code = ('source "$TASK_FUNCTIONS"\n'
                        f'install_repo_file() {{ {install}; }}\n'
                        'if install_qortal_icons; then exit 99; fi\n')
                result = subprocess.run([BASH, '-c', code], capture_output=True,
                                        text=True, timeout=10,
                                        env={**self.env, 'PATH': os.environ['PATH'],
                                             'TASK_FUNCTIONS': str(functions)})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(self.log.exists())

    def test_apply_cinnamon_settings_preserves_theme_when_helper_fails(self):
        settings = self.root / 'apply-settings.sh'
        settings.write_text((ROOT / 'apply-cinnamon-settings.sh').read_text())
        (self.root / 'create-icon-theme-uni.sh').write_text('exit 7\n')
        (self.bin / 'bash').symlink_to(BASH)
        for command in ('dirname',):
            (self.bin / command).symlink_to(shutil.which(command))
        result = subprocess.run([BASH, str(settings)], env=self.env, cwd=self.home,
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Qortal icon installation failed', result.stderr)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
