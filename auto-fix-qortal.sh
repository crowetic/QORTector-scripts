#!/usr/bin/env bash
# auto-fix-qortal.sh  —  Auto-fix / maintenance for Qortal Core
#
# PURPOSE
#   Keeps a Qortal Core node updated and within ~2500 blocks of network height.
#   Runs on a schedule (cron) and at boot; updates itself, settings, and the
#   JVM start script, and bootstraps when the reference is over 2500 blocks ahead, or the
#   node has a confirmed height stall.
#
# SCHEDULE / TRIGGERS
#   Cron: "@reboot sleep 399" and "1 1 */3 * *"  (see auto-fix-cron).
#
# PREREQUISITES
#   - Linux /proc, Bash, flock, timeout, jq (auto-installed if missing)
#   - unzip or JDK jar (candidate archive validation)
#   - curl (for downloads / connectivity)
#   - Qortal Core installed at ${HOME}/qortal with qortal.jar, settings.json
#   - HTTP API on localhost:12391 (admin/status, admin/info, blocks/height)
#
# SAFETY / BEHAVIOUR
#   - Only one instance runs at a time (flock).
#   - Database recovery requires a confirmed reason and a verified backup.
#   - Shutdown targets the JVM running this installation of qortal.jar.
#
# TUNABLE CONSTANTS — all env-overridable (see below).
#
# CHANGELOG
#   2026-10-03  Added concurrency lock and initial recovery guards,
#               GitHub rate-limit skip, guarded force_bootstrap,
#               targeted java kill, bash shebang, named constants.
#   2026-10-05  Verified downloads/backups, explicit recovery reasons, 2500-block
#               lag threshold, process shutdown checks and managed cron entries.
# ================= Colors (ANSI) =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# ================= Script flags =================
ARM_32_DETECTED=false
ARM_64_DETECTED=false

# ================= Global URLs (override via env) =================
DEFAULT_SCRIPT_URL="${AUTO_FIX_SCRIPT_URL:-https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh}"
DEFAULT_SCRIPT_MIRROR="${AUTO_FIX_SCRIPT_MIRROR_URL:-https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/auto-fix-qortal.sh}"

DEFAULT_SETTINGS_URL="${AUTO_FIX_SETTINGS_URL:-https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/settings.json}"
DEFAULT_SETTINGS_MIRROR="${AUTO_FIX_SETTINGS_MIRROR_URL:-https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/settings.json}"


# Temporary 6.1.2 core override (useful in scenarios where release version is less than ideal.)
SPECIAL_VERSION="6.1.2"
SPECIAL_BUILD_VERSION="qortal-6.1.2-4ee9441"
SPECIAL_JAR_URL="https://cloud.qortal.org/s/croweticTestJarDownload/download/qortal.jar"

LATEST_REMOTE_TAG=""
LATEST_REMOTE_NUM=""
LATEST_LOCAL_BUILD=""
LATEST_LOCAL_NUM=""

# ================= Tunable constants (env-overridable) =================
# Revision prevents self-update from reinstalling an older unsafe script.
AFQ_SCRIPT_REVISION=3
API_BASE="${AUTO_FIX_API_BASE:-http://localhost:12391}"
MAX_BLOCKS_BEHIND="${AUTO_FIX_MAX_BLOCKS_BEHIND:-2500}"
ACTIVE_LOG_MAX_AGE_SECONDS="${ACTIVE_LOG_MAX_AGE_SECONDS:-900}"
CORE_START_WAIT_SECONDS="${CORE_START_WAIT_SECONDS:-2100}"
HEIGHT_STALL_WAIT_SECONDS="${HEIGHT_STALL_WAIT_SECONDS:-300}"
HEIGHT_STALL_RECHECKS="${HEIGHT_STALL_RECHECKS:-2}"
FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS="${FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS:-30}"
CORE_STOP_WAIT_SECONDS="${CORE_STOP_WAIT_SECONDS:-120}"
SMALL_BACKUPS_TO_KEEP="${SMALL_BACKUPS_TO_KEEP:-10}"
AUTO_FIX_SELF_UPDATE="${AUTO_FIX_SELF_UPDATE:-1}"

# ================= Helpers (Bash / Linux) =================
p() { # printf wrapper
	# shellcheck disable=SC2059
	printf "%b\n" "$*"
}

atomic_write() { # atomic_write TMP DEST
	local tmp="$1" dest="$2"
	mkdir -p "$(dirname "$dest")" || return 1
	mv -f -- "$tmp" "$dest" || return 1
}

fetch() { # fetch URL OUTFILE [MIRROR_URL]
	local url="$1" out="$2" mirror="${3:-}" kind="${4:-}" tmp attempt source ok=false
	case "$out" in *.json) kind=json ;; esac
	tmp="$(mktemp "${out}.XXXXXX")" || return 1
	for source in "$url" "$mirror"; do
		[ -n "$source" ] || continue
		for attempt in 1 2 3 4 5; do
			: > "$tmp"
			if curl -fsSL --connect-timeout 10 --max-time 60 -o "$tmp" "$source" && [ -s "$tmp" ]; then
				if [ "$kind" = json ] && ! is_valid_json_file "$tmp"; then continue; fi
				ok=true
				break
			fi
			sleep 2
		done
		[ "$ok" = true ] && break
	done
	if [ "$ok" != true ]; then rm -f -- "$tmp"; return 1; fi
	if ! atomic_write "$tmp" "$out"; then rm -f -- "$tmp"; return 1; fi
}

is_valid_json_file() {
	[ -s "$1" ] && command -v jq >/dev/null 2>&1 && jq -e 'type == "object"' "$1" >/dev/null 2>&1
}

json_semantically_equal() { # json_semantically_equal FILE_A FILE_B
	local file_a="$1"
	local file_b="$2"
	[ -s "$file_a" ] || return 1
	[ -s "$file_b" ] || return 1
	command -v jq >/dev/null 2>&1 || return 1
	local a_norm
	a_norm="$(jq -cS . "$file_a" 2>/dev/null || true)"
	local b_norm
	b_norm="$(jq -cS . "$file_b" 2>/dev/null || true)"
	[ -n "$a_norm" ] && [ "$a_norm" = "$b_norm" ]
}

file_mtime_epoch() { # file_mtime_epoch FILE
	local file="$1"
	[ -e "$file" ] || return 1
	if stat -c %Y "$file" >/dev/null 2>&1; then
		stat -c %Y "$file"
		return 0
	fi
	if stat -f %m "$file" >/dev/null 2>&1; then
		stat -f %m "$file"
		return 0
	fi
	return 1
}

