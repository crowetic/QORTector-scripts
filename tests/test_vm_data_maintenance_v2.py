"""Isolated guest maintenance checks; all maintenance commands are mocked."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
GUEST = ROOT / 'vm-data-maintenance-v2'
SCRIPT = GUEST / 'vm-data-maintenance-v2.sh'
INSTALLER = GUEST / 'install.sh'

# Simulate root ownership for fixture paths without requiring root or changing
# host ownership. Tests still use real modes, symlinks, files and flock locks.
HARNESS = r'''
source "$REVIEW_SCRIPT"
CONFIG_FILE="$TEST_ROOT/config"
RUNTIME_DIR="$TEST_ROOT/runtime"
require_root() { :; }
stat() {
  local metadata owner permissions path="${*: -1}"
  metadata=$(command stat "$@") || return 1
  read -r owner permissions <<< "$metadata"
  owner=0
  [ "$path" != "${NONROOT_PATH:-}" ] || owner=1000
  [ "$path" != /tmp ] || permissions=755
  printf '%s %s\n' "$owner" "$permissions"
}
record() { printf '%s\n' "$*" >> "$TEST_ROOT/events"; }
df() {
  record df "$@"
  local percent=45
  [[ "${*: -1}" != /data ]] || percent=95
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
  printf '/dev/mock 100 45 55 %s%% /\n' "$percent"
}
docker() { record docker "$@"; }
journalctl() { record journalctl "$@"; }
apt-get() { record apt-get "$@"; }
systemd-tmpfiles() { record systemd-tmpfiles "$@"; }
fstrim() { record fstrim "$@"; }
mountpoint() { [[ "${*: -1}" != "${BAD_MOUNT:-}" ]]; }
'''


class GuestMaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nuqloud-guest-test-')
        self.root = pathlib.Path(self.temp.name)
        self.config = self.root / 'config'
        self.config.write_text('')
        self.config.chmod(0o644)
        self.events = self.root / 'events'
        self.events.write_text('')
        self.env = {**os.environ, 'REVIEW_SCRIPT': str(SCRIPT),
                    'TEST_ROOT': str(self.root)}

    def tearDown(self):
        self.temp.cleanup()

    def bash(self, code, success=True, extra_env=None):
        result = subprocess.run(['bash', '-c', HARNESS + '\n' + code],
                                env={**self.env, **(extra_env or {})},
                                text=True, capture_output=True, timeout=10)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def commands(self):
        return self.events.read_text().splitlines()

    def test_cli_help_and_invalid_arguments_need_no_root_or_config(self):
        for args, status in [(['--help'], 0), (['--unknown'], 2),
                             (['--mode'], 2), (['--config'], 2),
                             (['--mode', 'invalid'], 2)]:
            with self.subTest(args=args):
                result = subprocess.run(['bash', str(SCRIPT), *args],
                                        text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, status)
                self.assertIn('Usage:', result.stdout + result.stderr)

    def test_actual_nonroot_invocation_refuses_maintenance(self):
        if os.geteuid() == 0:
            self.skipTest('Requires a nonroot test process')
        result = subprocess.run(['bash', str(SCRIPT), '--mode', 'daily'],
                                text=True, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Run as root', result.stderr)

    def test_missing_config_never_enables_defaults(self):
        result = self.bash('main --mode daily --config "$TEST_ROOT/missing"', success=False)
        self.assertIn('Config missing', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_nonroot_config_is_rejected_before_source(self):
        self.config.write_text('record CONFIG_EXECUTED\n')
        result = self.bash('main --mode report', success=False,
                           extra_env={'NONROOT_PATH': str(self.config)})
        self.assertIn('root-owned', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_writable_config_or_parent_is_rejected_before_source(self):
        self.config.write_text('record CONFIG_EXECUTED\n')
        for path in [self.config, self.root]:
            with self.subTest(path=path):
                original = path.stat().st_mode & 0o777
                path.chmod(0o777)
                try:
                    result = self.bash('main --mode daily', success=False)
                    self.assertIn('writable by group/others', result.stderr)
                    self.assertEqual(self.commands(), [])
                finally:
                    path.chmod(original)

    def test_symlink_config_and_parent_are_rejected(self):
        folder = self.root / 'real'
        folder.mkdir()
        (folder / 'config').write_text('record CONFIG_EXECUTED\n')
        (self.root / 'linked').symlink_to(folder, target_is_directory=True)
        (self.root / 'file-link').symlink_to(folder / 'config')
        for path in ['linked/config', 'file-link']:
            with self.subTest(path=path):
                self.bash(f'main --mode daily --config "$TEST_ROOT/{path}"', success=False)
                self.assertEqual(self.commands(), [])

    def test_invalid_config_never_runs_maintenance(self):
        cases = ['ENABLE_TRIM=2', 'WARN_GUEST_PERCENT=08', 'WARN_GUEST_PERCENT=0',
                 'CRIT_GUEST_PERCENT=101', 'WARN_GUEST_PERCENT=95',
                 'JOURNAL_MAX_AGE=0d', 'JOURNAL_MAX_AGE=""', 'JOURNAL_MAX_SIZE=0',
                 'JOURNAL_MAX_SIZE=-1M', 'DOCKER_BUILD_CACHE_MIN_AGE=0h',
                 'DOCKER_BUILD_CACHE_MIN_AGE=all', 'TRIM_MOUNTS=( relative )',
                 'TRIM_MOUNTS=()', 'unset TRIM_MOUNTS; TRIM_MOUNTS=/',
                 'REPORT_PATHS=()', 'REPORT_PATHS=( relative )']
        for config in cases:
            with self.subTest(config=config):
                self.config.write_text(config + '\n')
                self.bash('main --mode weekly', success=False)
                self.assertEqual(self.commands(), [])

    def test_daily_defaults_only_vacuum_archived_journals(self):
        self.bash('main --mode daily')
        actions = [line for line in self.commands() if not line.startswith(('df ', 'docker '))]
        self.assertEqual(actions, ['journalctl --vacuum-time=10d --vacuum-size=200M'])
        self.assertIn('docker system df', self.commands())
        self.assertTrue(any(line.startswith('docker stats --no-stream') for line in self.commands()))

    def test_config_cannot_override_cli_mode_dry_run_or_private_lock(self):
        for config in ['DRY_RUN=0', 'MODE=weekly', 'RUNTIME_DIR=/tmp']:
            with self.subTest(config=config):
                self.config.write_text(config + '\n')
                self.bash('main --mode report --dry-run', success=False)
                self.assertEqual(self.commands(), [])

    def test_weekly_defaults_only_autoclean_apt(self):
        self.bash('main --mode weekly')
        actions = [line for line in self.commands() if not line.startswith(('df ', 'docker '))]
        self.assertEqual(actions, ['apt-get -y autoclean'])
        self.assertFalse(any('prune' in line for line in self.commands()))

    def test_report_mode_never_cleans(self):
        self.bash('main --mode report')
        self.assertTrue(all(line.startswith(('df ', 'docker ')) for line in self.commands()))

    def test_dry_run_suppresses_every_enabled_cleanup(self):
        self.config.write_text('ENABLE_TMPFILES_CLEAN=1\nENABLE_DOCKER_BUILD_CACHE_PRUNE=1\n')
        for mode in ['trim', 'daily', 'weekly', 'report']:
            with self.subTest(mode=mode):
                self.events.write_text('')
                self.bash(f'main --mode {mode} --dry-run')
                self.assertTrue(all(line.startswith(('df ', 'docker system df', 'docker stats '))
                                    for line in self.commands()), self.commands())

    def test_opt_in_cleanup_only_uses_tmpfiles_and_build_cache(self):
        self.config.write_text('ENABLE_TMPFILES_CLEAN=1\nENABLE_DOCKER_BUILD_CACHE_PRUNE=1\n')
        self.bash('main --mode weekly')
        self.assertIn('systemd-tmpfiles --clean', self.commands())
        self.assertIn('docker builder prune --all --force --filter until=336h', self.commands())
        self.assertFalse(any('system prune' in line or 'volume prune' in line or
                             'image prune' in line or 'container prune' in line
                             for line in self.commands()))

    def test_all_mounts_are_checked_before_any_trim(self):
        self.config.write_text('TRIM_MOUNTS=( / /data )\n')
        result = self.bash('main --mode trim', success=False,
                           extra_env={'BAD_MOUNT': '/data'})
        self.assertIn('Not a mountpoint: /data', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_trim_failure_still_checks_other_valid_mounts_and_fails(self):
        self.config.write_text('TRIM_MOUNTS=( / /data )\n')
        result = self.bash('''fstrim() { record fstrim "$@"; [[ "${*: -1}" != / ]]; }
main --mode trim''', success=False)
        self.assertIn('fstrim -v -- /data', self.commands())
        self.assertIn('FAILED mode=trim', result.stderr)
        self.assertNotIn('COMPLETE', result.stdout)

    def test_disabled_trim_allows_empty_mount_array(self):
        self.config.write_text('ENABLE_TRIM=0\nTRIM_MOUNTS=()\n')
        self.bash('main --mode trim')
        self.assertEqual(self.commands(), [])

    def test_report_includes_separate_guest_data_path(self):
        self.config.write_text('REPORT_PATHS=( / /data )\n')
        result = self.bash('main --mode report')
        self.assertIn('df -hPT -- / /data', self.commands())
        self.assertIn('CRITICAL guest filesystem for /data at 95%', result.stderr)

    def test_df_failure_reports_error_without_hiding_daily_cleanup_result(self):
        result = self.bash('df() { return 1; }; main --mode daily', success=False)
        self.assertIn('Could not read filesystem usage', result.stderr)
        self.assertIn('journalctl --vacuum-time=10d --vacuum-size=200M', self.commands())
        self.assertIn('FAILED mode=daily', result.stderr)

    def test_docker_report_failure_marks_run_failed(self):
        result = self.bash('docker() { record docker "$@"; return 1; }; main --mode report', success=False)
        self.assertIn('docker system df failed', result.stderr)
        self.assertIn('docker stats failed', result.stderr)
        self.assertNotIn('COMPLETE', result.stdout)

    def test_weekly_failure_attempts_other_jobs_and_preserves_failure_status(self):
        self.config.write_text('ENABLE_TMPFILES_CLEAN=1\nENABLE_DOCKER_BUILD_CACHE_PRUNE=1\n')
        result = self.bash('apt-get() { record apt-get "$@"; return 1; }; main --mode weekly', success=False)
        self.assertIn('systemd-tmpfiles --clean', self.commands())
        self.assertIn('docker builder prune --all --force --filter until=336h', self.commands())
        self.assertIn('FAILED mode=weekly', result.stderr)

    def test_missing_opt_in_tool_is_not_silently_successful(self):
        self.config.write_text('ENABLE_DOCKER_BUILD_CACHE_PRUNE=1\nREPORT_DOCKER=0\n')
        result = self.bash('''command() {
  if [[ "$*" == '-v docker' ]]; then return 1; fi
  builtin command "$@"
}
main --mode weekly''', success=False)
        self.assertIn('Build-cache pruning enabled but Docker unavailable', result.stderr)

    def test_private_lock_directory_rejects_symlink_and_writable_directory(self):
        runtime = self.root / 'runtime'
        target = self.root / 'saved'
        target.mkdir()
        runtime.symlink_to(target, target_is_directory=True)
        self.bash('main --mode report', success=False)
        self.assertEqual(list(target.iterdir()), [])
        runtime.unlink()
        runtime.mkdir(mode=0o777)
        runtime.chmod(0o777)
        self.bash('main --mode report', success=False)
        self.assertEqual(self.commands(), [])

    def test_lock_file_symlink_cannot_truncate_another_file(self):
        runtime = self.root / 'runtime'
        runtime.mkdir(mode=0o700)
        saved = self.root / 'saved'
        saved.write_text('keep this')
        (runtime / 'maintenance.lock').symlink_to(saved)
        self.bash('main --mode report', success=False)
        self.assertEqual(saved.read_text(), 'keep this')

    def test_real_flock_prevents_overlapping_modes(self):
        first = subprocess.Popen(['bash', '-c', HARNESS + '\nacquire_lock\nprintf "ready\\n"\nread -r release'],
                                 env=self.env, text=True, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            self.assertEqual(first.stdout.readline().strip(), 'ready')
            result = self.bash('main --mode daily')
            self.assertIn('Already running', result.stdout)
            self.assertEqual(self.commands(), [])
        finally:
            first.communicate('release\n', timeout=5)
        self.bash('main --mode daily')
        self.assertTrue(self.commands())

    def test_systemd_guest_units_verify_in_staged_root(self):
        if not shutil.which('systemd-analyze'):
            self.skipTest('systemd-analyze unavailable')
        stage = self.root / 'system'
        units = stage / 'etc' / 'systemd' / 'system'
        units.mkdir(parents=True)
        for unit in (GUEST / 'systemd').iterdir():
            shutil.copyfile(unit, units / unit.name)
        # Minimal dependencies for offline verification, never loaded by PID 1.
        for name in ['sysinit', 'basic', 'shutdown', 'local-fs', 'timers']:
            (units / f'{name}.target').write_text('[Unit]\nDescription=Test target\nDefaultDependencies=no\n')
        installed = stage / 'usr' / 'local' / 'sbin' / SCRIPT.name
        installed.parent.mkdir(parents=True)
        shutil.copyfile(SCRIPT, installed)
        installed.chmod(0o755)
        result = subprocess.run(['systemd-analyze', '--root', str(stage),
                                 '--generators=no', '--man=no', 'verify',
                                 'vm-data-maintenance-v2@trim.service',
                                 'vm-data-maintenance-v2@daily.service',
                                 'vm-data-maintenance-v2@weekly.service',
                                 'vm-data-maintenance-v2-trim.timer',
                                 'vm-data-maintenance-v2-daily.timer',
                                 'vm-data-maintenance-v2-weekly.timer'],
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


INSTALL_HARNESS = HARNESS + r'''
source "$REVIEW_INSTALLER"
require_root() { :; }
BIN_DIR="$TEST_ROOT/bin"
CONFIG_DIR="$TEST_ROOT/etc"
UNIT_DIR="$TEST_ROOT/units"
INSTALL_RUNTIME_DIR="$TEST_ROOT/install-runtime"
install() {
  local args=()
  if [[ "${FAIL_INSTALL:-}" == 1 && "$*" == *vm-data-maintenance-v2.sh* ]]; then return 1; fi
  while (($#)); do
    case "$1" in -o|-g) shift 2;; *) args+=("$1"); shift;; esac
  done
  command install "${args[@]}"
}
systemctl() {
  printf '%s\n' "$*" >> "$TEST_ROOT/systemctl-events"
  case "$1" in
    show) [[ "${FAIL_SYSTEMD:-}" != 1 ]];;
    cat) [[ -f "$UNIT_DIR/${*: -1}" ]];;
    *) return 0;;
  esac
}
verify_installation() {
  [[ "${FAIL_VERIFY:-}" != 1 ]] || return 1
  local mode
  for mode in report trim daily weekly; do
    (
      source "$BIN_DIR/vm-data-maintenance-v2.sh"
      require_root() { :; }
      RUNTIME_DIR="$TEST_ROOT/guest-runtime"
      main --config "$CONFIG_DIR/vm-data-maintenance-v2.conf" --mode "$mode" --dry-run
    ) || return 1
  done
}
'''


class GuestInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='vm-data-install-test-')
        self.root = pathlib.Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.configs = self.root / 'etc'
        self.units = self.root / 'units'
        for folder in [self.bin, self.configs, self.units]:
            folder.mkdir(mode=0o755)
        self.new_config = self.configs / 'vm-data-maintenance-v2.conf'
        self.old_config = self.configs / 'nuqloud-vm-maintenance.conf'
        (self.root / 'events').write_text('')
        self.systemctl_events = self.root / 'systemctl-events'
        self.systemctl_events.write_text('')
        self.env = {**os.environ, 'REVIEW_SCRIPT': str(SCRIPT),
                    'REVIEW_INSTALLER': str(INSTALLER), 'TEST_ROOT': str(self.root)}

    def tearDown(self):
        self.temp.cleanup()

    def bash(self, args='', success=True, extra_env=None):
        result = subprocess.run(['bash', '-c', INSTALL_HARNESS + '\ninstall_main ' + args],
                                env={**self.env, **(extra_env or {})},
                                text=True, capture_output=True, timeout=15)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def legacy_install(self, config='REPORT_DOCKER=0\nWARN_GUEST_PERCENT=72\n'):
        self.old_config.write_text(config)
        self.old_config.chmod(0o600)
        (self.bin / 'nuqloud-vm-maintenance.sh').write_text('legacy script')
        for name in ['nuqloud-vm-maintenance@.service',
                     'nuqloud-vm-maintenance-trim.timer',
                     'nuqloud-vm-maintenance-daily.timer',
                     'nuqloud-vm-maintenance-weekly.timer']:
            (self.units / name).write_text('legacy unit')

    def test_fresh_install_without_enabling_timers(self):
        self.bash('--no-enable')
        self.assertEqual((self.bin / SCRIPT.name).read_bytes(), SCRIPT.read_bytes())
        self.assertEqual(self.new_config.read_bytes(), (GUEST / 'vm-data-maintenance-v2.conf.example').read_bytes())
        self.assertEqual(self.new_config.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.bin / SCRIPT.name).stat().st_mode & 0o777, 0o755)
        self.assertEqual({path.name for path in self.units.iterdir()},
                         {path.name for path in (GUEST / 'systemd').iterdir()})
        calls = self.systemctl_events.read_text()
        self.assertIn('daemon-reload', calls)
        self.assertNotIn('enable --now', calls)
        self.assertNotIn('fstrim.timer', calls)
        self.assertNotIn('proxmox', calls)

    def test_installer_help_requires_no_root_or_systemd(self):
        result = subprocess.run(['bash', str(INSTALLER), '--help'],
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--no-enable', result.stdout)

    def test_legacy_install_migrates_config_and_removes_old_names(self):
        self.legacy_install()
        config = self.old_config.read_bytes()
        self.bash()
        self.assertEqual(self.new_config.read_bytes(), config)
        self.assertFalse(self.old_config.exists())
        self.assertFalse((self.bin / 'nuqloud-vm-maintenance.sh').exists())
        self.assertEqual(list(self.units.glob('nuqloud*')), [])
        calls = self.systemctl_events.read_text()
        for mode in ['trim', 'daily', 'weekly']:
            self.assertIn(f'disable --now nuqloud-vm-maintenance-{mode}.timer', calls)
        self.assertIn('stop nuqloud-vm-maintenance@trim.service', calls)
        self.assertIn('enable --now vm-data-maintenance-v2-trim.timer', calls)
        self.assertLess(calls.index('disable --now'), calls.index('daemon-reload'))
        self.assertLess(calls.index('daemon-reload'), calls.index('enable --now'))

    def test_both_configs_preserve_new_and_backup_legacy(self):
        self.legacy_install()
        old = self.old_config.read_bytes()
        self.new_config.write_text('ENABLE_JOURNAL_VACUUM=0\n')
        self.new_config.chmod(0o600)
        current = self.new_config.read_bytes()
        self.bash('--no-enable')
        self.assertEqual(self.new_config.read_bytes(), current)
        backups = list(self.configs.glob('vm-data-maintenance-v2.conf.pre-migration.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), old)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
        self.assertFalse(self.old_config.exists())

    def test_reinstall_preserves_custom_config(self):
        self.bash('--no-enable')
        self.new_config.write_text('ENABLE_TRIM=0\nTRIM_MOUNTS=()\nREPORT_DOCKER=0\n')
        expected = self.new_config.read_bytes()
        self.bash('--no-enable')
        self.assertEqual(self.new_config.read_bytes(), expected)
        self.assertEqual(list(self.configs.glob('*.pre-migration.*')), [])

    def test_failed_verification_keeps_legacy_files_and_schedules(self):
        self.legacy_install()
        expected = self.old_config.read_bytes()
        result = self.bash(success=False, extra_env={'FAIL_VERIFY': '1'})
        self.assertIn('legacy files and schedules were kept', result.stderr)
        self.assertEqual(self.old_config.read_bytes(), expected)
        self.assertTrue((self.bin / 'nuqloud-vm-maintenance.sh').exists())
        self.assertTrue((self.units / 'nuqloud-vm-maintenance-trim.timer').exists())
        calls = self.systemctl_events.read_text()
        self.assertNotIn('disable --now', calls)
        self.assertNotIn('stop ', calls)
        self.assertNotIn('enable --now', calls)

    def test_invalid_legacy_config_cannot_trigger_removal(self):
        self.legacy_install('ENABLE_TRIM=invalid\n')
        self.bash(success=False)
        self.assertTrue(self.old_config.exists())
        self.assertTrue((self.bin / 'nuqloud-vm-maintenance.sh').exists())
        self.assertNotIn('disable --now', self.systemctl_events.read_text())

    def test_payload_copy_failure_keeps_legacy_files(self):
        self.legacy_install()
        self.bash(success=False, extra_env={'FAIL_INSTALL': '1'})
        self.assertTrue(self.old_config.exists())
        self.assertTrue((self.bin / 'nuqloud-vm-maintenance.sh').exists())
        self.assertNotIn('disable --now', self.systemctl_events.read_text())

    def test_missing_systemd_manager_stops_before_install(self):
        self.bash(success=False, extra_env={'FAIL_SYSTEMD': '1'})
        self.assertEqual(list(self.bin.iterdir()), [])
        self.assertEqual(list(self.units.iterdir()), [])
        self.assertFalse(self.new_config.exists())

    def test_symlink_config_is_not_followed_or_removed(self):
        saved = self.root / 'saved'
        saved.write_text('keep settings')
        self.old_config.symlink_to(saved)
        self.bash(success=False)
        self.assertTrue(self.old_config.is_symlink())
        self.assertEqual(saved.read_text(), 'keep settings')


if __name__ == '__main__':
    unittest.main()
