"""Isolated launcher icon regressions: no network or desktop settings changes."""

import configparser
import os
import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile
import zlib


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
                        'cat', 'tr', 'touch', 'cp', 'python3'):
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
        self.assertEqual(index['Icon Theme']['Inherits'].split(',')[-1], 'hicolor')
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

    def test_preserve_rebuild_repairs_duplicate_index_and_zero_byte_icons(self):
        self.local_sources()
        (self.source / 'qortal-menu-button-2.png').write_bytes(b'')
        (self.theme / '48x48/apps').mkdir(parents=True)
        (self.theme / 'index.theme').write_text(
            '[Icon Theme]\nName=Yaru-blue-qortal\nDirectories=scalable/apps\n'
            'Directories=\nInherits=Yaru-blue-qortal,hicolor\n'
            '[scalable/apps]\nSize=48\nType=Scalable\nContext=Applications\n')
        (self.theme / '48x48/apps/qortal-menu-button-2.png').touch()
        self.fallback.mkdir(parents=True)
        (self.fallback / 'qortal-hub.png').touch()
        self.run_helper(QORTAL_ICONS_PRESERVE_EXISTING='1', QORTAL_ICONS_SELECT_THEME='0')
        self.assert_icons()
        self.assertTrue((self.source / 'qortal-menu-button-2.png').stat().st_size)
        before = (self.theme / 'index.theme').read_bytes()
        self.assertNotIn('Inherits=Yaru-blue-qortal', before.decode())
        index = configparser.ConfigParser(interpolation=None)
        index.read_string(before.decode())
        self.assertEqual(set(index['Icon Theme']['Directories'].split(',')), {'48x48/apps', 'scalable/apps'})
        self.run_helper(QORTAL_ICONS_PRESERVE_EXISTING='1', QORTAL_ICONS_SELECT_THEME='0')
        self.assertEqual((self.theme / 'index.theme').read_bytes(), before)
        self.assertEqual(len(list((self.home / 'backups/qortal-icons').glob('qortal-index-*.theme'))), 1)

    def test_gtk_resolves_and_renders_qortal_icons_at_requested_menu_sizes(self):
        self.local_sources()
        def chunk(kind, data):
            return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
        png = (b'\x89PNG\r\n\x1a\n' +
               chunk(b'IHDR', struct.pack('!2I5B', 48, 48, 8, 6, 0, 0, 0)) +
               chunk(b'IDAT', zlib.compress((b'\x00' + b'\x00\x80\xff\xff' * 48) * 48)) +
               chunk(b'IEND', b''))
        for source in self.source.glob('*.png'):
            source.write_bytes(png)
        self.theme.mkdir(parents=True)
        (self.theme / 'index.theme').write_text('[Icon Theme]\nDirectories=\n')
        self.run_helper(QORTAL_ICONS_PRESERVE_EXISTING='1', QORTAL_ICONS_SELECT_THEME='0')
        code = '''import os, pathlib, sys
try:
    import gi
    gi.require_version('Gtk', '3.0')
    from gi.repository import Gtk
except (ImportError, ValueError):
    sys.exit(77)
home = pathlib.Path.home()
icons = Gtk.IconTheme.new()
icons.set_search_path([str(home / '.icons'), str(pathlib.Path(os.environ['XDG_DATA_HOME']) / 'icons')])
icons.set_custom_theme('Yaru-blue-qortal')
for name in ('qortal', 'qortal-hub', 'qortal-ui', 'qortal-menu-button-2'):
    for size in (26, 36, 40):
        icon = icons.lookup_icon(name, size, Gtk.IconLookupFlags.FORCE_SIZE)
        assert icon and 'Yaru-blue-qortal/48x48/apps/' in icon.get_filename(), (name, size)
        assert icon.load_icon().get_width() == size, (name, size)
'''
        result = subprocess.run(['/usr/bin/python3', '-c', code], env=self.env,
                                capture_output=True, text=True, timeout=10)
        if result.returncode == 77:
            self.skipTest('GTK 3 Python bindings unavailable')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

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

    def test_preserve_mode_keeps_custom_artwork_icons_and_theme_selection(self):
        # Partial sources force the download/merge path without replacing the
        # user's existing source, generated icon or valid custom theme entries.
        self.source.mkdir(parents=True)
        (self.source / 'qortal.png').write_bytes(b'personal source')
        (self.theme / '48x48/apps').mkdir(parents=True)
        (self.theme / 'index.theme').write_text(
            '[Icon Theme]\nName=Personal Qortal\nDirectories=custom/apps\nInherits=Adwaita,hicolor\n'
            '[custom/apps]\nSize=96\nType=Fixed\nContext=Applications\n')
        (self.theme / '48x48/apps/qortal.png').write_bytes(b'personal icon')
        self.fallback.mkdir(parents=True)
        (self.fallback / 'qortal.png').write_bytes(b'personal fallback')
        self.run_helper(QORTAL_ICONS_PRESERVE_EXISTING='1', QORTAL_ICONS_SELECT_THEME='0')
        self.assertEqual((self.source / 'qortal.png').read_bytes(), b'personal source')
        index = configparser.ConfigParser(interpolation=None)
        index.read(self.theme / 'index.theme')
        self.assertEqual(index['Icon Theme']['Name'], 'Personal Qortal')
        self.assertIn('custom/apps', index['Icon Theme']['Directories'])
        self.assertEqual(index['custom/apps']['Size'], '96')
        self.assertIn('48x48/apps', index['Icon Theme']['Directories'])
        self.assertEqual(len(list((self.home / 'backups/qortal-icons').glob('qortal-index-*.theme'))), 1)
        self.assertEqual((self.theme / '48x48/apps/qortal.png').read_bytes(), b'personal icon')
        self.assertEqual((self.fallback / 'qortal.png').read_bytes(), b'personal fallback')
        self.assertTrue((self.fallback / 'qortal-hub.png').exists())
        self.assertNotIn('set org.', self.log.read_text())

    def test_rebuild_propagates_download_and_helper_failures(self):
        functions = self.root / 'rebuild-functions.sh'
        functions.write_text((ROOT / 'rebuilt-machine.sh').read_text())
        (self.root / 'create-icon-theme-uni.sh').write_text('#!/bin/bash\nexit 7\n')
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

    def test_apply_cinnamon_settings_preserves_icons_but_continues_when_helper_fails(self):
        settings = self.root / 'apply-settings.sh'
        settings.write_text((ROOT / 'apply-cinnamon-settings.sh').read_text())
        shutil.copy2(ROOT / 'cinnamon-settings.json', self.root / 'cinnamon-settings.json')
        (self.root / 'create-icon-theme-uni.sh').write_text('exit 7\n')
        (self.bin / 'bash').symlink_to(BASH)
        for command in ('dirname', 'grep', 'sed', 'id'):
            (self.bin / command).symlink_to(shutil.which(command))
        self.stub('pgrep', 'exit 1\n')
        self.stub('xrandr', 'echo "Monitors: 1"\n')
        self.stub('gsettings', '''printf '%s\\n' "$*" >> "$ICON_TEST_LOG"
state="$TMPDIR/${2:-}.${3:-}"
case "$1" in
  set) printf '%s' "$4" > "$state" ;;
  get)
    if [ "$2" = org.cinnamon ]; then echo '[]'
    else python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); v=p.read_text() if p.exists() else ""; print(v if v in ("true", "false") else repr(v))' "$state"; fi ;;
  list-schemas) printf '%s\\n' org.cinnamon.desktop.background org.gnome.desktop.interface ;;
  list-keys) printf '%s\\n' picture-uri picture-options color-scheme ;;
esac
''')
        for theme, component in (('yaru-blue-qortal', 'gtk-3.0/gtk.css'),
                                 ('windows-10-dark', 'metacity-1/metacity-theme-3.xml'),
                                 ('windows-10-dark', 'cinnamon/cinnamon.css')):
            asset = self.home / '.themes' / theme / component
            asset.parent.mkdir(parents=True, exist_ok=True)
            asset.write_text('theme component')
        wallpaper = self.home / 'Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png'
        wallpaper.parent.mkdir(parents=True)
        wallpaper.write_bytes(b'wallpaper')
        schema = self.root / 'menu-schema.json'
        schema.write_text('{}')
        result = subprocess.run([BASH, str(settings)],
                                env={**self.env, 'DISPLAY': ':99',
                                     'CINNAMON_MENU_SCHEMA': str(schema),
                                     'XDG_CONFIG_HOME': str(self.home / 'config'),
                                     'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/mock/session'}, cwd=self.home,
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Qortal icon installation failed', result.stderr)
        calls = self.log.read_text()
        self.assertNotIn('icon-theme', calls)
        self.assertIn('set org.cinnamon.desktop.interface gtk-theme yaru-blue-qortal', calls)
        self.assertIn('set org.cinnamon.desktop.wm.preferences theme windows-10-dark', calls)
        self.assertIn('set org.gnome.desktop.interface color-scheme prefer-dark', calls)
        self.assertIn(f'set org.cinnamon.desktop.background picture-uri {wallpaper.as_uri()}', calls)
        self.assertIn('nemo-icon-view-auto-layout=false',
                      (self.home / 'config/nemo/desktop-metadata').read_text())


if __name__ == '__main__':
    unittest.main()
