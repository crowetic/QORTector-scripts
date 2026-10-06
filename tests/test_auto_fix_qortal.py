"""Isolated recovery regression tests. No network or live Core is used."""
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'auto-fix-qortal.sh'


class AutoFixTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='auto-fix-test-')
        self.home = pathlib.Path(self.temp.name)
        self.core = self.home / 'qortal'
        self.core.mkdir()
        self.lib = self.home / 'functions.sh'
        self.lib.write_text(SCRIPT.read_text().split('# ================= Entry =================')[0])
        (self.core / 'settings.json').write_text('{}')
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=5)
        self.temp.cleanup()

    def bash(self, code, success=True, extra_env=None):
        env = {**os.environ, 'HOME': str(self.home), 'REVIEW_LIB': str(self.lib),
               'AUTO_FIX_SELF_UPDATE': '0'}
        env.update(extra_env or {})
        result = subprocess.run(['bash', '-c', '''source "$REVIEW_LIB"
sleep() { :; }
update_script() { echo FINISH; }
''' + code], env=env, text=True, capture_output=True, timeout=15)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def jar(self, name, value='old'):
        path = self.core / name
        with zipfile.ZipFile(path, 'w') as jar:
            jar.writestr('META-INF/MANIFEST.MF', 'Main-Class: org.qortal.Controller\n')
            jar.writestr('data', value)
        return path

    def test_identical_jar_does_not_restart(self):
        self.jar('qortal.jar')
        result = self.bash('''fetch() { cp "$HOME/qortal/qortal.jar" "$2"; }
qortal_kill_and_stop() { echo UNEXPECTED_STOP; return 1; }
check_for_GUI() { echo SAME_JAR; }
check_hash_update_qortal''')
        self.assertIn('SAME_JAR', result.stdout)
        self.assertNotIn('UNEXPECTED_STOP', result.stdout)

    def test_jar_update_keeps_database_and_previous_jar(self):
        old = self.jar('qortal.jar').read_bytes()
        self.jar('candidate.jar', 'new')
        (self.core / 'db').mkdir()
        (self.core / 'db' / 'data').write_text('database')
        self.bash('''fetch() { cp "$HOME/qortal/candidate.jar" "$2"; }
qortal_kill_and_stop() { :; }
potentially_update_settings() { :; }
start_core() { :; }
force_bootstrap() { return 99; }
check_hash_update_qortal''')
        self.assertEqual((self.core / 'qortal.jar.previous').read_bytes(), old)
        self.assertEqual((self.core / 'db' / 'data').read_text(), 'database')
        self.assertEqual((self.core / 'qortal.jar').read_bytes(), (self.core / 'candidate.jar').read_bytes())

    def test_bad_jar_keeps_installed_jar(self):
        old = self.jar('qortal.jar').read_bytes()
        self.bash('''fetch() { printf '<html>error</html>' > "$2"; }
qortal_kill_and_stop() { echo UNEXPECTED_STOP; }
check_hash_update_qortal''', success=False)
        self.assertEqual((self.core / 'qortal.jar').read_bytes(), old)

    def test_shutdown_failure_blocks_jar_replacement(self):
        old = self.jar('qortal.jar').read_bytes()
        self.jar('candidate.jar', 'new')
        result = self.bash('''fetch() { cp "$HOME/qortal/candidate.jar" "$2"; }
qortal_kill_and_stop() { return 1; }
check_hash_update_qortal''', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.core / 'qortal.jar').read_bytes(), old)

    def test_partial_failed_download_rejected(self):
        result = self.bash('''curl() {
 while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then printf partial > "$2"; return 18; fi
  shift
 done
}
fetch primary "$HOME/download.jar" mirror''', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / 'download.jar').exists())

    def test_download_mirror_recovers_primary_failure(self):
        self.bash('''curl() {
 local out source="${*: -1}"
 while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then out="$2"; fi; shift; done
 printf '%s' "$source" > "$out"
 [ "$source" = mirror ]
}
fetch primary "$HOME/download.jar" mirror''')
        self.assertEqual((self.home / 'download.jar').read_text(), 'mirror')

    def test_version_order(self):
        self.bash('''version_at_least 6.10.0 6.9.10 &&
! version_at_least 6.9.10 6.10.0 &&
version_at_least 6.1.2 6.1.2 &&
! version_at_least invalid 6.1.2''')

    def test_release_list_excludes_prereleases(self):
        self.bash('''curl() {
 case "${*: -1}" in *per_page*) printf '%s' '[{"tag_name":"v9.0.0","prerelease":true,"draft":false},{"tag_name":"v6.10.0","prerelease":false,"draft":false}]';; *) return 22;; esac
}
get_latest_remote_version
[ "$LATEST_REMOTE_TAG" = 6.10.0 ]''')

    def test_version_api_accepts_whitespace(self):
        self.bash('''curl() { printf '{"tag_name": "v6.10.0"}'; }
get_latest_remote_version
[ "$LATEST_REMOTE_TAG" = 6.10.0 ]''')

    def test_redirect_version_fallback(self):
        self.bash('''curl() {
 case "${*: -1}" in https://github.com/*) printf 'HTTP/2 302\r\nlocation: https://github.com/qortal/qortal/releases/tag/v6.10.0\r\n';; *) return 22;; esac
}
get_latest_remote_version
[ "$LATEST_REMOTE_TAG" = 6.10.0 ]''')

    def test_bootstrap_event_order(self):
        self.bash('''printf 'Starting bootstrap\nBootstrap completed\n' > "$HOME/qortal/qortal.log"
! is_actively_bootstrapping || exit 1
printf 'Starting bootstrap\n' >> "$HOME/qortal/qortal.log"
is_actively_bootstrapping''')

    def test_silent_running_bootstrap_is_protected(self):
        self.bash('''printf 'Starting bootstrap\n' > "$HOME/qortal/qortal.log"
touch -d '1 hour ago' "$HOME/qortal/qortal.log"
qortal_pids() { echo 123; }
is_actively_bootstrapping''')

    def test_lag_boundary_and_invalid_remotes(self):
        self.bash('''curl() { printf '%s' "$REMOTE_HEIGHT"; }
REMOTE_HEIGHT=3500
! node_is_far_behind 1000 || exit 1
REMOTE_HEIGHT=3501
node_is_far_behind 1000 || exit 1
! node_is_far_behind 5000 || exit 1
REMOTE_HEIGHT='<html>error</html>'
! node_is_far_behind 1000''')

    def test_valid_primary_is_authoritative_and_fallback_not_called(self):
        self.bash('''curl() {
 case "${*: -1}" in *api.qortal.org*) echo 10000;; *) touch "$HOME/fallback-called"; echo 2000;; esac
}
node_is_far_behind 1000 || exit 1
[ ! -e "$HOME/fallback-called" ]''')

    def test_close_primary_does_not_consult_far_ahead_fallback(self):
        self.bash('''curl() {
 case "${*: -1}" in *api.qortal.org*) echo 2000;; *) touch "$HOME/fallback-called"; echo 10000;; esac
}
! node_is_far_behind 1000 || exit 1
[ ! -e "$HOME/fallback-called" ]''')

    def test_failed_primary_uses_fallback(self):
        self.bash('''curl() { case "${*: -1}" in *api.qortal.org*) echo 10000; return 22;; *) echo 10000;; esac; }
node_is_far_behind 1000''')

    def test_invalid_primary_uses_fallback(self):
        self.bash('''curl() { case "${*: -1}" in *api.qortal.org*) echo '<html>error</html>';; *) echo 10000;; esac; }
node_is_far_behind 1000''')

    def test_failed_primary_with_close_fallback_does_not_bootstrap(self):
        self.bash('''curl() { case "${*: -1}" in *api.qortal.org*) return 28;; *) echo 2000;; esac; }
! node_is_far_behind 1000''')

    def test_both_requests_failing_does_not_confirm_lag(self):
        self.bash('''curl() { return 28; }
! node_is_far_behind 1000''')

    def setup_db(self):
        (self.core / 'db').mkdir()
        (self.core / 'db' / 'data').write_text('database')

    def force_code(self, overrides=''):
        return '''api_get() { echo 1000; }
node_is_far_behind() { return 0; }
qortal_kill_and_stop() { echo STOP >> "$HOME/events"; }
start_core() { echo START >> "$HOME/events"; }
wait_for_core_recovery() { :; }
''' + overrides + '\nforce_bootstrap behind'

    def test_verified_backup_before_bootstrap(self):
        self.setup_db()
        self.bash(self.force_code('''cp() { echo COPY >> "$HOME/events"; command cp "$@"; }'''))
        self.assertEqual((self.home / 'events').read_text().splitlines(), ['STOP', 'COPY', 'START'])
        backups = list((self.core / 'backup').glob('db-*'))
        self.assertEqual(backups, [])
        self.assertFalse((self.core / 'db').exists())

    def test_failed_backup_never_removes_database(self):
        self.setup_db()
        result = self.bash(self.force_code('cp() { return 1; }'), success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.core / 'db' / 'data').read_text(), 'database')

    def test_failed_backup_verification_never_removes_database(self):
        self.setup_db()
        result = self.bash(self.force_code('diff() { return 1; }'), success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.core / 'db' / 'data').exists())

    def test_shutdown_failure_never_removes_database(self):
        self.setup_db()
        self.bash(self.force_code('qortal_kill_and_stop() { return 1; }'), success=False)
        self.assertTrue((self.core / 'db' / 'data').exists())

    def test_launch_failure_restores_database(self):
        self.setup_db()
        self.bash(self.force_code('start_core() { return 1; }'), success=False)
        self.assertEqual((self.core / 'db' / 'data').read_text(), 'database')

    def test_active_bootstrap_never_removes_database(self):
        self.setup_db()
        self.bash(self.force_code('is_actively_bootstrapping() { return 0; }'))
        self.assertTrue((self.core / 'db' / 'data').exists())
        self.assertFalse((self.home / 'events').exists())

    def test_custom_repository_is_not_wiped(self):
        self.setup_db()
        (self.core / 'settings.json').write_text('{"repositoryPath":"/data/db"}')
        result = self.bash(self.force_code(), success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.core / 'db' / 'data').exists())

    def test_successful_recoveries_do_not_accumulate_full_backups(self):
        for number in range(4):
            self.setup_db()
            (self.core / 'db' / 'data').write_text(str(number))
            self.bash(self.force_code())
        backups = list((self.core / 'backup').glob('db-*'))
        self.assertEqual(backups, [])

    def test_stall_requires_timed_samples(self):
        (self.home / 'auto_fix_last_height.txt').write_text('1')
        result = self.bash('''api_get() { echo 1; }
node_is_far_behind() { return 1; }
sleep() { echo WAIT; }
force_bootstrap() { echo "RECOVER_$1"; }
check_height''')
        self.assertEqual(result.stdout.count('WAIT'), 2)
        self.assertIn('recheck 1/2 in 300s', result.stdout)
        self.assertIn('recheck 2/2 in 300s', result.stdout)
        self.assertIn('RECOVER_stalled', result.stdout)

    def test_advancing_height_not_stalled(self):
        (self.home / 'auto_fix_last_height.txt').write_text('1')
        result = self.bash('''api_get() { if [ -f "$HOME/sampled" ]; then echo 2; else touch "$HOME/sampled"; echo 1; fi; }
node_is_far_behind() { return 1; }
force_bootstrap() { echo UNEXPECTED; }
check_height''')
        self.assertNotIn('UNEXPECTED', result.stdout)

    def test_high_stall_bootstraps_at_any_height(self):
        (self.home / 'auto_fix_last_height.txt').write_text('4000000')
        result = self.bash('''api_get() { echo 4000000; }
node_is_far_behind() { return 1; }
restart_core() { echo RESTART; }
force_bootstrap() { echo CONFIRMED_BOOTSTRAP; }
check_height''')
        self.assertNotIn('RESTART', result.stdout)
        self.assertIn('CONFIRMED_BOOTSTRAP', result.stdout)

    def test_missing_jq_preserves_settings(self):
        original = '{"apiKey":"secret","custom":true}'
        (self.core / 'settings.json').write_text(original)
        self.bash('''command() {
 if [ "$1" = -v ] && { [ "$2" = jq ] || [ "$2" = apt-get ]; }; then return 1; fi
 builtin command "$@"
}
potentially_update_settings''', success=False)
        self.assertEqual((self.core / 'settings.json').read_text(), original)

    def test_settings_merge_and_no_rewrite(self):
        (self.core / 'settings.json').write_text('{"apiKey":"secret","minPeers":20,"networkThreadPriority":2}')
        self.bash('''fetch() { printf '{"minPeers":10,"networkThreadPriority":7}' > "$2"; }
potentially_update_settings || exit 1
first=$(stat -c %i "$HOME/qortal/settings.json")
potentially_update_settings || exit 1
[ "$first" = "$(stat -c %i "$HOME/qortal/settings.json")" ] || exit 1
jq -e '.apiKey == "secret" and .minPeers == 20 and .networkThreadPriority == 7' "$HOME/qortal/settings.json"''')

    def test_invalid_remote_settings_preserves_local(self):
        original = '{"custom":true}'
        (self.core / 'settings.json').write_text(original)
        self.bash('''fetch() { printf '[]' > "$2"; }
potentially_update_settings''', success=False)
        self.assertEqual((self.core / 'settings.json').read_text(), original)

    def test_cron_preserves_jobs_and_is_idempotent(self):
        (self.home / 'cron').write_text('MAILTO=user@example.test\n0 3 * * * /home/user/backup.sh\n@reboot sleep 399 && "${HOME}/auto-fix-qortal.sh"\n')
        self.bash('''crontab() { if [ "$1" = -l ]; then cat "$HOME/cron"; else cp "$1" "$HOME/cron"; fi; }
install_managed_cron headless || exit 1
cp "$HOME/cron" "$HOME/first-cron"
install_managed_cron headless || exit 1
cmp "$HOME/cron" "$HOME/first-cron"''')
        cron = (self.home / 'cron').read_text()
        self.assertIn('MAILTO=user@example.test', cron)
        self.assertIn('/home/user/backup.sh', cron)
        self.assertEqual(cron.count('auto-fix-qortal.sh'), 2)

    def test_cron_read_failure_does_not_install(self):
        result = self.bash('''crontab() { if [ "$1" = -l ]; then echo 'permission denied' >&2; return 1; else echo UNEXPECTED; fi; }
install_managed_cron headless''', success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('UNEXPECTED', result.stdout)

    def test_start_child_does_not_inherit_lock(self):
        (self.core / 'start.sh').write_text('#!/bin/bash\n/bin/sleep 60 >/dev/null 2>&1 &\necho $! > "$HOME/child.pid"\n')
        (self.core / 'start.sh').chmod(0o755)
        try:
            self.bash('''exec 9> "$HOME/lock"
flock -n 9 || exit 1
qortal_pids() { echo 123; }
start_core || exit 1
exec 9>&-
flock -n "$HOME/lock" true''')
        finally:
            pid = self.home / 'child.pid'
            if pid.exists():
                os.kill(int(pid.read_text()), signal.SIGTERM)

    def test_process_matching_targets_only_installation(self):
        java = self.home / 'java'
        shutil.copyfile(sys.executable, java)
        java.chmod(0o755)
        for cwd, jar in [(self.core, 'qortal.jar'), (self.home, 'qortal.jar'), (self.core, 'qortalXjar')]:
            self.children.append(subprocess.Popen([str(java), '-c', 'import time; time.sleep(60)', '-jar', jar], cwd=cwd))
        result = self.bash('qortal_pids')
        self.assertEqual(result.stdout.strip(), str(self.children[0].pid))

    def test_script_validation_rejects_downgrade_and_marker(self):
        self.bash('''script_passes_sanity "$REVIEW_LIB" || exit 1
sed 's/AFQ_SCRIPT_REVISION=[0-9]*/AFQ_SCRIPT_REVISION=1/' "$REVIEW_LIB" > "$HOME/old.sh"
! script_passes_sanity "$HOME/old.sh" || exit 1
cp "$REVIEW_LIB" "$HOME/bad.sh"
printf '\n======= REPLACE\n' >> "$HOME/bad.sh"
! script_passes_sanity "$HOME/bad.sh"''')

    def test_missing_release_metadata_preserves_custom_build(self):
        self.jar('qortal.jar')
        result = self.bash('''api_get() { printf '{"buildVersion": "qortal-6.1.2-custom"}'; }
get_latest_remote_version() { LATEST_REMOTE_TAG=""; LATEST_REMOTE_NUM=""; }
check_for_GUI() { echo HEALTH_CHECK; }
check_hash_update_qortal() { echo UNEXPECTED_REPLACEMENT; }
check_qortal''')
        self.assertIn('HEALTH_CHECK', result.stdout)
        self.assertNotIn('UNEXPECTED_REPLACEMENT', result.stdout)

    def test_special_build_override_is_preserved(self):
        result = self.bash('''api_get() { printf '{"buildVersion": "qortal-6.1.2-4ee9441"}'; }
get_latest_remote_version() { LATEST_REMOTE_TAG=6.1.2; LATEST_REMOTE_NUM=6.1.2; }
check_for_GUI() { echo CORRECT_SPECIAL_BUILD; }
check_hash_update_qortal() { echo UNEXPECTED_REPLACEMENT; }
check_qortal''')
        self.assertIn('CORRECT_SPECIAL_BUILD', result.stdout)
        self.assertNotIn('UNEXPECTED_REPLACEMENT', result.stdout)

    def test_immediate_jar_launch_failure_restores_previous(self):
        old = self.jar('qortal.jar').read_bytes()
        self.jar('candidate.jar', 'new')
        self.bash('''fetch() { cp "$HOME/qortal/candidate.jar" "$2"; }
qortal_kill_and_stop() { :; }
potentially_update_settings() { :; }
start_core() { return 1; }
check_hash_update_qortal''', success=False)
        self.assertEqual((self.core / 'qortal.jar').read_bytes(), old)

    def test_failed_height_sample_does_not_confirm_stall(self):
        (self.home / 'auto_fix_last_height.txt').write_text('1000000')
        result = self.bash('''api_get() { if [ -f "$HOME/sampled" ]; then return 22; else touch "$HOME/sampled"; echo 1000000; fi; }
node_is_far_behind() { return 1; }
force_bootstrap() { echo UNEXPECTED_BOOTSTRAP; }
check_height''')
        self.assertNotIn('UNEXPECTED_BOOTSTRAP', result.stdout)

    def test_bootstrapping_complete_clears_active_state(self):
        self.bash('''printf 'Starting bootstrap\nBootstrapping complete\n' > "$HOME/qortal/qortal.log"
! is_actively_bootstrapping''')

    def test_lag_is_reconfirmed_before_recovery(self):
        self.setup_db()
        self.bash('''api_get() { echo 1000; }
node_is_far_behind() { return 1; }
qortal_kill_and_stop() { echo UNEXPECTED_STOP; }
force_bootstrap behind''')
        self.assertTrue((self.core / 'db' / 'data').exists())

    def test_stale_pid_does_not_invoke_stop_script(self):
        java = self.home / 'java'
        shutil.copyfile(sys.executable, java)
        java.chmod(0o755)
        child = subprocess.Popen([str(java), '-c', 'import time; time.sleep(60)', '-jar', 'qortal.jar'], cwd=self.core)
        self.children.append(child)
        (self.core / 'run.pid').write_text(str(os.getpid()))
        stop = self.core / 'stop.sh'
        stop.write_text('#!/bin/bash\necho BAD_STOP > "$HOME/bad-stop"\n')
        stop.chmod(0o755)
        self.bash('''sleep() { command sleep 0.1; }
CORE_STOP_WAIT_SECONDS=10
qortal_kill_and_stop''')
        child.wait(timeout=5)
        self.assertFalse((self.home / 'bad-stop').exists())

    def test_invalid_json_primary_uses_valid_mirror(self):
        self.bash('''curl() {
 local out source="${*: -1}"
 while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then out="$2"; fi; shift; done
 if [ "$source" = mirror ]; then printf '{"valid":true}' > "$out"; else printf '[]' > "$out"; fi
}
fetch primary "$HOME/settings.json" mirror''')
        self.assertEqual((self.home / 'settings.json').read_text(), '{"valid":true}')

    def test_self_exec_can_reacquire_lock(self):
        source = SCRIPT.read_text()
        head, entry = source.split('# ================= Entry =================', 1)
        fixture = self.home / 'reexec.sh'
        fixture.write_text(head + '''
initial_update() {
 if [ -z "${TEST_REEXEC:-}" ]; then
  export TEST_REEXEC=1
  exec "$HOME/reexec.sh"
 fi
 echo MAINTENANCE_REACHED
}
# ================= Entry =================''' + entry)
        fixture.chmod(0o755)
        result = subprocess.run([str(fixture)], env={**os.environ, 'HOME': str(self.home)},
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('MAINTENANCE_REACHED', result.stdout)

    def test_confirmed_stall_at_high_height_recovers_database(self):
        self.setup_db()
        code = self.force_code().replace('echo 1000', 'echo 4000000')
        code = code.replace('force_bootstrap behind', 'CONFIRMED_STALLED_HEIGHT=4000000\nforce_bootstrap stalled')
        self.bash(code)
        self.assertFalse((self.core / 'db').exists())
        backups = list((self.core / 'backup').glob('db-*'))
        self.assertEqual(backups, [])

    @unittest.skipUnless(shutil.which('jar'), 'JDK jar unavailable')
    def test_jdk_jar_validation_fallback(self):
        self.jar('candidate.jar')
        self.bash('''command() {
 if [ "$1" = -v ] && [ "$2" = unzip ]; then return 1; fi
 builtin command "$@"
}
jar_is_valid "$HOME/qortal/candidate.jar" || exit 1
printf 'not a jar' > "$HOME/qortal/candidate.jar"
! jar_is_valid "$HOME/qortal/candidate.jar"''')

    def test_unavailable_api_after_launch_preserves_database(self):
        self.setup_db()
        result = self.bash('''api_get() { return 22; }
qortal_kill_and_stop() { :; }
start_core() { :; }
wait_for_core_recovery() { return 1; }
potentially_update_settings() { :; }
force_bootstrap() { echo UNEXPECTED_BOOTSTRAP; }
no_local_height''', success=False)
        self.assertNotIn('UNEXPECTED_BOOTSTRAP', result.stdout)
        self.assertTrue((self.core / 'db' / 'data').exists())

    def test_partial_db_is_restored_after_failed_start(self):
        self.setup_db()
        code = self.force_code('''start_core() {
 if [ ! -e "$HOME/retried" ]; then
  touch "$HOME/retried"
  mkdir -p "$HOME/qortal/db"
  printf partial > "$HOME/qortal/db/new-data"
  return 1
 fi
 return 0
}''')
        self.bash(code, success=False)
        self.assertEqual((self.core / 'db' / 'data').read_text(), 'database')
        self.assertFalse((self.core / 'db' / 'new-data').exists())
        self.assertEqual(list((self.core / 'backup').glob('db-*')), [])

    def test_unconfirmed_start_retains_recovery_backup(self):
        self.setup_db()
        self.bash(self.force_code('wait_for_core_recovery() { return 1; }'), success=False)
        backups = [p for p in (self.core / 'backup').glob('db-*') if (p / '.auto-fix-pending').exists()]
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'data').read_text(), 'database')
        self.assertTrue((self.core / 'db' / 'data').exists())

    def test_shutdown_failure_during_rollback_retains_original(self):
        self.setup_db()
        self.bash(self.force_code('''qortal_kill_and_stop() {
 if [ -f "$HOME/stopped-once" ]; then return 1; fi
 touch "$HOME/stopped-once"
}
wait_for_core_recovery() { return 1; }'''), success=False)
        originals = list((self.core / 'backup').glob('*.original'))
        self.assertEqual(len(originals), 1)
        self.assertEqual((originals[0] / 'data').read_text(), 'database')

    def test_cleanup_only_deletes_script_owned_backups(self):
        root = self.core / 'backup'
        root.mkdir()
        for name in ['db-20261005123456-AbC123', 'db-manual', 'data-manual']:
            folder = root / name
            folder.mkdir()
            (folder / 'data').write_text('saved')
        (root / 'db-20261005123456-AbC123' / '.auto-fix-verified').touch()
        self.bash('cleanup_recovery_backups')
        self.assertFalse((root / 'db-20261005123456-AbC123').exists())
        self.assertTrue((root / 'db-manual' / 'data').exists())
        self.assertTrue((root / 'data-manual' / 'data').exists())

    def test_pending_cleanup_requires_confirmed_start(self):
        root = self.core / 'backup' / 'db-20261005123456-AbC123'
        root.mkdir(parents=True)
        (root / '.auto-fix-pending').touch()
        self.bash('wait_for_core_recovery() { return 1; }; cleanup_backups_if_ready', success=False)
        self.assertTrue(root.exists())
        self.bash('wait_for_core_recovery() { return 0; }; cleanup_backups_if_ready')
        self.assertFalse(root.exists())

    def readiness_code(self, overrides=''):
        return '''CORE_START_WAIT_SECONDS=20
FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS=10
sleep() { SECONDS=$((SECONDS + $1)); }
qortal_pids() { echo 123; }
api_get() { echo 4000000; }
is_actively_bootstrapping() { return 1; }
''' + overrides + '\nwait_for_core_recovery'

    def test_readiness_requires_sustained_api_and_live_jvm(self):
        self.bash(self.readiness_code('''sleep() {
 echo WAIT >> "$HOME/readiness-events"
 SECONDS=$((SECONDS + $1))
}'''))
        self.assertEqual((self.home / 'readiness-events').read_text().splitlines(), ['WAIT', 'WAIT'])

    def test_readiness_accepts_active_bootstrap_with_no_api(self):
        self.bash(self.readiness_code('api_get() { return 22; }; is_actively_bootstrapping() { return 0; }'))

    def test_readiness_rejects_delayed_jvm_exit(self):
        result = self.bash(self.readiness_code('''sleep() { SECONDS=$((SECONDS + $1)); touch "$HOME/core-exited"; }
qortal_pids() { [ -f "$HOME/core-exited" ] || echo 123; }'''), success=False)
        self.assertNotEqual(result.returncode, 0)

    def test_readiness_times_out_without_api_or_bootstrap_evidence(self):
        result = self.bash(self.readiness_code('api_get() { return 22; }'), success=False)
        self.assertNotEqual(result.returncode, 0)

    def test_no_local_height_returns_after_ready_without_fixed_35min_sleep(self):
        result = self.bash('''qortal_kill_and_stop() { :; }
start_core() { :; }
potentially_update_settings() { :; }
wait_for_core_recovery() { echo READY; }
check_height() { echo "CHECK_$1"; }
sleep() { echo "UNEXPECTED_SLEEP_$1"; }
no_local_height''')
        self.assertIn('READY', result.stdout)
        self.assertIn('CHECK_started', result.stdout)
        self.assertNotIn('UNEXPECTED_SLEEP', result.stdout)

    def test_height_disappearing_after_start_does_not_recurse(self):
        result = self.bash('''api_get() { return 22; }
no_local_height() { echo UNEXPECTED_RETRY; }
check_height started''', success=False)
        self.assertNotIn('UNEXPECTED_RETRY', result.stdout)
        self.assertNotEqual(result.returncode, 0)

    def test_long_startup_prints_periodic_status(self):
        result = self.bash(self.readiness_code('''CORE_START_WAIT_SECONDS=65
api_get() { return 22; }'''), success=False)
        self.assertIn('checking every 5s', result.stdout)
        self.assertIn('30s elapsed', result.stdout)
        self.assertIn('60s elapsed', result.stdout)

    def test_failed_startup_does_not_start_another_cleanup_wait(self):
        result = self.bash('''unset -f update_script
source "$REVIEW_LIB"
sleep() { :; }
cleanup_backups_if_ready() { echo UNEXPECTED_SECOND_WAIT; }
potentially_update_settings() { :; }
update_script startup_failed''')
        self.assertNotIn('UNEXPECTED_SECOND_WAIT', result.stdout)

    def test_cleanup_preserves_symlinked_backup_location(self):
        saved = self.home / 'saved-backups'
        managed = saved / 'db-20261005123456-AbC123'
        managed.mkdir(parents=True)
        (managed / '.auto-fix-pending').touch()
        (self.core / 'backup').symlink_to(saved, target_is_directory=True)
        self.bash('cleanup_recovery_backups', success=False)
        self.assertTrue(managed.exists())

    def test_small_backup_retention_keeps_latest_good_and_manual_files(self):
        folder = self.core / 'qortal-backup' / 'auto-fix-settings-backup'
        folder.mkdir(parents=True)
        for number in range(5):
            path = folder / f'backup-settings-2026100512345{number}.json'
            path.write_text('{}')
            os.utime(path, (number, number))
        (folder / 'latest-good.json').symlink_to('backup-settings-20261005123450.json')
        (folder / 'backup-settings-manual.json').write_text('{}')
        self.bash('SMALL_BACKUPS_TO_KEEP=2; prune_small_backups')
        self.assertTrue((folder / 'latest-good.json').exists())
        self.assertTrue((folder / 'backup-settings-20261005123454.json').exists())
        self.assertTrue((folder / 'backup-settings-20261005123453.json').exists())
        self.assertFalse((folder / 'backup-settings-20261005123451.json').exists())
        self.assertTrue((folder / 'backup-settings-manual.json').exists())

    def test_script_and_cron_backups_are_bounded(self):
        scripts = self.core / 'new-scripts' / 'backups'
        cron = self.home / 'backups' / 'cron-backups'
        scripts.mkdir(parents=True)
        cron.mkdir(parents=True)
        for number in range(4):
            (scripts / f'auto-fix-2026100512345{number}.sh').write_text('script')
            (cron / f'crontab-backup-2026100512345{number}').write_text('cron')
        (scripts / 'original.sh').write_text('original')
        self.bash('SMALL_BACKUPS_TO_KEEP=2; prune_small_backups')
        self.assertEqual(len(list(scripts.glob('auto-fix-*'))), 2)
        self.assertEqual(len(list(cron.iterdir())), 2)
        self.assertTrue((scripts / 'original.sh').exists())

    def test_invalid_tunable_fails_before_maintenance(self):
        result = subprocess.run(['bash', str(SCRIPT)], env={**os.environ, 'HOME': str(self.home),
            'AUTO_FIX_MAX_BLOCKS_BEHIND': 'invalid'}, text=True, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Invalid positive integer', result.stdout)


if __name__ == '__main__':
    unittest.main()