is_recent_file() { # is_recent_file FILE MAX_AGE_SECONDS
	local file="$1"
	local max_age="$2"
	local mtime
	mtime="$(file_mtime_epoch "$file" 2>/dev/null || true)"
	[ -n "$mtime" ] || return 1
	local now
	now="$(date +%s)"
	local age=$((now - mtime))
	[ "$age" -le "$max_age" ] 2>/dev/null
}

log_indicates_active_bootstrap() {
	[ -s "$1" ] || return 1
	# Track event ordering: a completion must clear an earlier start.
	tail -n 200 "$1" | awk '
	BEGIN { active=0 }
	{ line=tolower($0)
			if (line ~ /bootstrap(ping)? (is )?(complete|completed|finished|successful)|finished bootstrapping|bootstrap(ping)? failed|not bootstrapping|no bootstrap|bootstrap not required|bootstrap disabled|bootstrap=false/) active=0
			else if (line ~ /bootstrapping|starting bootstrap|bootstrap (started|in progress|download|downloading|extract|extracting|import|importing|verify|verifying|apply|applying|sync)/) active=1
	}
	END { exit !active }'
}

is_actively_bootstrapping() { # is_actively_bootstrapping
	local log_file="${HOME}/qortal/qortal.log"
	# A running Core may be silently extracting for longer than the freshness window.
	log_indicates_active_bootstrap "$log_file" || return 1
	is_recent_file "$log_file" "$ACTIVE_LOG_MAX_AGE_SECONDS" || [ -n "$(qortal_pids)" ]
}

qortal_kill_and_stop() {
	local pid attempt stop_pid
	[ -d /proc/self ] || { p "Cannot inspect Core processes; refusing recovery."; return 1; }
	local -a pids=()
	# /proc identifies the jar argument AND its working directory. Avoid broad pkill.
	while IFS= read -r pid; do pids+=("$pid"); done < <(qortal_pids)
	stop_pid="$(cat "${HOME}/qortal/run.pid" 2>/dev/null)" || stop_pid=""
	# Only trust stop.sh's PID file when it identifies this Core JVM.
	if [ -x "${HOME}/qortal/stop.sh" ] && [[ "$stop_pid" =~ ^[0-9]+$ ]] && printf '%s\n' "${pids[@]}" | grep -qx "$stop_pid"; then
		(cd "${HOME}/qortal" && timeout --kill-after=5 "$CORE_STOP_WAIT_SECONDS" ./stop.sh 9>&-) >/dev/null 2>&1 || true
	fi
	for pid in "${pids[@]}"; do
		# Revalidate identity before signalling, including possible PID reuse.
		if qortal_pids | grep -qx "$pid"; then kill -TERM "$pid" 2>/dev/null || true; fi
	done
	for ((attempt=0; attempt<CORE_STOP_WAIT_SECONDS; attempt++)); do
		[ -z "$(qortal_pids)" ] && return 0
		sleep 1
	done
	[ -z "$(qortal_pids)" ] && return 0
	p "${RED}Core did not stop; aborting recovery without replacing jar or deleting db.${NC}"
	return 1
}

is_node_genuinely_stuck() {
	# Only the stall path sets this evidence after timed, numeric height samples.
	local height
	[ -n "${CONFIRMED_STALLED_HEIGHT:-}" ] || return 1
	is_actively_bootstrapping && return 1
	height="$(api_get /blocks/height)" || return 1
	is_height "$height" || return 1
	[ "$height" = "$CONFIRMED_STALLED_HEIGHT" ]
}

script_passes_sanity() {
	local revision
	[ -s "$1" ] || return 1
	bash -n "$1" || return 1
	grep -Eq '^(<<<<<<<|=======|>>>>>>>)' "$1" && return 1
	revision="$(sed -n 's/^AFQ_SCRIPT_REVISION=\([0-9][0-9]*\)$/\1/p' "$1")"
	[[ "$revision" =~ ^[0-9]{1,8}$ ]] && [ "$revision" -ge "$AFQ_SCRIPT_REVISION" ] || return 1
	grep -q 'initial_update()' "$1" && grep -q 'potentially_update_settings()' "$1" && grep -q 'is_actively_bootstrapping()' "$1"
}

# API failures are unknown, never height zero.
api_get() { curl -fsS --connect-timeout 5 --max-time 15 "${API_BASE}$1"; }
is_height() { [[ "$1" =~ ^(0|[1-9][0-9]{0,9})$ ]]; }
valid_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
version_at_least() {
	valid_version "$1" && valid_version "$2" || return 1
	[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}
qortal_pids() {
	local proc pid cwd arg jar found executable
	[ -d /proc/self ] || return 1
	for proc in /proc/[0-9]*; do
		pid="${proc##*/}"
		executable="$(readlink "$proc/exe" 2>/dev/null)" || continue
		case "$executable" in */java|*/java\ \(deleted\)) ;; *) continue ;; esac
		cwd="$(readlink -f "$proc/cwd" 2>/dev/null)" || continue
		found=false; jar=false
		while IFS= read -r -d '' arg; do
			if [ "$jar" = true ]; then
				if [ "$arg" = "${HOME}/qortal/qortal.jar" ] || { [ "$arg" = qortal.jar ] && [ "$cwd" = "$(readlink -f "${HOME}/qortal")" ]; }; then found=true; fi
				break
			fi
			[ "$arg" = -jar ] && jar=true
		done < "$proc/cmdline" 2>/dev/null
		[ "$found" = true ] && printf '%s\n' "$pid"
	done
	return 0
}
start_core() {
	(cd "${HOME}/qortal" && ./start.sh 9>&-) || return 1
	sleep 3
	if [ -z "$(qortal_pids)" ]; then p "Core launch failed; inspect ${HOME}/qortal/run.log."; return 1; fi
}
# Require sustained evidence before deleting recovery copies. The deadline also
# covers slow API requests; an existing JVM alone is not startup confirmation.
wait_for_core_recovery() {
	local started="$SECONDS" deadline=$((SECONDS + CORE_START_WAIT_SECONDS))
	local stable_since=-1 height remaining delay next_report=$((SECONDS + 30)) evidence
	p "Waiting up to ${CORE_START_WAIT_SECONDS}s for Core startup; checking every 5s."
	while [ "$SECONDS" -lt "$deadline" ]; do
		[ -n "$(qortal_pids)" ] || { p "Core exited during startup verification."; return 1; }
		height="$(api_get /blocks/height 2>/dev/null)" || height=""
		evidence=""
		if is_height "$height"; then evidence="height API"; elif is_actively_bootstrapping; then evidence="bootstrap progress"; fi
		if [ -n "$evidence" ]; then
			if [ "$stable_since" -lt 0 ]; then
				stable_since="$SECONDS"
				p "Core reports $evidence; confirming it remains running for ${FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS}s."
			fi
			if [ "$((SECONDS - stable_since))" -ge "$FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS" ]; then
				# Recheck process identity after the potentially slow API request.
				if [ -n "$(qortal_pids)" ]; then p "Core startup confirmed after $((SECONDS - started))s."; return 0; fi
				return 1
			fi
		else
			stable_since=-1
		fi
		if [ "$SECONDS" -ge "$next_report" ]; then
			p "Still checking Core startup ($((SECONDS - started))s elapsed; ${CORE_START_WAIT_SECONDS}s maximum)."
			next_report=$((SECONDS + 30))
		fi
		remaining=$((deadline - SECONDS))
		[ "$remaining" -gt 0 ] || break
		delay=5; [ "$remaining" -ge "$delay" ] || delay="$remaining"
		sleep "$delay"
	done
	p "Core startup could not be confirmed; retaining recovery copies."
	return 1
}
cleanup_recovery_backups() {
	local root="${HOME}/qortal/backup" marker backup name sibling
	[ -d "$root" ] || return 0
	# Only delete directories carrying our ownership markers. Never sweep db/data
	# folders elsewhere, manually saved backups, or symlinked backup locations.
	[ ! -L "$root" ] || { p "Backup root is a symlink; skipping automatic cleanup."; return 1; }
	while IFS= read -r -d '' marker; do
		backup="${marker%/*}"; name="${backup##*/}"
		[[ "$name" =~ ^db-[0-9]{14}-[[:alnum:]]{6}$ ]] || continue
		[ ! -L "$backup" ] || continue
		for sibling in "${backup}.original" "${backup}.failed-db"; do
			if [ -e "$sibling" ] && [ ! -L "$sibling" ]; then rm -rf -- "$sibling" || return 1; fi
		done
		rm -rf -- "$backup" || return 1
		p "Removed database recovery backup: $backup"
	done < <(find "$root" -mindepth 2 -maxdepth 2 -type f \( -name .auto-fix-pending -o -name .auto-fix-verified \) -print0)
}
cleanup_backups_if_ready() {
	local root="${HOME}/qortal/backup"
	[ -d "$root" ] && [ ! -L "$root" ] || return 0
	if find "$root" -mindepth 2 -maxdepth 2 -type f \( -name .auto-fix-pending -o -name .auto-fix-verified \) -print -quit | grep -q .; then
		wait_for_core_recovery || return 1
		cleanup_recovery_backups
	fi
}
prune_small_backup_group() {
	local folder="$1" pattern="$2" protected="${3:-}" record name count=0
	[ -d "$folder" ] && [ ! -L "$folder" ] || return 0
	while IFS= read -r -d '' record; do
		name="${record#*$'\t'}"
		[[ "$name" =~ $pattern ]] || continue
		[ "$folder/$name" != "$protected" ] || continue
		count=$((count + 1))
		if [ "$count" -gt "$SMALL_BACKUPS_TO_KEEP" ]; then rm -f -- "$folder/$name" || return 1; fi
	done < <(find "$folder" -mindepth 1 -maxdepth 1 -type f -printf '%T@\t%f\0' | sort -z -nr)
}
prune_small_backups() {
	local settings="${HOME}/qortal/qortal-backup/auto-fix-settings-backup" protected
	protected="$(readlink -f "$settings/latest-good.json" 2>/dev/null)" || protected=""
	prune_small_backup_group "$settings" '^backup-settings-(default-|postmerge-)?[0-9]{14}\.json$' "$protected" || return 1
	prune_small_backup_group "${HOME}/qortal/new-scripts/backups" '^auto-fix-[0-9]{14}\.sh$' || return 1
	prune_small_backup_group "${HOME}/backups/cron-backups" '^crontab-backup-[0-9]{14}$' || return 1
	prune_small_backup_group "${HOME}/qortal/backup/logs" '^log4j2-[0-9]{14}\.properties$'
}
restart_core() {
	is_actively_bootstrapping && { p "Bootstrap active; leaving Core running."; return 0; }
	qortal_kill_and_stop || return 1
	start_core || return 1
	sleep "$FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS"
}
jar_is_valid() {
	[ -s "$1" ] || return 1
	if command -v unzip >/dev/null 2>&1; then
		unzip -tqq "$1" >/dev/null 2>&1 && unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null | grep -qi '^Main-Class:'
	elif command -v jar >/dev/null 2>&1; then
		local validation_dir jar_path valid=1
		validation_dir="$(mktemp -d)" || return 1
		jar_path="$(readlink -f "$1")" || { rm -rf "$validation_dir"; return 1; }
		if (cd "$validation_dir" && jar xf "$jar_path") >/dev/null 2>&1 && grep -qi '^Main-Class:' "$validation_dir/META-INF/MANIFEST.MF"; then valid=0; fi
		rm -rf -- "$validation_dir"
		return "$valid"
	else
		p "No jar validator (unzip/jar); skipping replacement."; return 1
	fi
}
install_start_script() {
	local name="$1" candidate="${HOME}/qortal/.start.sh.download"
	if fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/$name" "$candidate" && sh -n "$candidate" && chmod +x "$candidate"; then
		atomic_write "$candidate" "${HOME}/qortal/start.sh"
	else
		rm -f -- "$candidate"; p "Start script refresh failed; keeping current start.sh."; return 1
	fi
}
node_is_far_behind() {
	local height="$1" reference source=api.qortal.org
	is_height "$height" || return 1
	# A valid primary response is authoritative; the second endpoint is failover.
	reference="$(curl -fsS --connect-timeout 10 --max-time 20 https://api.qortal.org/blocks/height)" || reference=""
	if ! is_height "$reference"; then
		p "Primary reference unavailable/invalid; trying qortal.link."
		source=qortal.link
		reference="$(curl -fsS --connect-timeout 10 --max-time 20 https://qortal.link/blocks/height)" || reference=""
	fi
	if ! is_height "$reference"; then p "No valid reference height; deferring lag recovery."; return 1; fi
	p "Local height $height; reference $source height $reference; lag threshold $MAX_BLOCKS_BEHIND."
	[ "$((reference - height))" -gt "$MAX_BLOCKS_BEHIND" ]
}
# HOME is expanded by cron at execution time.
# shellcheck disable=SC2016
install_managed_cron() {
	local mode="$1" old new errors
	mkdir -p "${HOME}/backups/cron-backups" || return 1
	old="$(mktemp)" || return 1
	new="$(mktemp)" || { rm -f "$old"; return 1; }
	errors="$(mktemp)" || { rm -f "$old" "$new"; return 1; }
	if ! LC_ALL=C crontab -l > "$old" 2> "$errors"; then
		if ! grep -qi 'no crontab' "$errors"; then
			p "Cannot read crontab; leaving it unchanged."; rm -f "$old" "$new" "$errors"; return 1
		fi
	fi
	cp "$old" "${HOME}/backups/cron-backups/crontab-backup-$(date +%Y%m%d%H%M%S)" || { rm -f "$old" "$new" "$errors"; return 1; }
	# Remove only legacy auto-fix invocations; preserve other jobs and variables.
	awk '/^[[:space:]]*#/ || $0 !~ /(^|[ /])auto-fix-qortal\.sh(["[:space:]]|$)/' "$old" > "$new"
	if [ "$mode" = headless ]; then
		if ! grep -q 'start-qortal-core.sh' "$new"; then printf '@reboot "${HOME}/start-qortal-core.sh"\n' >> "$new"; fi
		printf '@reboot sleep 399 && "${HOME}/auto-fix-qortal.sh" > "${HOME}/auto-fix-startup.log" 2>&1\n' >> "$new"
	fi
	printf '1 1 */3 * * "${HOME}/auto-fix-qortal.sh" > "${HOME}/log-auto-fix-cron.log" 2>&1\n' >> "$new"
	if ! cmp -s "$old" "$new"; then
		if ! crontab "$new"; then rm -f "$old" "$new" "$errors"; return 1; fi
	fi
	rm -f "$old" "$new" "$errors"
}

# ================== Functions (keep order) ==================

# Function to update the script initially if needed
initial_update() {
	if [ "$AUTO_FIX_SELF_UPDATE" = 1 ] && [ ! -f "${HOME}/auto_fix_updated" ]; then
		p "${YELLOW}Checking for the latest version of the script...${NC}"
		dl="${HOME}/auto-fix-qortal.sh.download"
		if fetch "$DEFAULT_SCRIPT_URL" "$dl" "$DEFAULT_SCRIPT_MIRROR"; then
			# quick sanity: must contain key functions and current bootstrap-detection logic
			if script_passes_sanity "$dl"; then
				chmod +x "$dl" 2>/dev/null || true
				atomic_write "$dl" "${HOME}/auto-fix-qortal.sh" || return 1
				: > "${HOME}/auto_fix_updated"
				p "${GREEN}Script updated. Restarting...${NC}"
				exec "${HOME}/auto-fix-qortal.sh"
			else
				p "${RED}Downloaded script failed sanity check; continuing with current copy.${NC}"
				rm -f -- "$dl"
			fi
		else
				p "${YELLOW}Could not fetch updated script (network/GitHub hiccup). Continuing with current copy.${NC}"
		fi
	fi
	check_internet
}

check_internet() {
	p "${CYAN}....................................................................${NC}"
	p "${CYAN}THIS SCRIPT RUNS AUTOMATICALLY. LET IT FINISH; DO NOT CLOSE IT EARLY.${NC}"
	p "${CYAN}It keeps Qortal updated and synced. Thanks.  —crowetic${NC}"
	p "${CYAN}....................................................................${NC}"
	sleep 2
	p "${YELLOW}Checking internet connection...${NC}"
	INTERNET_STATUS="UNKNOWN"
	TIMESTAMP="$(date +%s)"

	test_connectivity() { # HEAD check for 2xx response codes
		URL=$1
		status="$(curl -s -o /dev/null -I --max-time 8 --write-out '%{http_code}' "$URL" 2>/dev/null)"
		if [ -n "$status" ] 2>/dev/null && [ "$status" -ge 200 ] 2>/dev/null && [ "$status" -lt 300 ] 2>/dev/null; then
			return 0
		fi
		return 1
	}

	if ping -c 1 -W 1 8.8.4.4 >/dev/null 2>&1; then
		INTERNET_STATUS="UP"
		p "${GREEN}Ping successful to 8.8.4.4${NC}"
	else
		p "${YELLOW}Ping failed, falling back to Qortal domain tests...${NC}"
		if test_connectivity "https://qortal.org"; then
			INTERNET_STATUS="UP"; p "${GREEN}Internet via qortal.org${NC}"
		elif test_connectivity "https://api.qortal.org"; then
			INTERNET_STATUS="UP"; p "${GREEN}Internet via api.qortal.org${NC}"
		elif test_connectivity "https://ext-node.qortal.link"; then
			INTERNET_STATUS="UP"; p "${GREEN}Internet via ext-node.qortal.link${NC}"
		else
			INTERNET_STATUS="DOWN"
		fi
	fi

	if [ "$INTERNET_STATUS" = "UP" ]; then
		p "${BLUE}Internet UP, continuing...${NC}"
		rm -f -- "${HOME}/Desktop/check-qortal-status.sh" 2>/dev/null || true
		cd || exit 1
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh" "${HOME}/qortal/check-qortal-status.sh" || true
		chmod +x "${HOME}/qortal/check-qortal-status.sh" 2>/dev/null || true
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh" "${HOME}/start-qortal.sh" || true
		chmod +x "${HOME}/start-qortal.sh" 2>/dev/null || true
		fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh" "${HOME}/refresh-qortal.sh" || true
		chmod +x "${HOME}/refresh-qortal.sh" 2>/dev/null || true
		check_for_raspi
	else
		p "${RED}Internet is DOWN. Please fix connection and restart device.${NC}"
		sleep 30
		exit 1
	fi
}

check_for_raspi() {
	ARCH="$(uname -m)"
	if [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
		p "${WHITE}Raspberry Pi detected, checking 32/64-bit...${NC}"
		if uname -m | grep -q 'armv7l'; then
			p "${WHITE}32-bit ARM detected, using ARM32 start script${NC}"
			ARM_32_DETECTED=true
			install_start_script start-modified-memory-args.sh

			check_qortal
		else
			p "${WHITE}64-bit ARM detected, proceeding...${NC}"
			ARM_64_DETECTED=true
			check_memory
		fi
	else
		p "${YELLOW}Not a Raspberry Pi, checking Ubuntu version...${NC}"
		if command -v lsb_release >/dev/null 2>&1; then
			UBUNTU_VER="$(lsb_release -rs | cut -d. -f1)"
		else
			UBUNTU_VER="$(grep -o 'VERSION_ID="[0-9]*' /etc/os-release | tr -dc '0-9')"
		fi
		if [ -n "$UBUNTU_VER" ] && [ "$UBUNTU_VER" -ge 24 ] 2>/dev/null; then
			p "${YELLOW}Ubuntu 24+ detected.${NC}"

		fi
		check_memory
	fi
}

check_memory() {
	totalm="$(free -m | awk '/^Mem:/{print $2}')"
	p "${YELLOW}RAM check: ${totalm} MB — selecting start script...${NC}"

	if [ -n "$totalm" ] && [ "$totalm" -le 6000 ] 2>/dev/null; then
		p "${WHITE}< 6GB RAM — using 4GB start script${NC}"
		install_start_script 4GB-start.sh
	elif [ -n "$totalm" ] && [ "$totalm" -ge 6001 ] 2>/dev/null && [ "$totalm" -le 16000 ] 2>/dev/null; then
		p "${WHITE}6–16GB RAM — using mid-range start script${NC}"
		install_start_script start-6001-to-16000m.sh
	else
		p "${WHITE}> 16GB RAM — using high-RAM start script${NC}"
		install_start_script start-high-RAM.sh
	fi

	check_qortal
}

get_latest_remote_version() {
	local remote tag loc
	LATEST_REMOTE_TAG=""; LATEST_REMOTE_NUM=""
	remote="$(curl -fsS --max-time 10 https://api.github.com/repos/qortal/qortal/releases/latest)" || remote=""
	tag="$(printf '%s' "$remote" | sed -n 's/.*"tag_name":[[:space:]]*"v\([0-9.]*\)".*/\1/p')"
	if ! valid_version "$tag"; then
		loc="$(curl -fsSI --max-time 10 https://github.com/qortal/qortal/releases/latest 2>/dev/null)" || loc=""
		tag="$(printf '%s\n' "$loc" | sed -n 's|^[Ll]ocation:.*releases/tag/v\([0-9.]*\)[[:space:]\r]*$|\1|p')"
	fi
	if ! valid_version "$tag" && command -v jq >/dev/null 2>&1; then
		remote="$(curl -fsS --max-time 10 'https://api.github.com/repos/qortal/qortal/releases?per_page=20')" || remote=""
		tag="$(printf '%s' "$remote" | jq -r '[.[] | select(.draft == false and .prerelease == false)][0].tag_name // ""' 2>/dev/null)"
		tag="${tag#v}"
	fi
	if valid_version "$tag"; then LATEST_REMOTE_TAG="$tag"; LATEST_REMOTE_NUM="$tag"; fi
}

check_qortal() {
	p "${YELLOW}Checking qortal version (local vs remote)...${NC}"

	core_running="$(api_get /admin/status || true)"
	if [ -z "$core_running" ]; then
		p "${CYAN}Node not responding. Checking for bootstrapping...${NC}"
		if is_actively_bootstrapping; then
			p "${RED}Bootstrapping detected. Updating script and exiting current cycle...${NC}"
			update_script
			return 0
		fi
		if [ ! -s "${HOME}/qortal/qortal.jar" ]; then
			p "${YELLOW}Core not running and qortal.jar missing. Skipping startup wait; running immediate jar/version recovery checks...${NC}"
		else
			p "${RED}Core not running; waiting 2 minutes in case it is starting slowly...${NC}"
			sleep 120
		fi
	fi

	local_info="$(api_get /admin/info || true)"
	LATEST_LOCAL_BUILD="$(printf '%s' "$local_info" | sed -n 's/.*"buildVersion":[[:space:]]*"\([^"]*\)".*/\1/p')"
	LATEST_LOCAL_NUM="$(printf '%s' "$LATEST_LOCAL_BUILD" | sed -n 's/^qortal-\([0-9]*\.[0-9]*\.[0-9]*\)\(-.*\)\{0,1\}$/\1/p')"

	# Try multiple methods to determine the latest release version.
	get_latest_remote_version

	if [ "$LATEST_REMOTE_TAG" = "$SPECIAL_VERSION" ]; then
		if [ "$LATEST_LOCAL_BUILD" = "$SPECIAL_BUILD_VERSION" ]; then
			p "${GREEN}Latest tag is ${SPECIAL_VERSION} and required build (${SPECIAL_BUILD_VERSION}) is already installed.${NC}"
			check_for_GUI
			return 0
		fi
		p "${YELLOW}Latest tag is ${SPECIAL_VERSION}; temporary core override required (${SPECIAL_BUILD_VERSION}).${NC}"
		check_hash_update_qortal
		return 0
	fi

	if [ -n "$LATEST_LOCAL_NUM" ] && [ -n "$LATEST_REMOTE_NUM" ]; then
		if version_at_least "$LATEST_LOCAL_NUM" "$LATEST_REMOTE_NUM"; then
			p "${GREEN}Local >= remote; no core update needed.${NC}"
			check_for_GUI
		else
			check_hash_update_qortal
		fi
	elif [ -z "$LATEST_REMOTE_NUM" ] && [ -s "${HOME}/qortal/qortal.jar" ]; then
		p "${YELLOW}Release version unavailable; retaining installed jar and checking node health.${NC}"
		check_for_GUI
	else
		check_hash_update_qortal
	fi
}

check_hash_update_qortal() {
	local jar_url="https://github.com/qortal/qortal/releases/latest/download/qortal.jar"
	local candidate="${HOME}/qortal/.qortal.jar.download" installed="${HOME}/qortal/qortal.jar"
	local backup="${HOME}/qortal/qortal.jar.previous" had_installed=false
	is_actively_bootstrapping && { p "Bootstrap active; deferring jar update."; update_script; return 0; }
	if [ "$LATEST_REMOTE_TAG" = "$SPECIAL_VERSION" ]; then jar_url="$SPECIAL_JAR_URL"; fi
	mkdir -p "${HOME}/qortal" || return 1
	if ! fetch "$jar_url" "$candidate" || ! jar_is_valid "$candidate"; then
		p "${RED}Candidate jar download/validation failed; retaining installed jar.${NC}"
		rm -f "$candidate"; update_script; return 1
	fi
	# Compare file contents, independent of their names.
	if [ -s "$installed" ] && cmp -s "$installed" "$candidate"; then
		rm -f "$candidate"; p "${GREEN}Core jar already matches candidate.${NC}"
		check_for_GUI; return 0
	fi
	if is_actively_bootstrapping; then rm -f "$candidate"; update_script; return 0; fi
	if ! qortal_kill_and_stop; then rm -f "$candidate"; return 1; fi
	if [ -e "$installed" ]; then
		if ! cp -p -- "$installed" "$backup"; then rm -f "$candidate"; start_core; return 1; fi
		had_installed=true
	fi
	if ! atomic_write "$candidate" "$installed"; then start_core; return 1; fi
	p "${GREEN}Core jar installed; starting with the existing database.${NC}"
	potentially_update_settings || true
	if ! start_core; then
		p "Core start failed; attempting to restore the previous jar."
		if [ "$had_installed" = true ] && qortal_kill_and_stop && cp -p -- "$backup" "$candidate" && atomic_write "$candidate" "$installed"; then start_core || true; fi
		return 1
	fi
	sleep "$FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS"
	update_script
}

check_for_GUI() {
	if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
		p "${CYAN}GUI detected. Setting up GUI auto-fix...${NC}"
		if [ "$ARM_32_DETECTED" = true ] || [ "$ARM_64_DETECTED" = true ]; then
			p "${WHITE}ARM + GUI — skipping autostart GUI; using cron for reliability.${NC}"
			setup_raspi_cron
		else
			p "${YELLOW}Installing GUI cron + autostart entries...${NC}"
			install_managed_cron gui || return 1
			fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal-GUI.desktop" "${HOME}/auto-fix-qortal-GUI.desktop" || true
			fetch "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.desktop" "${HOME}/start-qortal.desktop" || true
			mkdir -p "${HOME}/.config/autostart" 2>/dev/null || true
			cp -f -- "${HOME}/auto-fix-qortal-GUI.desktop" "${HOME}/.config/autostart" 2>/dev/null || true
			cp -f -- "${HOME}/start-qortal.desktop" "${HOME}/.config/autostart" 2>/dev/null || true
			rm -f -- "${HOME}/auto-fix-qortal-GUI.desktop" "${HOME}/start-qortal.desktop"
			p "${YELLOW}Auto-fix will run in a terminal ~7 minutes after login.${NC}"
			p "${CYAN}Continuing to verify node height...${NC}"
			check_height
		fi
	else
		p "${YELLOW}Headless system detected, setting cron then checking height...${NC}"
		setup_raspi_cron
	fi
}

setup_raspi_cron() {
	if find "${HOME}/.config/autostart" -maxdepth 1 -name 'start-qortal*.desktop' 2>/dev/null | grep -q .; then
		install_managed_cron gui || return 1
	else
		install_managed_cron headless || return 1
	fi
	check_height
}

check_height() {
	local height previous checked attempt stalled=true
	local track="${HOME}/auto_fix_last_height.txt"
	CONFIRMED_STALLED_HEIGHT=""
	is_actively_bootstrapping && { p "Bootstrap active; deferring height recovery."; update_script; return 0; }
	height="$(api_get /blocks/height)" || height=""
	if ! is_height "$height"; then
		if [ "${1:-}" = started ]; then p "Height became unavailable after startup; deferring further recovery."; update_script; return 1; fi
		no_local_height; return
	fi
	# Being behind is an intentional recovery trigger, even if height is advancing.
	if node_is_far_behind "$height"; then force_bootstrap behind; return; fi
	previous="$(cat "$track" 2>/dev/null)" || previous=""
	if [ "$height" = "$previous" ]; then
		for ((attempt=0; attempt<HEIGHT_STALL_RECHECKS; attempt++)); do
			p "Height $height is unchanged; recheck $((attempt + 1))/${HEIGHT_STALL_RECHECKS} in ${HEIGHT_STALL_WAIT_SECONDS}s."
			sleep "$HEIGHT_STALL_WAIT_SECONDS"
			checked="$(api_get /blocks/height)" || checked=""
			if ! is_height "$checked" || [ "$checked" != "$height" ] || is_actively_bootstrapping; then stalled=false; break; fi
		done
		if [ "$stalled" = true ]; then
			CONFIRMED_STALLED_HEIGHT="$height"
			force_bootstrap stalled
			return
		fi
	fi
	printf '%s' "$height" > "$track"
	update_script
}

no_local_height() {
	local candidate="${HOME}/qortal/.log4j2.properties.download"
	is_actively_bootstrapping && { p "Bootstrap active; leaving Core running."; update_script; return 0; }
	if [ ! -f "${HOME}/qortal/qortal.log" ] && compgen -G "${HOME}/qortal/log.t*" >/dev/null; then
		if fetch https://raw.githubusercontent.com/Qortal/qortal/master/log4j2.properties "$candidate" && grep -q 'appender' "$candidate"; then
			qortal_kill_and_stop || return 1
			mkdir -p "${HOME}/qortal/backup/logs" || { start_core; return 1; }
			if [ -f "${HOME}/qortal/log4j2.properties" ]; then
				cp -p "${HOME}/qortal/log4j2.properties" "${HOME}/qortal/backup/logs/log4j2-$(date +%Y%m%d%H%M%S).properties" || { start_core; return 1; }
			fi
			atomic_write "$candidate" "${HOME}/qortal/log4j2.properties" || { start_core; return 1; }
		else
			rm -f "$candidate"; p "Logging refresh failed; retaining existing configuration."
		fi
	fi
	potentially_update_settings || true
	# An unavailable API does not mean the JVM is absent. Never launch a duplicate.
	qortal_kill_and_stop || return 1
	start_core || return 1
	if wait_for_core_recovery; then
		cleanup_recovery_backups || return 1
		if is_actively_bootstrapping; then update_script; else check_height started; fi
	else
		p "API/bootstrap progress still unavailable; preserving database and deferring recovery."
		update_script startup_failed
		return 1
	fi
}

remote_height_checks() {
	local height
	height="$(api_get /blocks/height)" || height=""
	if is_height "$height" && node_is_far_behind "$height"; then force_bootstrap behind; else update_script; fi
}

force_bootstrap() {
	local reason="${1:-}" height backup original db="${HOME}/qortal/db"
	is_actively_bootstrapping && { p "Bootstrap active; skipping recovery."; update_script; return 0; }
	case "$reason" in
		behind)
			height="$(api_get /blocks/height)" || return 1
			if ! node_is_far_behind "$height"; then p "Behind condition no longer confirmed; preserving database."; update_script; return 0; fi ;;
		stalled)
			if ! is_node_genuinely_stuck; then p "Stall no longer confirmed; preserving database."; update_script; return 0; fi ;;
		*) p "No confirmed bootstrap reason; preserving database."; return 1 ;;
	esac
	if command -v jq >/dev/null 2>&1 && is_valid_json_file "${HOME}/qortal/settings.json"; then
		local repository
		repository="$(jq -r '.repositoryPath // "db"' "${HOME}/qortal/settings.json")" || return 1
		if [ "$repository" != db ] && [ "$repository" != 'db/' ] && [ "$repository" != "$db" ] && [ "$repository" != "$db/" ]; then
			p "Custom repositoryPath; refusing automatic bootstrap of the default db."; return 1
		fi
	else
		p "Cannot validate repositoryPath; preserving database."; return 1
	fi
	is_actively_bootstrapping && { update_script; return 0; }
	if [ -L "${HOME}/qortal/backup" ]; then p "Backup root is a symlink; refusing automatic database recovery."; return 1; fi
	qortal_kill_and_stop || return 1
	mkdir -p "${HOME}/qortal/backup" || { start_core; return 1; }
	if [ -L "$db" ]; then p "Database is a symlink; refusing automatic deletion."; start_core; return 1; fi
	if [ -d "$db" ]; then
		backup="$(mktemp -d "${HOME}/qortal/backup/db-$(date +%Y%m%d%H%M%S)-XXXXXX")" || { start_core; return 1; }
		if ! cp -a -- "$db/." "$backup/" || ! diff -qr -- "$db" "$backup" >/dev/null; then
			p "${RED}Database backup failed verification; preserving database.${NC}"
			rm -rf -- "$backup"
			start_core; return 1
		fi
		# Mark ownership only after the copy has been verified.
		if ! : > "$backup/.auto-fix-pending"; then rm -rf -- "$backup"; start_core; return 1; fi
		# Rename the stopped database beside its original path for rollback.
		original="${backup}.original"
		if ! mv -- "$db" "$original"; then start_core; return 1; fi
	fi
	p "${YELLOW}Bootstrapping: confirmed $reason (lag threshold $MAX_BLOCKS_BEHIND blocks).${NC}"
	if ! start_core || ! wait_for_core_recovery; then
		# A failed launch may have created a partial db. Stop it before restoring the
		# original, and retain all recovery copies if shutdown/restoration fails.
		if [ -n "${original:-}" ]; then
			qortal_kill_and_stop || return 1
			if [ -e "$db" ] || [ -L "$db" ]; then
				mv -- "$db" "${backup}.failed-db" || return 1
			fi
			mv -- "$original" "$db" || return 1
			if start_core && wait_for_core_recovery; then cleanup_recovery_backups || return 1; fi
		fi
		return 1
	fi
	cleanup_recovery_backups || return 1
	rm -f -- "${HOME}/auto_fix_last_height.txt"
	update_script
}

potentially_update_settings() {
	p "${GREEN}Validating and updating settings.json (numeric max-merge + forced priorities)...${NC}"

	local QORTAL_DIR SETTINGS_FILE BACKUP_DIR TIMESTAMP BACKUP_FILE LATEST_GOOD_LINK TMP_FILE REMOTE_FILE FINAL_BKP
	QORTAL_DIR="${HOME}/qortal"
	SETTINGS_FILE="${QORTAL_DIR}/settings.json"
	BACKUP_DIR="${QORTAL_DIR}/qortal-backup/auto-fix-settings-backup"
	TIMESTAMP="$(date +%Y%m%d%H%M%S)"
	BACKUP_FILE="${BACKUP_DIR}/backup-settings-${TIMESTAMP}.json"
	LATEST_GOOD_LINK="${BACKUP_DIR}/latest-good.json"
	TMP_FILE="$(mktemp "${QORTAL_DIR}/.settings.json.tmp.XXXXXX")" || return 1
	REMOTE_FILE="$(mktemp "${QORTAL_DIR}/.settings.remote.tmp.XXXXXX")" || { rm -f "$TMP_FILE"; return 1; }

	# Single canonical remote file (default + patch)
	DEFAULT_SETTINGS_URL="${AUTO_FIX_SETTINGS_URL:-https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/settings.json}"
	DEFAULT_SETTINGS_MIRROR="${AUTO_FIX_SETTINGS_MIRROR_URL:-https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/settings.json}"

	mkdir -p "${BACKUP_DIR}" || { rm -f "$TMP_FILE" "$REMOTE_FILE"; return 1; }

	# Ensure jq (best-effort)
	if ! command -v jq >/dev/null 2>&1; then
		p "${YELLOW}jq not found. Attempting install (Debian/Ubuntu)...${NC}"
		if command -v apt-get >/dev/null 2>&1; then
		if [ "$(id -u)" -ne 0 ]; then
			sudo -n apt-get update -y && sudo -n apt-get install -y jq || true
		else
			apt-get update -y && apt-get install -y jq || true
		fi
		fi
	fi

	if ! command -v jq >/dev/null 2>&1; then
		p "${YELLOW}jq unavailable; leaving settings unchanged.${NC}"
		rm -f -- "$TMP_FILE" "$REMOTE_FILE"; return 1
	fi

	# Backup current (even if invalid)
	if [ -f "$SETTINGS_FILE" ]; then
		cp -f -- "$SETTINGS_FILE" "$BACKUP_FILE" || { rm -f "$TMP_FILE" "$REMOTE_FILE"; return 1; }
		if is_valid_json_file "$SETTINGS_FILE"; then
		ln -sfn "$(basename "$BACKUP_FILE")" "$LATEST_GOOD_LINK" 2>/dev/null || true
		fi
	fi

	# Fetch canonical remote
	if ! fetch "$DEFAULT_SETTINGS_URL" "$REMOTE_FILE" "$DEFAULT_SETTINGS_MIRROR" json || ! is_valid_json_file "$REMOTE_FILE"; then
		p "${RED}Failed to fetch remote settings (GitHub+Gitea). Aborting settings update safely.${NC}"
		rm -f -- "$TMP_FILE" "$REMOTE_FILE"
		return 1
	fi

	# If local invalid/missing: install remote as-is
	if ! is_valid_json_file "$SETTINGS_FILE"; then
		p "${YELLOW}settings.json missing/invalid. Installing remote settings as-is.${NC}"
		atomic_write "$REMOTE_FILE" "$SETTINGS_FILE" || return 1
		cp -f -- "$SETTINGS_FILE" "${BACKUP_DIR}/backup-settings-default-${TIMESTAMP}.json" 2>/dev/null || true
		ln -sfn "backup-settings-default-${TIMESTAMP}.json" "$LATEST_GOOD_LINK" 2>/dev/null || true
		p "${GREEN}settings.json created from remote.${NC}"
		rm -f -- "$TMP_FILE"
		return 0
	fi

	# Valid local + valid remote -> merge
	if command -v jq >/dev/null 2>&1; then
		jq -S --slurpfile remote "$REMOTE_FILE" '
		def merge_max($a;$b):
			if   ($a|type)=="object" and ($b|type)=="object" then
				( (($a|keys_unsorted) + ($b|keys_unsorted)) | unique ) as $ks
				| reduce $ks[] as $k
					({}; .[$k] =
						if   ($a|has($k)) and ($b|has($k)) then merge_max($a[$k]; $b[$k])
						elif ($a|has($k))                  then $a[$k]
						else                                     $b[$k]
						end)
			elif ($a|type)=="number" and ($b|type)=="number" then
				(if $a >= $b then $a else $b end)
			else
				# non-number leaves: prefer local if present; else remote
				if ($a == null) then $b else $a end
			end;

		def to_map_array(a):
			(a // [])
			| map(select(has("messageType") and has("limit")))
			| map({
					key: .messageType,
					# coerce numeric strings to numbers if possible, otherwise leave as-is
					value: ( .limit | if type=="string" then (tonumber? // .) else . end )
				})
			| from_entries;

		def merge_thread($l;$p):
			(to_map_array($l)) as $lm
			| (to_map_array($p)) as $pm
			| ( (($lm|keys_unsorted) + ($pm|keys_unsorted)) | unique ) as $keys
			| ( $keys
				| map({
					messageType: .,
					limit:
					( if   (($lm[.]|type)=="number") and (($pm[.]|type)=="number") then
							(if $lm[.] >= $pm[.] then $lm[.] else $pm[.] end)
						elif (($lm[.]|type)=="number") then $lm[.]
						else                                $pm[.]
						end )
				})
			);

		def force_from_remote($merged; $r; $keys):
			reduce ($keys[]) as $k
			($merged;
				if ($r|has($k)) then
					.[$k] = $r[$k]           # force EXACT value from remote, type preserved
				else
					.                         # if remote lacks the key, leave merged value as-is
				end);

		. as $local
		| ($remote[0] // {}) as $r

		# 1) Merge everything except the special array (numeric max-merge)
		| ( merge_max($local; ($r | del(.maxThreadsPerMessageType))) ) as $base

		# 2) Special-case array: max per messageType, union of types
		| ( $base
			| .maxThreadsPerMessageType =
				merge_thread($local.maxThreadsPerMessageType; $r.maxThreadsPerMessageType)
			) as $withThreads

		# 3) Force exact values for specific priority/latency keys from remote if present
		| force_from_remote(
			$withThreads;
			$r;
			[
				"handshakeThreadPriority",
				"dbCacheThreadPriority",
				"networkThreadPriority",
				"pruningThreadPriority",
				"synchronizerThreadPriority",
				"archivingPause"
			]
			)
		' "$SETTINGS_FILE" > "$TMP_FILE" 2>/dev/null

		if is_valid_json_file "$TMP_FILE"; then
			if json_semantically_equal "$SETTINGS_FILE" "$TMP_FILE"; then
				rm -f -- "$TMP_FILE" 2>/dev/null || true
				p "${GREEN}settings.json already up-to-date; no rewrite needed.${NC}"
			else
				atomic_write "$TMP_FILE" "$SETTINGS_FILE" || return 1
				FINAL_BKP="${BACKUP_DIR}/backup-settings-postmerge-${TIMESTAMP}.json"
				cp -f -- "$SETTINGS_FILE" "$FINAL_BKP" 2>/dev/null || true
				ln -sfn "$(basename "$FINAL_BKP")" "$LATEST_GOOD_LINK" 2>/dev/null || true
				p "${GREEN}settings.json merged successfully (max-merge + forced priorities from remote).${NC}"
			fi
		else
			p "${RED}Settings merge failed; retaining current settings.${NC}"
			rm -f -- "$TMP_FILE" "$REMOTE_FILE"; return 1
		fi
	else
		p "${YELLOW}jq unavailable; skipping merge. (Local file left unchanged.)${NC}"
		rm -f -- "$REMOTE_FILE" 2>/dev/null || true
		return 0
	fi

	rm -f -- "$REMOTE_FILE" 2>/dev/null || true
	return 0
}

update_script() {
	# A later healthy run also clears marked copies retained after a failed recovery.
	if [ "${1:-}" != startup_failed ]; then
		cleanup_backups_if_ready || p "Recovery backups retained until startup is confirmed."
	fi
	p "${YELLOW}Updating script to newest version and backing up old one...${NC}"
	mkdir -p "${HOME}/qortal/new-scripts/backups" 2>/dev/null || true
	if [ -f "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" ]; then
		cp -f -- "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups/auto-fix-$(date +%Y%m%d%H%M%S).sh" 2>/dev/null || true
	fi
	if [ -f "${HOME}/auto-fix-qortal.sh" ]; then
		cp -f -- "${HOME}/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups/original.sh" 2>/dev/null || true
	fi

	dl="${HOME}/qortal/new-scripts/auto-fix-qortal.sh.download"
	if [ "$AUTO_FIX_SELF_UPDATE" = 1 ] && fetch "$DEFAULT_SCRIPT_URL" "$dl" "$DEFAULT_SCRIPT_MIRROR"; then
		if script_passes_sanity "$dl"; then
			chmod +x "$dl" 2>/dev/null || true
			atomic_write "$dl" "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" || return 1
			local copy_tmp
			copy_tmp="$(mktemp "${HOME}/.auto-fix-qortal.sh.XXXXXX")" || return 1
			cp -p -- "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "$copy_tmp" && atomic_write "$copy_tmp" "${HOME}/auto-fix-qortal.sh" || return 1
			chmod +x "${HOME}/auto-fix-qortal.sh" 2>/dev/null || true
			rm -f -- "${HOME}/auto_fix_updated"
		else
			p "${RED}Self-update sanity check failed (missing required functions); keeping current script.${NC}"
			rm -f -- "$dl" 2>/dev/null || true
		fi
	else
		if [ "$AUTO_FIX_SELF_UPDATE" = 1 ]; then p "Self-update fetch failed; retaining current script."; else p "Self-update disabled for this run."; fi
	fi

	p "${YELLOW}Checking for any settings changes required...${NC}"
	sleep 1
	potentially_update_settings
	prune_small_backups || p "Could not prune small backup files."

	rm -f -- "${HOME}/remote.md5" "${HOME}/qortal/local.md5" 2>/dev/null || true

	p "${YELLOW}Auto-fix script run complete.${NC}"
	sleep 2
	return 0
}

# ================= Entry =================
# Concurrency lock: ensure only one instance runs at a time so overlapping
# cron/@reboot triggers cannot race during recovery.
for setting in MAX_BLOCKS_BEHIND ACTIVE_LOG_MAX_AGE_SECONDS CORE_START_WAIT_SECONDS HEIGHT_STALL_WAIT_SECONDS HEIGHT_STALL_RECHECKS FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS CORE_STOP_WAIT_SECONDS SMALL_BACKUPS_TO_KEEP; do
	if ! [[ "${!setting}" =~ ^[1-9][0-9]{0,8}$ ]]; then p "Invalid positive integer: $setting"; exit 1; fi
done
if [ ! -d /proc/self ] || ! command -v timeout >/dev/null 2>&1; then
	p "Linux /proc and timeout are required for safe recovery."; exit 1
fi
LOCK_FILE="${HOME}/.auto-fix-qortal.lock"
if command -v flock >/dev/null 2>&1; then
	exec 9>"$LOCK_FILE" || exit 1
	if ! flock -n 9; then
		p "${YELLOW}Another auto-fix instance is already running; exiting.${NC}"
		exit 0
	fi
else
	p "${RED}flock not available; refusing to run recovery without a lock.${NC}"
	exit 1
fi

initial_update
