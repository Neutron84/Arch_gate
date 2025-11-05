#!/usr/bin/env bash
##
##& Ultra-Logger
##^ Purpose: Comprehensive, interactive-safe logging and tracing for Termux
##* Scope: Termux-first with optional Android/Shizuku (rish) and root features

## Settings
##* Fail-fast: exit on error, unset vars, or failed pipeline segments
set -euo pipefail

## ---------------- System detection (Debian/Arch/Gentoo/Termux/Android)
OS_FAMILY=""
DISTRO_ID=""
PKG_MGR=""
HAS_SUDO=0
IS_TERMUX=0
IS_ANDROID=0
PKG_REFRESHED=0

detect_system() {
	## IS_TERMUX: PREFIX path pattern or presence of termux-* utilities
	if [[ -n "${PREFIX:-}" && "$PREFIX" == *"/com.termux/"* ]] || command -v termux-info >/dev/null 2>&1; then
		IS_TERMUX=1
	fi
	## IS_ANDROID: getprop availability
	if command -v getprop >/dev/null 2>&1; then
		IS_ANDROID=1
	fi
	OS_FAMILY="$(uname -s 2>/dev/null || echo unknown)"
	## Read distro info when available
	if [[ -r /etc/os-release ]]; then
		. /etc/os-release
		DISTRO_ID="${ID:-}"
	fi
	## Pick package manager
	if [[ $IS_TERMUX -eq 1 ]]; then
		if command -v pkg >/dev/null 2>&1; then PKG_MGR="pkg"; else PKG_MGR="apt"; fi
	else
		if command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt";
		elif command -v pacman >/dev/null 2>&1; then PKG_MGR="pacman";
		elif command -v emerge >/dev/null 2>&1; then PKG_MGR="emerge";
		elif command -v apk >/dev/null 2>&1; then PKG_MGR="apk"; ## Alpine (best-effort)
		else PKG_MGR=""; fi
	fi
	## Sudo availability
	if command -v sudo >/dev/null 2>&1; then HAS_SUDO=1; fi
}

detect_system

## ================== Overview ==================
## Features
##* Verbose logger with levels: TRACE | DEBUG | INFO | WARN | ERROR | FATAL
##* Periodic snapshots: CPU, RAM, Disk, Processes, Network (size-rotated)
##* TTY recording: script | asciinema | ttyrec (selected via config)
##* Tracing: strace and ltrace wrappers around the target payload
##* Filesystem monitoring: inotify over configured paths (space-safe parsing)
##* Android/Shizuku: logcat (all buffers) + optional periodic dumpsys summaries
##* Clean finishes: user command `endinstall` or AUTO_STOP_AFTER timeout
##* Config-driven: auto-create `config.ini` with grouped, tagged sections
##* Dependencies: best-effort installation via pkg, with clear WARN fallbacks
##* Reliability: safe background process cleanup and final environment snapshot
##* Log rotation: prevents runaway file growth for continuous streams
##* Reports: enriched initial diagnostics and end-of-run colored summary

##^ Notes
##? Interactive safety: never pipe the interactive target; preserves keyboard/touch
##? Space safety: arrays and %q quoting prevent argument splitting

##! Termux limitations (informational)
##! - dmesg → Kernel access may be blocked.
##! - auditd / ausearch → kernel and root required.
##! - eBPF / BCC tools (execsnoop/opensnoop) → root + supported kernel.
##! - tcpdump/wireshark → raw sockets require root.
##! - strace/ltrace may require root on recent Android releases.
## ===========================================================================

##~ Targets on the waiting list:

## ===========================================================================

#!/usr/bin/env bash

##& Ultra-Logger
##^ Purpose: Comprehensive, interactive-safe logging and tracing for Termux
##* Scope: Termux-first with optional Android/Shizuku (rish) and root features

## Settings
##* Fail-fast: exit on error, unset vars, or failed pipeline segments
set -euo pipefail

## ================== Overview ==================
## Features
##* Verbose logger with levels: TRACE | DEBUG | INFO | WARN | ERROR | FATAL
##* Periodic snapshots: CPU, RAM, Disk, Processes, Network (size-rotated)
##* TTY recording: script | asciinema | ttyrec (selected via config)
##* Tracing: strace and ltrace wrappers around the target payload
##* Filesystem monitoring: inotify over configured paths (space-safe parsing)
##* Android/Shizuku: logcat (all buffers) + optional periodic dumpsys summaries
##* Clean finishes: user command `endinstall` or AUTO_STOP_AFTER timeout
##* Config-driven: auto-create `config.ini` with grouped, tagged sections
##* Dependencies: best-effort installation via pkg, with clear WARN fallbacks
##* Reliability: safe background process cleanup and final environment snapshot
##* Log rotation: prevents runaway file growth for continuous streams
##* Reports: enriched initial diagnostics and end-of-run colored summary

##^ Notes
##? Interactive safety: never pipe the interactive target; preserves keyboard/touch
##? Space safety: arrays and %q quoting prevent argument splitting

##! Termux limitations (informational)
##! - dmesg → Kernel access may be blocked.
##! - auditd / ausearch → kernel and root required.
##! - eBPF / BCC tools (execsnoop/opensnoop) → root + supported kernel.
##! - tcpdump/wireshark → raw sockets require root.
##! - strace/ltrace may require root on recent Android releases.
## ===========================================================================

##~ Targets on the waiting list:

## ===========================================================================


## --------------- Read settings from configuration file
##* INI parser (simple): supports [section] and key=value lines
declare -A config
current_section=""
while IFS= read -r line || [[ -n "$line" ]]; do
    ## Strip comments (##...) while respecting no escaping rules for simplicity
    case "$line" in
        \##*) continue;;
    esac
    ## Remove inline comments
    line=${line%%##*}
    ## Trim leading whitespace
    while [[ "$line" == " "* || "$line" == $'\t'* ]]; do line=${line##?}; done
    ## Trim trailing whitespace
    while [[ "$line" == *" " || "$line" == *$'\t' ]]; do line=${line%?}; done

    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        current_section=${BASH_REMATCH[1]}
    elif [[ "$line" =~ ^([a-zA-Z0-9_]+)=(.*) ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        ## Trim whitespace around value
        ## leading
        while [[ "$value" == " "* || "$value" == $'\t'* ]]; do value=${value##?}; done
        ## trailing
        while [[ "$value" == *" " || "$value" == *$'\t' ]]; do value=${value%?}; done
        config["$key"]="$value"
    fi
done < "$config_file"

## Main settings
##* Derived directories use SESSION_ID for isolation
SESSION_ID="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="${BASE_DIR:-$HOME/ultra-logs/$SESSION_ID}"
LOG_DIR="$BASE_DIR/logs"
FILES_DIR="$BASE_DIR/files"
mkdir -p "$LOG_DIR" "$FILES_DIR"

## Read settings from config array with defaults
##? Each reads from parsed INI or falls back to sensible default
REPO_URL="${config[REPO_URL]:-}"
TARGET="${config[TARGET]:-run-target.sh}"
EDIT_BEFORE_RUN="${config[EDIT_BEFORE_RUN]:-0}"
AUTO_STOP_AFTER="${config[AUTO_STOP_AFTER]:-0}"

## Capabilities
ENABLE_TTY_CAPTURE="${config[ENABLE_TTY_CAPTURE]:-1}"
TTY_RECORDER="${config[TTY_RECORDER]:-script}"
ENABLE_INOTIFY="${config[ENABLE_INOTIFY]:-1}"
INOTIFY_PATHS="${config[INOTIFY_PATHS]:-$HOME $PREFIX}"
ENABLE_SNAPSHOTS="${config[ENABLE_SNAPSHOTS]:-1}"
SNAPSHOT_INTERVAL="${config[SNAPSHOT_INTERVAL]:-30}"
ENABLE_STRACE="${config[ENABLE_STRACE]:-1}"
ENABLE_LTRACE="${config[ENABLE_LTRACE]:-0}"
ENABLE_NET_SNAPSHOT="${config[ENABLE_NET_SNAPSHOT]:-1}"

## Shizuku/rish
##? Android service logging options
ENABLE_SHIZUKU="${config[ENABLE_SHIZUKU]:-1}"
SHIZUKU_EXTRA_DUMPS="${config[SHIZUKU_EXTRA_DUMPS]:-1}"

## Advanced settings
##? Verbosity and log rotation size
LOG_LEVEL_CFG="${config[LOG_LEVEL]:-INFO}"
LOG_ROTATE_SIZE_MB="${config[LOG_ROTATE_SIZE_MB]:-50}"

## Root features
##? Require root/tsu/su; disabled gracefully when unavailable
ENABLE_ROOT_FEATURES="${config[ENABLE_ROOT_FEATURES]:-0}"
ENABLE_DMESG="${config[ENABLE_DMESG]:-0}"
ENABLE_AUDIT="${config[ENABLE_AUDIT]:-0}"
ENABLE_BPF="${config[ENABLE_BPF]:-0}"
BPF_EXECSNOOP="${config[BPF_EXECSNOOP]:-0}"
BPF_OPENSNOOP="${config[BPF_OPENSNOOP]:-0}"
ENABLE_TCPDUMP="${config[ENABLE_TCPDUMP]:-0}"
TCPDUMP_IFACE="${config[TCPDUMP_IFACE]:-}"
TCPDUMP_FILTER="${config[TCPDUMP_FILTER]:-}"

## --------------- Logger levels
## Define log levels and their order
log_levels=(TRACE DEBUG INFO WARN ERROR FATAL)
log_level_threshold=0
## Find log level threshold based on LOG_LEVEL_CFG
for i in "${!log_levels[@]}"; do
    if [[ "${log_levels[i]}" == "$LOG_LEVEL_CFG" ]]; then
        log_level_threshold=$i
        break
    fi
done

## Logging function
log() {
    local lvl="$1"; shift
    local -i current_lvl=0
    ## Find current log level
    for i in "${!log_levels[@]}"; do
        [[ "${log_levels[i]}" == "$lvl" ]] && current_lvl=$i && break
    done
    ## If current log level is greater than or equal to threshold, print message
    if [[ $current_lvl -ge $log_level_threshold ]]; then
        printf "[%(%F %T)T][%s] %s\n" -1 "$lvl" "$*" | tee -a "$LOG_DIR/bash.log"
    fi
}
## Helper functions for different log levels
TRACE() { log TRACE "$@"; }
DEBUG() { log DEBUG "$@"; }
INFO() { log INFO "$@"; }
WARN() { log WARN "$@"; }
ERROR() { log ERROR "$@"; }
FATAL() { log FATAL "$@"; exit 1; }

INFO "=== Ultra-Logger (Termux + Shizuku) ==="
INFO "Session ID: $SESSION_ID"
INFO "Logs directory: $LOG_DIR"
INFO "Files directory: $FILES_DIR"

## --------------- Ensure config.ini exists and open for review/edit
config_file="config.ini"
if [[ ! -f "$config_file" ]]; then
    echo "INFO: 'config.ini' not found. Creating a default configuration file."
    cat > "$config_file" <<'EOF'
[Main]
! Purpose: Core target selection and session controls

##* URL to download and execute (optional). If empty, no download occurs.
REPO_URL=https://raw.githubusercontent.com/sabamdarif/termux-desktop/main/setup-termux-desktop

##* Destination filename to save as (or your own local script to run).
##  If REPO_URL is set, this name is used for the downloaded file.
TARGET=setup-termux-desktop.sh

##? Open an editor before running the target (1=yes, 0=no).
EDIT_BEFORE_RUN=0

##? Auto-stop after N seconds (0 disables auto-stop).
AUTO_STOP_AFTER=120


[TTY]
##! Terminal capture and recorder selection

##* Master switch: enable TTY capture (1=yes, 0=no).
ENABLE_TTY_CAPTURE=0

##* Recorder to use when TTY capture is enabled.
##  Valid: script | asciinema | ttyrec | 0 (off)
TTY_RECORDER=0


[Monitoring]
! Filesystem and system monitoring controls

##* Monitor file system changes with inotifywait (1=yes, 0=no).
ENABLE_INOTIFY=1

##? Space-separated paths to watch (quote paths containing spaces).
INOTIFY_PATHS=$HOME/ultra_logs $PREFIX

##* Take periodic system snapshots (CPU, RAM, Disk, Network) (1/0).
ENABLE_SNAPSHOTS=1

##? Interval in seconds between snapshots.
SNAPSHOT_INTERVAL=30


[Tracing]
##^ System and library call tracing

##? Enable strace on target (1/0).
ENABLE_STRACE=0

##? Enable ltrace on target (1/0). // Requires ltrace to be installed
ENABLE_LTRACE=0


[Android/Shizuku]
##^ Android-specific logging via Shizuku/rish (if available)

##* Enable Shizuku/rish features (1/0).
ENABLE_SHIZUKU=1

##? Extra periodic dumpsys (activity, meminfo, netstats) (1/0).
SHIZUKU_EXTRA_DUMPS=1


[Logging]
##^ Logger verbosity and rotation

##* Log level: TRACE | DEBUG | INFO | WARN | ERROR | FATAL
LOG_LEVEL=TRACE

##? Max size (MB) before rotation for large logs (logcat, snapshots).
LOG_ROTATE_SIZE_MB=50


[RootFeatures]
##! Root-only features (require tsu/su or running as root)

##* Master switch for root features section (1/0).
ENABLE_ROOT_FEATURES=0

##? Kernel logs via dmesg -wT (1/0). // May be blocked on some devices
ENABLE_DMESG=0

##? Linux audit framework logs via ausearch (1/0). // Requires audit tools
ENABLE_AUDIT=0

##? eBPF/BCC tools (1/0). // Requires kernel support and bcc tools
ENABLE_BPF=0
BPF_EXECSNOOP=0
BPF_OPENSNOOP=0

##? Packet capture via tcpdump (1/0). // Requires root and tcpdump
ENABLE_TCPDUMP=0

##? Optional: network interface for tcpdump (e.g., wlan0). Empty = auto.
TCPDUMP_IFACE=

##? Optional: tcpdump filter expression (quoted). Empty = none.
TCPDUMP_FILTER=

EOF
    echo "INFO: Default config.ini created in the current directory. Opening editor..."
    ${EDITOR:-nano} "$config_file" || true
else
    INFO "Opening existing config.ini for review. Close the editor to continue."
    ${EDITOR:-nano} "$config_file" || true
fi

## ================= Permission Manager =================
AUTO_APPROVE=0
CURRENT_GROUP=""

begin_group() {
    CURRENT_GROUP="$1"
    AUTO_APPROVE=0
    INFO "New group '${CURRENT_GROUP}' started. Any previous auto-approval is reset."
}

ask_permission() {
    local msg="$1"
    if [[ "$AUTO_APPROVE" -eq 1 ]]; then
        return 0
    fi
    while true; do
        printf "\n>>> %s\n" "$msg"
        printf "Proceed? [a=all, y=yes, n=no, c=cancel]\n"
        read -r ans
        case "$ans" in
            [aA]) AUTO_APPROVE=1; return 0 ;;
            [yY]) return 0 ;;
            [nN]) return 1 ;;
            [cC]) echo "Cancelled by user."; exit 1 ;;
            *) echo "Invalid choice. Use: a / y / n / c." ;;
        esac
    done
}

## --------------- Check for command existence in PATH or next to script
##* Utility: returns 0 if command exists, 1 otherwise
have() { command -v "$1" >/dev/null 2>&1; }

## Function to find rish: in PATH or next to script
##? Prefer PATH; fallback to sibling file; prints empty string on failure
find_rish() {
    local rish_cmd="rish"
    if have "$rish_cmd"; then
        echo "$rish_cmd"
        return 0
        elif [[ -x "$(dirname "$0")/rish" ]]; then
        echo "$(dirname "$0")/rish"
        return 0
    fi
    echo ""
    return 1
}

## Function to convert array to safe string
##* Joins arguments and escapes them with %q for safe shell reuse
array_to_quoted_string() {
    local out=""
    printf -v out '%q ' "$@"
    out=${out% }
    printf '%s' "$out"
}

## Root detection and runner helpers
##? Use tsu/su to elevate when not already root
is_root() {
    if [[ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]]; then
        return 0
    fi
    return 1
}

find_root_runner() {
	## Prefer sudo when available (non-interactive if possible), then tsu/su
	if [[ $HAS_SUDO -eq 1 ]]; then
		printf '%s\n' "sudo" "-n"
		return 0
	fi
	if have tsu; then
		printf '%s\n' "tsu" "-c"
		return 0
	elif have su; then
		printf '%s\n' "su" "-c"
		return 0
	fi
	printf '%s\n' "" ""
	return 1
}

run_as_root() {
    ##* Usage: run_as_root <command> [arg1 ...]
    ##? Elevates and runs while preserving argument boundaries using printf %q
    if is_root; then
        "$@"
        return $?
    fi
    local runner cmd_flag
    read -r runner cmd_flag < <(find_root_runner)
    if [[ -n "$runner" ]]; then
        local cmd_str=""
        printf -v cmd_str '%q ' "$@"
        cmd_str=${cmd_str% }
        "$runner" "$cmd_flag" "$cmd_str"
        return $?
    fi
    return 127
}

## Resolve a package name for the current distro given a desired name or command
_resolve_pkg_name() {
	local want="$1"
	case "$PKG_MGR" in
		apt)
			case "$want" in
				ss) echo "iproute2";;
				inotifywait) echo "inotify-tools";;
				top) echo "procps";;
				netstat) echo "net-tools";;
				asciinema) echo "asciinema";;
				ttyrec) echo "ttyrec";;
				*) echo "$want";;
			esac
			;;
		pacman)
			case "$want" in
				ss) echo "iproute2";;
				inotifywait) echo "inotify-tools";;
				top) echo "procps-ng";;
				netstat) echo "net-tools";;
				asciinema) echo "asciinema";;
				ttyrec) echo "ttyrec";;
				*) echo "$want";;
			esac
			;;
		emerge)
			case "$want" in
				ss) echo "sys-apps/iproute2";;
				inotifywait) echo "sys-fs/inotify-tools";;
				top) echo "sys-process/procps";;
				netstat) echo "net-tools";;
				asciinema) echo "app-misc/asciinema";;
				ttyrec) echo "app-misc/ttyrec";;
				strace) echo "dev-util/strace";;
				ltrace) echo "dev-util/ltrace";;
				tcpdump) echo "net-analyzer/tcpdump";;
				*) echo "$want";;
			esac
			;;
		apk)
			case "$want" in
				ss) echo "iproute2";;
				inotifywait) echo "inotify-tools";;
				top) echo "procps";;
				netstat) echo "net-tools";;
				*) echo "$want";;
			esac
			;;
		pkg|*)
			echo "$want";;
	esac
}

_install_pkg_once() {
	local pkg="$1"
	case "$PKG_MGR" in
		apt)
			if [[ $PKG_REFRESHED -eq 0 ]]; then
				if [[ "$AUTO_APPROVE" -eq 1 ]] || ask_permission "Run apt-get update?"; then
					run_as_root apt-get update -y || true
				fi
				PKG_REFRESHED=1
			fi
			run_as_root apt-get install -y "$pkg" || return 1
			;;
		pacman)
			run_as_root pacman -Sy --noconfirm "$pkg" || return 1
			;;
		emerge)
			run_as_root emerge -n "$pkg" || return 1
			;;
		apk)
			run_as_root apk add --no-interactive "$pkg" || return 1
			;;
		pkg)
			run_as_root pkg install "$pkg" -y || return 1
			;;
		*)
			return 1
			;;
	esac
	return 0
}

## Function to check and install dependencies (multi-distro)
req_pkg() {
	local pkg_name="$1" ## requested package or command hint
	local cmd_name="$2" ## executable to validate
	cmd_name="${cmd_name:-$pkg_name}"
	if have "$cmd_name"; then
		return 0
	fi
	WARN "Dependency '$cmd_name' not found. Attempting to install..."
	local resolved
	resolved="$(_resolve_pkg_name "$pkg_name")"
	if [[ -z "$PKG_MGR" ]]; then
		WARN "No supported package manager detected. Please install '$resolved' manually."
		return 1
	fi
	if [[ "$AUTO_APPROVE" -eq 1 ]] || ask_permission "Install '$resolved' using $PKG_MGR?"; then
		_install_pkg_once "$resolved" || { WARN "Failed to install '$resolved'."; return 1; }
		if have "$cmd_name"; then
			INFO "Installed '$resolved' providing '$cmd_name'."
			return 0
		else
			WARN "'$resolved' installed but '$cmd_name' still missing."
			return 1
		fi
	else
		WARN "User denied installation for '$resolved'."
		return 1
	fi
}

## --------------- Check and install required dependencies
INFO "Checking and installing dependencies..."
begin_group "deps"
req_pkg "termux-tools" "script"
req_pkg "iproute2" "ss"
req_pkg "net-tools" "netstat"
req_pkg "procps" "top"
req_pkg "curl" "curl"

## Optional features
if [[ "$ENABLE_INOTIFY" == "1" ]]; then
    req_pkg "inotify-tools" "inotifywait"
fi

if [[ "$ENABLE_STRACE" == "1" ]]; then
    req_pkg "strace" "strace"
fi

if [[ "$ENABLE_LTRACE" == "1" ]]; then
    req_pkg "ltrace" "ltrace"
fi

## Optional TTY recorder tools
if [[ "$ENABLE_TTY_CAPTURE" == "1" ]]; then
    case "$TTY_RECORDER" in
        asciinema)
            req_pkg "asciinema" "asciinema" ;;
        ttyrec)
            req_pkg "ttyrec" "ttyrec" ;;
        0)
            INFO "TTY_RECORDER=0: TTY capture disabled by recorder selection."
            ENABLE_TTY_CAPTURE=0
            ;;
        tee|script|*)
            : ;; ## no extra deps
    esac
fi

## Root features
if [[ "$ENABLE_ROOT_FEATURES" == "1" ]]; then
    if [[ "$ENABLE_DMESG" == "1" ]]; then
        req_pkg "termux-tools" "dmesg"
    fi
    if [[ "$ENABLE_AUDIT" == "1" ]]; then
        req_pkg "audit" "ausearch" ## Assuming 'audit' is the package name
    fi
    if [[ "$ENABLE_BPF" == "1" ]]; then
        if [[ "$BPF_EXECSNOOP" == "1" ]]; then
            req_pkg "bcc" "execsnoop" ## Assuming 'bcc' is the package
        fi
        if [[ "$BPF_OPENSNOOP" == "1" ]]; then
            req_pkg "bcc" "opensnoop"
        fi
    fi
    if [[ "$ENABLE_TCPDUMP" == "1" ]]; then
        req_pkg "tcpdump" "tcpdump"
    fi
fi

## --------------- Initial snapshot (Diagnostics)
##* Captures uname/uptime/packages/env; helps reproduce user environments
{
    echo "== uname =="; uname -a || true
    echo "== uptime =="; uptime || true
    echo "== termux-info =="; termux-info || true
    echo "== env =="; env || true
    echo "== packages =="; pkg list-installed || true
    echo "== SELinux status =="; getenforce || true
    echo "== PREFIX/bin content =="; ls -al "$PREFIX/bin" || true
    RISH_PATH=$(find_rish)
    if [[ "$ENABLE_SHIZUKU" == "1" && -n "$RISH_PATH" ]]; then
        echo "== Android services (via Shizuku/rish) =="; "$RISH_PATH" dumpsys activity services | head -n 200 || true
    fi
} > "$LOG_DIR/diagnostics.txt" 2>&1
INFO "Initial diagnostics saved to $LOG_DIR/diagnostics.txt."

## --------------- Input validation
if [[ -n "${REPO_URL:-}" ]]; then
    if [[ ! "$REPO_URL" =~ ^https?:// ]]; then
        FATAL "Invalid REPO_URL format: '$REPO_URL'. It must start with http:// or https://."
    fi
fi

## --------------- If REPO_URL is set: Download target (Group B)
if [[ -n "${REPO_URL:-}" ]]; then
    begin_group "target-download"
    if ask_permission "Download target script from $REPO_URL?"; then
        INFO "Downloading target from: $REPO_URL"
        CURL_TRACE="$LOG_DIR/curl-trace.txt"
        CURL_HDRS="$LOG_DIR/curl-headers.txt"
        
        curl -Lf --trace-ascii "$CURL_TRACE" -D "$CURL_HDRS" -o "$FILES_DIR/$TARGET" "$REPO_URL" 2>>"$LOG_DIR/bash.log" \
        || FATAL "Download failed for '$REPO_URL'."
        cp -f "$FILES_DIR/$TARGET" "./$TARGET"
        chmod +x "./$TARGET"
        INFO "Target saved to ./$TARGET and made executable."
        if [[ "$EDIT_BEFORE_RUN" == "1" ]]; then
            INFO "Opening target script for editing. Press Ctrl+X to save and exit nano."
            ${EDITOR:-nano} "./$TARGET" || true
        fi
    else
        WARN "User skipped target download."
    fi
fi

## --------------- Disable clear/tput to preserve output
##? Prevents accidental screen clears by target scripts while logging
## These scripts temporarily override the clear and tput functions in the target execution environment
## to prevent accidental clearing of console output during logging.
DISABLE_CLEAR_SH="$FILES_DIR/disable-clear.sh"
cat > "$DISABLE_CLEAR_SH" <<'EOF'
__LOG_FILE="${LOG_DIR_OVERRIDE:-/dev/null}" ## Points to bash.log
clear() { printf '[DEBUG] clear() ignored\n' >> "$__LOG_FILE"; }
tput() {
    if [[ "$1" == "reset" || "$1" == "clear" ]]; then
        printf '[DEBUG] tput %s ignored\n' "$1" >> "$__LOG_FILE";
        return 0;
    fi;
    command tput "$@";
}
export -f clear tput
EOF
ENV_SH="$FILES_DIR/env-logger.sh"
cat > "$ENV_SH" <<EOF
export LOG_DIR_OVERRIDE="$LOG_DIR/bash.log"
EOF

## --------------- inotify file system monitoring
##* Converts INOTIFY_PATHS to array to preserve spaces in paths
INOTIFY_PIDS=()
if [[ "$ENABLE_INOTIFY" == "1" ]] && req_pkg "inotify-tools" "inotifywait"; then
    begin_group "feature:inotify"
    if ask_permission "Start inotify monitoring on configured paths?"; then
    INFO "Starting inotify on paths: $INOTIFY_PATHS"
    ## Convert INOTIFY_PATHS string to array to handle paths with spaces correctly

     read -r -a INOTIFY_PATHS_ARRAY <<< "$INOTIFY_PATHS"
    ##eval "read -r -a INOTIFY_PATHS_ARRAY <<< $INOTIFY_PATHS"
    for P in "${INOTIFY_PATHS_ARRAY[@]}"; do
        if [[ -d "$P" ]]; then
            ## inotifywait runs in the background and sends output to a log file
            inotifywait -m -r -e create,delete,modify,attrib,move "$P" > "$LOG_DIR/fs.$(echo "$P" | tr '/ ' '__').log" 2>&1 &
            INOTIFY_PIDS+=($!)
            DEBUG "inotifywait for $P started with PID ${INOTIFY_PIDS[-1]}"
        else
            WARN "Inotify path '$P' is not a directory, skipping."
        fi
    done
    else
        WARN "Inotify monitoring skipped by user."
    fi
else
    WARN "inotify disabled or 'inotifywait' not found/installed. File system monitoring skipped."
fi

## --------------- Snapshot periodic resources/network/process
##* Streams snapshots into rotating files via split
SNAP_PID=""
snapshot_once(){
    {
        echo "===== $(date '+%F %T') ====="
        echo "-- top (1 iteration) --"; top -b -n 1 2>/dev/null || true
        echo "-- ps (top 200 by CPU) --"; ps -eo pid,ppid,user,stat,%cpu,%mem,etime,cmd --sort=-%cpu 2>/dev/null | head -n 200 || true
        echo "-- memory usage --"; free -h 2>/dev/null || true
        echo "-- disk usage --"; df -h 2>/dev/null || true
        if [[ "$ENABLE_NET_SNAPSHOT" == "1" ]]; then
            ## First we try ss, if not found then netstat
            if have "ss"; then
                echo "-- network sockets (ss) --"; ss -tulpn 2>/dev/null || true
                elif have "netstat"; then
                echo "-- network sockets (netstat) --"; netstat -tulpn 2>/dev/null || true
            else
                WARN "Neither 'ss' nor 'netstat' found for network snapshot."
            fi
        fi
    }
}
if [[ "$ENABLE_SNAPSHOTS" == "1" ]]; then
    begin_group "feature:snapshots"
    if ask_permission "Start periodic snapshots every ${SNAPSHOT_INTERVAL} seconds?"; then
    INFO "Starting periodic snapshots every ${SNAPSHOT_INTERVAL} seconds."
    ## Snapshots are taken periodically and their output is streamed to split
    ## split divides the files based on size (LOG_ROTATE_SIZE_MB) and appends each part to snapshots.log
    (
        while true; do
            snapshot_once
            sleep "$SNAPSHOT_INTERVAL"
        done
    ) | stdbuf -oL split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE"' - "$LOG_DIR/snapshots." 2>/dev/null &
    SNAP_PID=$!
    DEBUG "Snapshot service started with PID $SNAP_PID"
    else
        WARN "Periodic snapshots skipped by user."
    fi
else
    WARN "Periodic snapshots disabled."
fi

## --------------- Shizuku/rish: logcat + dumpsys
RISH_OK=0
RISH_CMD=$(find_rish)
if [[ "$ENABLE_SHIZUKU" == "1" && -n "$RISH_CMD" ]]; then
    begin_group "feature:shizuku"
    if ask_permission "Start Shizuku/rish logcat capture and optional dumpsys?"; then
    INFO "Shizuku/rish detected at '$RISH_CMD'. Starting logcat capture..."
    ## logcat captures logs in threadtime format from all buffers and splits them
    ( "$RISH_CMD" logcat -v threadtime -b all 2>&1 ) | stdbuf -oL split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE"' - "$LOG_DIR/logcat." 2>/dev/null &
    LOGCAT_PID=$!
    RISH_OK=1
    DEBUG "Logcat capture started with PID $LOGCAT_PID"
    
    if [[ "$SHIZUKU_EXTRA_DUMPS" == "1" ]]; then
        INFO "Starting periodic dumpsys (activity, meminfo, netstats)..."
        ## Additional dumpsys commands are run periodically
        (
            while true; do
                {
                    echo "===== $(date '+%F %T') ====="
                    echo "-- dumpsys activity processes --";  "$RISH_CMD" dumpsys activity processes 2>&1 || true
                    echo "-- dumpsys meminfo (top) --";       "$RISH_CMD" dumpsys meminfo 2>&1 | head -n 300 || true
                    echo "-- dumpsys netstats --";            "$RISH_CMD" dumpsys netstats 2>&1 | head -n 400 || true
                } >> "$LOG_DIR/dumpsys.periodic.txt"
                sleep "$SNAPSHOT_INTERVAL"
            done
        ) &
        DUMPSYS_PID=$!
        DEBUG "Dumpsys service started with PID $DUMPSYS_PID"
    fi
    else
        WARN "Shizuku/rish logging skipped by user."
    fi
else
    WARN "Shizuku disabled or 'rish' not found/installed; skipping logcat/dumpsys."
    LOGCAT_PID=""; DUMPSYS_PID=""
fi

## --------------- Root-only features: dmesg, audit, BPF (execsnoop/opensnoop), tcpdump
DMESG_PID=""; AUDIT_PID=""; BPF_EXECSNOOP_PID=""; BPF_OPENSNOOP_PID=""; TCPDUMP_PID=""
if [[ "$ENABLE_ROOT_FEATURES" == "1" ]]; then
    begin_group "feature:root"
    if ask_permission "Enable root feature set (dmesg/audit/BPF/tcpdump) now?" && ( is_root || find_root_runner >/dev/null ); then
        ## dmesg follower
        if [[ "$ENABLE_DMESG" == "1" ]] && have dmesg; then
            INFO "Starting dmesg -wT capture..."
            (
                run_as_root dmesg -wT 2>&1 |
                stdbuf -oL split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE"' - "$LOG_DIR/dmesg." 2>/dev/null
            ) &
            DMESG_PID=$!
            DEBUG "dmesg capture started with PID $DMESG_PID"
        elif [[ "$ENABLE_DMESG" == "1" ]]; then
            WARN "dmesg not found; skipping kernel log capture."
        fi

        ## Audit logs (best-effort; only if tools exist)
        if [[ "$ENABLE_AUDIT" == "1" ]]; then
            if have ausearch; then
                INFO "Starting periodic audit log capture (ausearch)..."
                (
                    while true; do
                        {
                            echo "===== $(date '+%F %T') ====="
                            run_as_root ausearch -m ALL -ts recent -i 2>&1 || true
                        } >> "$LOG_DIR/audit.periodic.txt"
                        sleep "$SNAPSHOT_INTERVAL"
                    done
                ) &
                AUDIT_PID=$!
                DEBUG "Audit capture started with PID $AUDIT_PID"
            else
                WARN "Audit tools not found (ausearch); skipping audit capture."
            fi
        fi

        ## BPF tools
        if [[ "$ENABLE_BPF" == "1" ]]; then
            if [[ "$BPF_EXECSNOOP" == "1" ]] && have execsnoop; then
                INFO "Starting BPF execsnoop..."
                run_as_root execsnoop > "$LOG_DIR/execsnoop.log" 2>&1 &
                BPF_EXECSNOOP_PID=$!
                DEBUG "execsnoop started with PID $BPF_EXECSNOOP_PID"
            elif [[ "$BPF_EXECSNOOP" == "1" ]]; then
                WARN "execsnoop not found; skipping."
            fi
            if [[ "$BPF_OPENSNOOP" == "1" ]] && have opensnoop; then
                INFO "Starting BPF opensnoop..."
                run_as_root opensnoop > "$LOG_DIR/opensnoop.log" 2>&1 &
                BPF_OPENSNOOP_PID=$!
                DEBUG "opensnoop started with PID $BPF_OPENSNOOP_PID"
            elif [[ "$BPF_OPENSNOOP" == "1" ]]; then
                WARN "opensnoop not found; skipping."
            fi
        fi

        ## tcpdump capture to rotating chunks (pcap)
        if [[ "$ENABLE_TCPDUMP" == "1" ]] && have tcpdump; then
            begin_group "feature:tcpdump"
            if ask_permission "Start tcpdump capture (pcap rotated to $LOG_DIR)?"; then
            INFO "Starting tcpdump capture..."
            TCPDUMP_CMD=(tcpdump -vv -s0 -U -w -)
            [[ -n "$TCPDUMP_IFACE" ]] && TCPDUMP_CMD+=( -i "$TCPDUMP_IFACE" )
            if [[ -n "$TCPDUMP_FILTER" ]]; then
                TCPDUMP_CMD+=( "$TCPDUMP_FILTER" )
            fi
            (
                run_as_root "${TCPDUMP_CMD[@]}" |
                split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE".pcap' - "$LOG_DIR/tcpdump." 2>/dev/null
            ) &
            TCPDUMP_PID=$!
            DEBUG "tcpdump started with PID $TCPDUMP_PID"
            else
                WARN "tcpdump capture skipped by user."
            fi
        elif [[ "$ENABLE_TCPDUMP" == "1" ]]; then
            WARN "tcpdump not found; skipping network packet capture."
        fi
    else
        WARN "Root not available (tsu/su not found or denied); skipping root-only features."
    fi
else
    DEBUG "Root features disabled by configuration."
fi

## --------------- Running target with TTY capture + strace/ltrace
BASH_LOG="$LOG_DIR/bash.log"
TTY_LOG="$LOG_DIR/tty.typescript"
RUN_PAYLOAD=( true ) ## Default: do nothing (if no target specified)

## Check for target file existence and how to run it
if [[ -x "./$TARGET" ]]; then
    RUN_PAYLOAD=( "./$TARGET" )
    elif [[ -n "${REPO_URL:-}" ]]; then
    RUN_PAYLOAD=( bash "./$TARGET" ) ## If we downloaded it but it's not executable, run with bash
else
    INFO "No target script specified (REPO_URL empty and ./$TARGET not found). Running 'true' as placeholder."
fi

## Construct command chain to run target
## Source helper scripts to disable clear/tput
RUN_PAYLOAD_CMD=$(array_to_quoted_string "${RUN_PAYLOAD[@]}")
CMD_CHAIN=( bash -xv -c "source '$ENV_SH' && source '$DISABLE_CLEAR_SH' && $RUN_PAYLOAD_CMD" )

## Run strace/ltrace if enabled
LAUNCH=( "${CMD_CHAIN[@]}" )
if [[ "$ENABLE_LTRACE" == "1" ]] && have ltrace; then
    LAUNCH=( ltrace -f -o "$LOG_DIR/ltrace.%p.log" -- "${LAUNCH[@]}" )
    INFO "ltrace enabled for payload."
fi
if [[ "$ENABLE_STRACE" == "1" ]] && have strace; then
    LAUNCH=( strace -ff -o "$LOG_DIR/strace.%p.log" -- "${LAUNCH[@]}" )
    INFO "strace enabled for payload."
fi

INFO "Launching payload with tracing..."
LAUNCH_CMD=$(array_to_quoted_string "${LAUNCH[@]}")
begin_group "target-exec"
if ! ask_permission "Execute TARGET script now?"; then
    WARN "User denied execution of target script. Skipping payload launch."
    WRAPPER_PID=""
elif [[ "$ENABLE_TTY_CAPTURE" == "1" ]]; then
    case "$TTY_RECORDER" in
        script)
            if have script; then
                INFO "Executing with TTY recorder 'script': $LAUNCH_CMD"
                script -q -f -c "$LAUNCH_CMD" "$TTY_LOG" &
                WRAPPER_PID=$!
                INFO "Payload wrapper (script) started with PID $WRAPPER_PID"
            else
                WARN "Requested TTY recorder 'script' not available. Running without TTY recording."
                bash -lc "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload started directly with PID $WRAPPER_PID"
            fi
            ;;
        0)
            INFO "TTY_RECORDER=0: Running without TTY recording."
            bash -lc "$LAUNCH_CMD" &
            WRAPPER_PID=$!
            INFO "Payload started directly with PID $WRAPPER_PID"
            ;;
        asciinema)
            if have asciinema; then
                INFO "Executing with TTY recorder 'asciinema': $LAUNCH_CMD"
                asciinema rec -q -c "$LAUNCH_CMD" "$LOG_DIR/tty-asciinema.cast" &
                WRAPPER_PID=$!
                INFO "Payload (asciinema) started with PID $WRAPPER_PID"
            else
                WARN "Requested TTY recorder 'asciinema' not available. Proceeding without TTY recording."
                bash -lc "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload started directly with PID $WRAPPER_PID"
            fi
            ;;
        ttyrec)
            if have ttyrec; then
                INFO "Executing with TTY recorder 'ttyrec': $LAUNCH_CMD"
                ttyrec -q "$LOG_DIR/tty.ttyrec" bash -c "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload (ttyrec) started with PID $WRAPPER_PID"
            else
                WARN "Requested TTY recorder 'ttyrec' not available. Proceeding without TTY recording."
                bash -lc "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload started directly with PID $WRAPPER_PID"
            fi
            ;;
        *)
            WARN "Unknown TTY_RECORDER='$TTY_RECORDER' or 'tee' selected. Running without TTY recording to preserve interactivity."
            bash -lc "$LAUNCH_CMD" &
            WRAPPER_PID=$!
            INFO "Payload started directly with PID $WRAPPER_PID"
            ;;
    esac
else
    ## Run target without TTY capture
    WARN "TTY capture disabled. Running interactively without additional recording."
    bash -lc "$LAUNCH_CMD" &
    WRAPPER_PID=$!
    INFO "Payload started directly with PID $WRAPPER_PID"
fi

## --------------- Command finish loop (interactive or automatic monitoring)
finish_time=""
if [[ "$AUTO_STOP_AFTER" -gt 0 ]]; then
    INFO "Logging will automatically stop in ${AUTO_STOP_AFTER} seconds."
    finish_time=$(( SECONDS + AUTO_STOP_AFTER ))
fi

## Setup traps to gracefully stop on signals
trap 'INFO "SIGINT received. Stopping monitors..."; break' INT
trap 'INFO "SIGTERM received. Stopping monitors..."; break' TERM
trap 'INFO "Exit detected. Stopping monitors..."' EXIT

INFO "Logging is running in background. To stop, type 'endinstall' and press Enter."
INFO "You can minimize Termux or run other commands while this is running."
while true; do
    if [[ -n "$finish_time" ]] && [[ "$SECONDS" -ge "$finish_time" ]]; then
        INFO "AUTO_STOP_AFTER limit reached. Stopping monitors..."
        break
    fi
    ## read with -t 1 times out every 1 second so we can check AUTO_STOP_AFTER
    read -r -t 1 -p "" CMD || continue ## Monitor user input in the background
    if [[ "$CMD" == "endinstall" ]]; then
        INFO "User requested to stop monitors. Stopping..."
        break
        elif [[ -n "$CMD" ]]; then
        INFO "Unknown command: '$CMD' (type 'endinstall' to finish)"
    fi
done

## --------------- Stopping background processes
## Function safe_kill for safely stopping processes
safe_kill() {
    local pid="$1"
    if [[ -z "$pid" ]]; then return 0; fi ## If PID is empty, do nothing
    
    INFO "Attempting to terminate PID $pid gracefully..."
    kill -TERM "$pid" 2>/dev/null || { DEBUG "PID $pid not found or already terminated with TERM."; return 0; }
    sleep 2 ## Give the process 2 seconds to respond to TERM
    
    if kill -0 "$pid" 2>/dev/null; then ## If process is still alive
        WARN "Process $pid did not terminate gracefully after SIGTERM. Sending SIGKILL."
        kill -KILL "$pid" 2>/dev/null || { WARN "Failed to send SIGKILL to PID $pid."; }
    else
        DEBUG "Process $pid terminated gracefully."
    fi
}

INFO "Terminating all background logging processes..."
for pid in "${INOTIFY_PIDS[@]:-}"; do safe_kill "$pid"; done
[[ -n "${SNAP_PID:-}" ]] && safe_kill "$SNAP_PID" || true
[[ "${RISH_OK}" -eq 1 && -n "${LOGCAT_PID:-}" ]] && safe_kill "$LOGCAT_PID" || true
[[ "${RISH_OK}" -eq 1 && -n "${DUMPSYS_PID:-}" ]] && safe_kill "$DUMPSYS_PID" || true
[[ -n "${DMESG_PID:-}" ]] && safe_kill "$DMESG_PID" || true
[[ -n "${AUDIT_PID:-}" ]] && safe_kill "$AUDIT_PID" || true
[[ -n "${BPF_EXECSNOOP_PID:-}" ]] && safe_kill "$BPF_EXECSNOOP_PID" || true
[[ -n "${BPF_OPENSNOOP_PID:-}" ]] && safe_kill "$BPF_OPENSNOOP_PID" || true
[[ -n "${TCPDUMP_PID:-}" ]] && safe_kill "$TCPDUMP_PID" || true
safe_kill "$WRAPPER_PID" || true

## --------------- Saving final snapshot and Checksums + Archiving
INFO "Saving final system snapshot..."
snapshot_once >> "$LOG_DIR/snapshots.log" ## Save the final snapshot

(
    cd "$BASE_DIR"
    INFO "Generating SHA256 checksums for all collected files..."
    ## Find all files and compute their SHA256 hashes
    find . -type f -print0 | xargs -0 sha256sum > "$LOG_DIR/checksums.sha256" || true
    INFO "Creating final archive of logs and files..."
    ## Compress logs and files directories into a tar.gz file
    tar -czf "$BASE_DIR/all-logs.$SESSION_ID.tar.gz" logs files
) || true

## --------------- Completion summary report with ANSI color coding
##* ANSI color codes
COLOR_RESET="\033[0m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"

total_logs=$(find "$LOG_DIR" -type f | wc -l)
total_files_collected=$(find "$FILES_DIR" -type f | wc -l)
warnings_count=$(grep -c 'WARN' "$LOG_DIR/bash.log" || true)
errors_count=$(grep -c 'ERROR' "$LOG_DIR/bash.log" || true)

INFO "================ DONE ================"
INFO "Summary Report for Session: $SESSION_ID"
INFO "  Total log files generated : $total_logs"
INFO "  Total collected files     : $total_files_collected"
INFO "  Total warnings in bash.log: ${COLOR_YELLOW}$warnings_count${COLOR_RESET}"
INFO "  Total errors in bash.log  : ${COLOR_RED}$errors_count${COLOR_RESET}"

##* Feature overview
INFO "  TTY capture                : ENABLE_TTY_CAPTURE=$ENABLE_TTY_CAPTURE, RECORDER=$TTY_RECORDER"
INFO "  Tracing                    : strace=$ENABLE_STRACE, ltrace=$ENABLE_LTRACE"
INFO "  Monitoring                 : inotify=$ENABLE_INOTIFY, snapshots=$ENABLE_SNAPSHOTS (@${SNAPSHOT_INTERVAL}s)"
INFO "  Android/Shizuku            : enabled=$ENABLE_SHIZUKU, rish_ok=$RISH_OK, extra_dumps=$SHIZUKU_EXTRA_DUMPS"
INFO "  Root features              : master=$ENABLE_ROOT_FEATURES, dmesg=$ENABLE_DMESG, audit=$ENABLE_AUDIT, bpf=$ENABLE_BPF, tcpdump=$ENABLE_TCPDUMP"
INFO "  Tcpdump opts               : iface='${TCPDUMP_IFACE:-}' filter='${TCPDUMP_FILTER:-}'"

##? Inotify paths summary (word-count; quoted paths may contain spaces)
INFO "  Inotify paths (count)      : $(printf '%s\n' $INOTIFY_PATHS | wc -w 2>/dev/null || echo 0)"

INFO "All logs and files are saved in: ${COLOR_GREEN}$BASE_DIR${COLOR_RESET}"
INFO "A compressed archive is available at  : ${COLOR_GREEN}$(ls "$BASE_DIR"/all-logs*.tar.gz 2>/dev/null | head -n1)${COLOR_RESET}"
INFO "Thank you for using Ultra-Logger!"
exit 0
## --------------- Read settings from configuration file
##* INI parser (simple): supports [section] and key=value lines
declare -A config
current_section=""
while IFS= read -r line || [[ -n "$line" ]]; do
    ## Strip comments (##...) while respecting no escaping rules for simplicity
    case "$line" in
        \##*) continue;;
    esac
    ## Remove inline comments
    line=${line%%##*}
    ## Trim leading whitespace
    while [[ "$line" == " "* || "$line" == $'\t'* ]]; do line=${line##?}; done
    ## Trim trailing whitespace
    while [[ "$line" == *" " || "$line" == *$'\t' ]]; do line=${line%?}; done

    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        current_section=${BASH_REMATCH[1]}
    elif [[ "$line" =~ ^([a-zA-Z0-9_]+)=(.*) ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        ## Trim whitespace around value
        ## leading
        while [[ "$value" == " "* || "$value" == $'\t'* ]]; do value=${value##?}; done
        ## trailing
        while [[ "$value" == *" " || "$value" == *$'\t' ]]; do value=${value%?}; done
        config["$key"]="$value"
    fi
done < "$config_file"

## Main settings
##* Derived directories use SESSION_ID for isolation
SESSION_ID="$(date +%Y%m%d-%H%M%S)"
BASE_DIR="${BASE_DIR:-$HOME/ultra-logs/$SESSION_ID}"
LOG_DIR="$BASE_DIR/logs"
FILES_DIR="$BASE_DIR/files"
mkdir -p "$LOG_DIR" "$FILES_DIR"

## Read settings from config array with defaults
##? Each reads from parsed INI or falls back to sensible default
REPO_URL="${config[REPO_URL]:-}"
TARGET="${config[TARGET]:-run-target.sh}"
EDIT_BEFORE_RUN="${config[EDIT_BEFORE_RUN]:-0}"
AUTO_STOP_AFTER="${config[AUTO_STOP_AFTER]:-0}"

## Capabilities
ENABLE_TTY_CAPTURE="${config[ENABLE_TTY_CAPTURE]:-1}"
TTY_RECORDER="${config[TTY_RECORDER]:-script}"
ENABLE_INOTIFY="${config[ENABLE_INOTIFY]:-1}"
INOTIFY_PATHS="${config[INOTIFY_PATHS]:-$HOME $PREFIX}"
ENABLE_SNAPSHOTS="${config[ENABLE_SNAPSHOTS]:-1}"
SNAPSHOT_INTERVAL="${config[SNAPSHOT_INTERVAL]:-30}"
ENABLE_STRACE="${config[ENABLE_STRACE]:-1}"
ENABLE_LTRACE="${config[ENABLE_LTRACE]:-0}"
ENABLE_NET_SNAPSHOT="${config[ENABLE_NET_SNAPSHOT]:-1}"

## Shizuku/rish
##? Android service logging options
ENABLE_SHIZUKU="${config[ENABLE_SHIZUKU]:-1}"
SHIZUKU_EXTRA_DUMPS="${config[SHIZUKU_EXTRA_DUMPS]:-1}"

## Advanced settings
##? Verbosity and log rotation size
LOG_LEVEL_CFG="${config[LOG_LEVEL]:-INFO}"
LOG_ROTATE_SIZE_MB="${config[LOG_ROTATE_SIZE_MB]:-50}"

## Root features
##? Require root/tsu/su; disabled gracefully when unavailable
ENABLE_ROOT_FEATURES="${config[ENABLE_ROOT_FEATURES]:-0}"
ENABLE_DMESG="${config[ENABLE_DMESG]:-0}"
ENABLE_AUDIT="${config[ENABLE_AUDIT]:-0}"
ENABLE_BPF="${config[ENABLE_BPF]:-0}"
BPF_EXECSNOOP="${config[BPF_EXECSNOOP]:-0}"
BPF_OPENSNOOP="${config[BPF_OPENSNOOP]:-0}"
ENABLE_TCPDUMP="${config[ENABLE_TCPDUMP]:-0}"
TCPDUMP_IFACE="${config[TCPDUMP_IFACE]:-}"
TCPDUMP_FILTER="${config[TCPDUMP_FILTER]:-}"

## --------------- Logger levels
## Define log levels and their order
log_levels=(TRACE DEBUG INFO WARN ERROR FATAL)
log_level_threshold=0
## Find log level threshold based on LOG_LEVEL_CFG
for i in "${!log_levels[@]}"; do
    if [[ "${log_levels[i]}" == "$LOG_LEVEL_CFG" ]]; then
        log_level_threshold=$i
        break
    fi
done

## Logging function
log() {
    local lvl="$1"; shift
    local -i current_lvl=0
    ## Find current log level
    for i in "${!log_levels[@]}"; do
        [[ "${log_levels[i]}" == "$lvl" ]] && current_lvl=$i && break
    done
    ## If current log level is greater than or equal to threshold, print message
    if [[ $current_lvl -ge $log_level_threshold ]]; then
        printf "[%(%F %T)T][%s] %s\n" -1 "$lvl" "$*" | tee -a "$LOG_DIR/bash.log"
    fi
}
## Helper functions for different log levels
TRACE() { log TRACE "$@"; }
DEBUG() { log DEBUG "$@"; }
INFO() { log INFO "$@"; }
WARN() { log WARN "$@"; }
ERROR() { log ERROR "$@"; }
FATAL() { log FATAL "$@"; exit 1; }

INFO "=== Ultra-Logger (Termux + Shizuku) ==="
INFO "Session ID: $SESSION_ID"
INFO "Logs directory: $LOG_DIR"
INFO "Files directory: $FILES_DIR"

## --------------- Ensure config.ini exists and open for review/edit
config_file="config.ini"
if [[ ! -f "$config_file" ]]; then
    echo "INFO: 'config.ini' not found. Creating a default configuration file."
    cat > "$config_file" <<'EOF'
[Main]
! Purpose: Core target selection and session controls

##* URL to download and execute (optional). If empty, no download occurs.
REPO_URL=https://raw.githubusercontent.com/sabamdarif/termux-desktop/main/setup-termux-desktop

##* Destination filename to save as (or your own local script to run).
##  If REPO_URL is set, this name is used for the downloaded file.
TARGET=setup-termux-desktop.sh

##? Open an editor before running the target (1=yes, 0=no).
EDIT_BEFORE_RUN=0

##? Auto-stop after N seconds (0 disables auto-stop).
AUTO_STOP_AFTER=120


[TTY]
##! Terminal capture and recorder selection

##* Master switch: enable TTY capture (1=yes, 0=no).
ENABLE_TTY_CAPTURE=0

##* Recorder to use when TTY capture is enabled.
##  Valid: script | asciinema | ttyrec | 0 (off)
TTY_RECORDER=0


[Monitoring]
! Filesystem and system monitoring controls

##* Monitor file system changes with inotifywait (1=yes, 0=no).
ENABLE_INOTIFY=1

##? Space-separated paths to watch (quote paths containing spaces).
INOTIFY_PATHS=$HOME/ultra_logs $PREFIX

##* Take periodic system snapshots (CPU, RAM, Disk, Network) (1/0).
ENABLE_SNAPSHOTS=1

##? Interval in seconds between snapshots.
SNAPSHOT_INTERVAL=30


[Tracing]
##^ System and library call tracing

##? Enable strace on target (1/0).
ENABLE_STRACE=0

##? Enable ltrace on target (1/0). // Requires ltrace to be installed
ENABLE_LTRACE=0


[Android/Shizuku]
##^ Android-specific logging via Shizuku/rish (if available)

##* Enable Shizuku/rish features (1/0).
ENABLE_SHIZUKU=1

##? Extra periodic dumpsys (activity, meminfo, netstats) (1/0).
SHIZUKU_EXTRA_DUMPS=1


[Logging]
##^ Logger verbosity and rotation

##* Log level: TRACE | DEBUG | INFO | WARN | ERROR | FATAL
LOG_LEVEL=TRACE

##? Max size (MB) before rotation for large logs (logcat, snapshots).
LOG_ROTATE_SIZE_MB=50


[RootFeatures]
##! Root-only features (require tsu/su or running as root)

##* Master switch for root features section (1/0).
ENABLE_ROOT_FEATURES=0

##? Kernel logs via dmesg -wT (1/0). // May be blocked on some devices
ENABLE_DMESG=0

##? Linux audit framework logs via ausearch (1/0). // Requires audit tools
ENABLE_AUDIT=0

##? eBPF/BCC tools (1/0). // Requires kernel support and bcc tools
ENABLE_BPF=0
BPF_EXECSNOOP=0
BPF_OPENSNOOP=0

##? Packet capture via tcpdump (1/0). // Requires root and tcpdump
ENABLE_TCPDUMP=0

##? Optional: network interface for tcpdump (e.g., wlan0). Empty = auto.
TCPDUMP_IFACE=

##? Optional: tcpdump filter expression (quoted). Empty = none.
TCPDUMP_FILTER=

EOF
    echo "INFO: Default config.ini created in the current directory. Opening editor..."
    ${EDITOR:-nano} "$config_file" || true
else
    INFO "Opening existing config.ini for review. Close the editor to continue."
    ${EDITOR:-nano} "$config_file" || true
fi

## ================= Permission Manager =================
AUTO_APPROVE=0
CURRENT_GROUP=""

begin_group() {
    CURRENT_GROUP="$1"
    AUTO_APPROVE=0
    INFO "New group '${CURRENT_GROUP}' started. Any previous auto-approval is reset."
}

ask_permission() {
    local msg="$1"
    if [[ "$AUTO_APPROVE" -eq 1 ]]; then
        return 0
    fi
    while true; do
        printf "\n>>> %s\n" "$msg"
        printf "Proceed? [a=all, y=yes, n=no, c=cancel]\n"
        read -r ans
        case "$ans" in
            [aA]) AUTO_APPROVE=1; return 0 ;;
            [yY]) return 0 ;;
            [nN]) return 1 ;;
            [cC]) echo "Cancelled by user."; exit 1 ;;
            *) echo "Invalid choice. Use: a / y / n / c." ;;
        esac
    done
}

## --------------- Check for command existence in PATH or next to script
##* Utility: returns 0 if command exists, 1 otherwise
have() { command -v "$1" >/dev/null 2>&1; }

## ---------------- System detection (Debian/Arch/Gentoo/Termux/Android)
OS_FAMILY=""
DISTRO_ID=""
PKG_MGR=""
HAS_SUDO=0
IS_TERMUX=0
IS_ANDROID=0
PKG_REFRESHED=0

detect_system() {
	if [[ -n "${PREFIX:-}" && "$PREFIX" == *"/com.termux/"* ]] || command -v termux-info >/dev/null 2>&1; then
		IS_TERMUX=1
	fi
	if command -v getprop >/dev/null 2>&1; then
		IS_ANDROID=1
	fi
	OS_FAMILY="$(uname -s 2>/dev/null || echo unknown)"
	if [[ -r /etc/os-release ]]; then
		. /etc/os-release
		DISTRO_ID="${ID:-}"
	fi
	if [[ $IS_TERMUX -eq 1 ]]; then
		if command -v pkg >/dev/null 2>&1; then PKG_MGR="pkg"; else PKG_MGR="apt"; fi
	else
		if command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt";
		elif command -v pacman >/dev/null 2>&1; then PKG_MGR="pacman";
		elif command -v emerge >/dev/null 2>&1; then PKG_MGR="emerge";
		elif command -v apk >/dev/null 2>&1; then PKG_MGR="apk"; else PKG_MGR=""; fi
	fi
	if command -v sudo >/dev/null 2>&1; then HAS_SUDO=1; fi
}

detect_system

## Function to find rish: in PATH or next to script
##? Prefer PATH; fallback to sibling file; prints empty string on failure
find_rish() {
    local rish_cmd="rish"
    if have "$rish_cmd"; then
        echo "$rish_cmd"
        return 0
        elif [[ -x "$(dirname "$0")/rish" ]]; then
        echo "$(dirname "$0")/rish"
        return 0
    fi
    echo ""
    return 1
}

## Function to convert array to safe string
##* Joins arguments and escapes them with %q for safe shell reuse
array_to_quoted_string() {
    local out=""
    printf -v out '%q ' "$@"
    out=${out% }
    printf '%s' "$out"
}

## Root detection and runner helpers
##? Use tsu/su to elevate when not already root
is_root() {
    if [[ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]]; then
        return 0
    fi
    return 1
}

find_root_runner() {
    ## Prefer sudo when available (non-interactive if possible), then tsu/su
    if [[ $HAS_SUDO -eq 1 ]]; then
        printf '%s\n' "sudo" "-n"
        return 0
    fi
    if have tsu; then
        printf '%s\n' "tsu" "-c"
        return 0
    elif have su; then
        printf '%s\n' "su" "-c"
        return 0
    fi
    printf '%s\n' "" ""
    return 1
}

run_as_root() {
    ##* Usage: run_as_root <command> [arg1 ...]
    ##? Elevates and runs while preserving argument boundaries using printf %q
    if is_root; then
        "$@"
        return $?
    fi
    local runner cmd_flag
    read -r runner cmd_flag < <(find_root_runner)
    if [[ -n "$runner" ]]; then
        local cmd_str=""
        printf -v cmd_str '%q ' "$@"
        cmd_str=${cmd_str% }
        "$runner" "$cmd_flag" "$cmd_str"
        return $?
    fi
    return 127
}

_resolve_pkg_name() {
    local want="$1"
    case "$PKG_MGR" in
        apt)
            case "$want" in
                ss) echo "iproute2";; inotifywait) echo "inotify-tools";; top) echo "procps";; netstat) echo "net-tools";;
                asciinema) echo "asciinema";; ttyrec) echo "ttyrec";; *) echo "$want";; esac ;;
        pacman)
            case "$want" in
                ss) echo "iproute2";; inotifywait) echo "inotify-tools";; top) echo "procps-ng";; netstat) echo "net-tools";;
                asciinema) echo "asciinema";; ttyrec) echo "ttyrec";; *) echo "$want";; esac ;;
        emerge)
            case "$want" in
                ss) echo "sys-apps/iproute2";; inotifywait) echo "sys-fs/inotify-tools";; top) echo "sys-process/procps";; netstat) echo "net-tools";;
                asciinema) echo "app-misc/asciinema";; ttyrec) echo "app-misc/ttyrec";; strace) echo "dev-util/strace";; ltrace) echo "dev-util/ltrace";; tcpdump) echo "net-analyzer/tcpdump";;
                *) echo "$want";; esac ;;
        apk)
            case "$want" in
                ss) echo "iproute2";; inotifywait) echo "inotify-tools";; top) echo "procps";; netstat) echo "net-tools";; *) echo "$want";; esac ;;
        pkg|*) echo "$want";;
    esac
}

_install_pkg_once() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)
            if [[ $PKG_REFRESHED -eq 0 ]]; then
                if [[ "$AUTO_APPROVE" -eq 1 ]] || ask_permission "Run apt-get update?"; then run_as_root apt-get update -y || true; fi
                PKG_REFRESHED=1
            fi
            run_as_root apt-get install -y "$pkg" || return 1 ;;
        pacman) run_as_root pacman -Sy --noconfirm "$pkg" || return 1 ;;
        emerge) run_as_root emerge -n "$pkg" || return 1 ;;
        apk)    run_as_root apk add --no-interactive "$pkg" || return 1 ;;
        pkg)    run_as_root pkg install "$pkg" -y || return 1 ;;
        *) return 1 ;;
    esac
    return 0
}

req_pkg() {
    local pkg_name="$1"
    local cmd_name="$2"; cmd_name="${cmd_name:-$pkg_name}"
    if have "$cmd_name"; then return 0; fi
    WARN "Dependency '$cmd_name' not found. Attempting to install..."
    local resolved; resolved="$(_resolve_pkg_name "$pkg_name")"
    if [[ -z "$PKG_MGR" ]]; then
        WARN "No supported package manager detected. Please install '$resolved' manually."
        return 1
    fi
    if [[ "$AUTO_APPROVE" -eq 1 ]] || ask_permission "Install '$resolved' using $PKG_MGR?"; then
        _install_pkg_once "$resolved" || { WARN "Failed to install '$resolved'."; return 1; }
        if have "$cmd_name"; then
            INFO "Installed '$resolved' providing '$cmd_name'."
            return 0
        else
            WARN "'$resolved' installed but '$cmd_name' still missing."
            return 1
        fi
    else
        WARN "User denied installation for '$resolved'."
        return 1
    fi
}

## --------------- Check and install required dependencies
INFO "Checking and installing dependencies..."
begin_group "deps"
req_pkg "termux-tools" "script"
req_pkg "iproute2" "ss"
req_pkg "net-tools" "netstat"
req_pkg "procps" "top"
req_pkg "curl" "curl"

## Optional features
if [[ "$ENABLE_INOTIFY" == "1" ]]; then
    req_pkg "inotify-tools" "inotifywait"
fi

if [[ "$ENABLE_STRACE" == "1" ]]; then
    req_pkg "strace" "strace"
fi

if [[ "$ENABLE_LTRACE" == "1" ]]; then
    req_pkg "ltrace" "ltrace"
fi

## Optional TTY recorder tools
if [[ "$ENABLE_TTY_CAPTURE" == "1" ]]; then
    case "$TTY_RECORDER" in
        asciinema)
            req_pkg "asciinema" "asciinema" ;;
        ttyrec)
            req_pkg "ttyrec" "ttyrec" ;;
        0)
            INFO "TTY_RECORDER=0: TTY capture disabled by recorder selection."
            ENABLE_TTY_CAPTURE=0
            ;;
        tee|script|*)
            : ;; ## no extra deps
    esac
fi

## Root features
if [[ "$ENABLE_ROOT_FEATURES" == "1" ]]; then
    if [[ "$ENABLE_DMESG" == "1" ]]; then
        req_pkg "termux-tools" "dmesg"
    fi
    if [[ "$ENABLE_AUDIT" == "1" ]]; then
        req_pkg "audit" "ausearch" ## Assuming 'audit' is the package name
    fi
    if [[ "$ENABLE_BPF" == "1" ]]; then
        if [[ "$BPF_EXECSNOOP" == "1" ]]; then
            req_pkg "bcc" "execsnoop" ## Assuming 'bcc' is the package
        fi
        if [[ "$BPF_OPENSNOOP" == "1" ]]; then
            req_pkg "bcc" "opensnoop"
        fi
    fi
    if [[ "$ENABLE_TCPDUMP" == "1" ]]; then
        req_pkg "tcpdump" "tcpdump"
    fi
fi

## --------------- Initial snapshot (Diagnostics)
##* Captures uname/uptime/packages/env; helps reproduce user environments
{
    echo "== uname =="; uname -a || true
    echo "== uptime =="; uptime || true
    echo "== termux-info =="; termux-info || true
    echo "== env =="; env || true
    echo "== packages =="; pkg list-installed || true
    echo "== SELinux status =="; getenforce || true
    echo "== PREFIX/bin content =="; ls -al "$PREFIX/bin" || true
    RISH_PATH=$(find_rish)
    if [[ "$ENABLE_SHIZUKU" == "1" && -n "$RISH_PATH" ]]; then
        echo "== Android services (via Shizuku/rish) =="; "$RISH_PATH" dumpsys activity services | head -n 200 || true
    fi
} > "$LOG_DIR/diagnostics.txt" 2>&1
INFO "Initial diagnostics saved to $LOG_DIR/diagnostics.txt."

## --------------- Input validation
if [[ -n "${REPO_URL:-}" ]]; then
    if [[ ! "$REPO_URL" =~ ^https?:// ]]; then
        FATAL "Invalid REPO_URL format: '$REPO_URL'. It must start with http:// or https://."
    fi
fi

## --------------- If REPO_URL is set: Download target (Group B)
if [[ -n "${REPO_URL:-}" ]]; then
    begin_group "target-download"
    if ask_permission "Download target script from $REPO_URL?"; then
        INFO "Downloading target from: $REPO_URL"
        CURL_TRACE="$LOG_DIR/curl-trace.txt"
        CURL_HDRS="$LOG_DIR/curl-headers.txt"
        
        curl -Lf --trace-ascii "$CURL_TRACE" -D "$CURL_HDRS" -o "$FILES_DIR/$TARGET" "$REPO_URL" 2>>"$LOG_DIR/bash.log" \
        || FATAL "Download failed for '$REPO_URL'."
        cp -f "$FILES_DIR/$TARGET" "./$TARGET"
        chmod +x "./$TARGET"
        INFO "Target saved to ./$TARGET and made executable."
        if [[ "$EDIT_BEFORE_RUN" == "1" ]]; then
            INFO "Opening target script for editing. Press Ctrl+X to save and exit nano."
            ${EDITOR:-nano} "./$TARGET" || true
        fi
    else
        WARN "User skipped target download."
    fi
fi

## --------------- Disable clear/tput to preserve output
##? Prevents accidental screen clears by target scripts while logging
## These scripts temporarily override the clear and tput functions in the target execution environment
## to prevent accidental clearing of console output during logging.
DISABLE_CLEAR_SH="$FILES_DIR/disable-clear.sh"
cat > "$DISABLE_CLEAR_SH" <<'EOF'
__LOG_FILE="${LOG_DIR_OVERRIDE:-/dev/null}" ## Points to bash.log
clear() { printf '[DEBUG] clear() ignored\n' >> "$__LOG_FILE"; }
tput() {
    if [[ "$1" == "reset" || "$1" == "clear" ]]; then
        printf '[DEBUG] tput %s ignored\n' "$1" >> "$__LOG_FILE";
        return 0;
    fi;
    command tput "$@";
}
export -f clear tput
EOF
ENV_SH="$FILES_DIR/env-logger.sh"
cat > "$ENV_SH" <<EOF
export LOG_DIR_OVERRIDE="$LOG_DIR/bash.log"
EOF

## --------------- inotify file system monitoring
##* Converts INOTIFY_PATHS to array to preserve spaces in paths
INOTIFY_PIDS=()
if [[ "$ENABLE_INOTIFY" == "1" ]] && req_pkg "inotify-tools" "inotifywait"; then
    begin_group "feature:inotify"
    if ask_permission "Start inotify monitoring on configured paths?"; then
    INFO "Starting inotify on paths: $INOTIFY_PATHS"
    ## Convert INOTIFY_PATHS string to array to handle paths with spaces correctly

     read -r -a INOTIFY_PATHS_ARRAY <<< "$INOTIFY_PATHS"
    ##eval "read -r -a INOTIFY_PATHS_ARRAY <<< $INOTIFY_PATHS"
    for P in "${INOTIFY_PATHS_ARRAY[@]}"; do
        if [[ -d "$P" ]]; then
            ## inotifywait runs in the background and sends output to a log file
            inotifywait -m -r -e create,delete,modify,attrib,move "$P" > "$LOG_DIR/fs.$(echo "$P" | tr '/ ' '__').log" 2>&1 &
            INOTIFY_PIDS+=($!)
            DEBUG "inotifywait for $P started with PID ${INOTIFY_PIDS[-1]}"
        else
            WARN "Inotify path '$P' is not a directory, skipping."
        fi
    done
    else
        WARN "Inotify monitoring skipped by user."
    fi
else
    WARN "inotify disabled or 'inotifywait' not found/installed. File system monitoring skipped."
fi

## --------------- Snapshot periodic resources/network/process
##* Streams snapshots into rotating files via split
SNAP_PID=""
snapshot_once(){
    {
        echo "===== $(date '+%F %T') ====="
        echo "-- top (1 iteration) --"; top -b -n 1 2>/dev/null || true
        echo "-- ps (top 200 by CPU) --"; ps -eo pid,ppid,user,stat,%cpu,%mem,etime,cmd --sort=-%cpu 2>/dev/null | head -n 200 || true
        echo "-- memory usage --"; free -h 2>/dev/null || true
        echo "-- disk usage --"; df -h 2>/dev/null || true
        if [[ "$ENABLE_NET_SNAPSHOT" == "1" ]]; then
            ## First we try ss, if not found then netstat
            if have "ss"; then
                echo "-- network sockets (ss) --"; ss -tulpn 2>/dev/null || true
                elif have "netstat"; then
                echo "-- network sockets (netstat) --"; netstat -tulpn 2>/dev/null || true
            else
                WARN "Neither 'ss' nor 'netstat' found for network snapshot."
            fi
        fi
    }
}
if [[ "$ENABLE_SNAPSHOTS" == "1" ]]; then
    begin_group "feature:snapshots"
    if ask_permission "Start periodic snapshots every ${SNAPSHOT_INTERVAL} seconds?"; then
    INFO "Starting periodic snapshots every ${SNAPSHOT_INTERVAL} seconds."
    ## Snapshots are taken periodically and their output is streamed to split
    ## split divides the files based on size (LOG_ROTATE_SIZE_MB) and appends each part to snapshots.log
    (
        while true; do
            snapshot_once
            sleep "$SNAPSHOT_INTERVAL"
        done
    ) | stdbuf -oL split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE"' - "$LOG_DIR/snapshots." 2>/dev/null &
    SNAP_PID=$!
    DEBUG "Snapshot service started with PID $SNAP_PID"
    else
        WARN "Periodic snapshots skipped by user."
    fi
else
    WARN "Periodic snapshots disabled."
fi

## --------------- Shizuku/rish: logcat + dumpsys
RISH_OK=0
RISH_CMD=$(find_rish)
if [[ "$ENABLE_SHIZUKU" == "1" && -n "$RISH_CMD" ]]; then
    begin_group "feature:shizuku"
    if ask_permission "Start Shizuku/rish logcat capture and optional dumpsys?"; then
    INFO "Shizuku/rish detected at '$RISH_CMD'. Starting logcat capture..."
    ## logcat captures logs in threadtime format from all buffers and splits them
    ( "$RISH_CMD" logcat -v threadtime -b all 2>&1 ) | stdbuf -oL split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE"' - "$LOG_DIR/logcat." 2>/dev/null &
    LOGCAT_PID=$!
    RISH_OK=1
    DEBUG "Logcat capture started with PID $LOGCAT_PID"
    
    if [[ "$SHIZUKU_EXTRA_DUMPS" == "1" ]]; then
        INFO "Starting periodic dumpsys (activity, meminfo, netstats)..."
        ## Additional dumpsys commands are run periodically
        (
            while true; do
                {
                    echo "===== $(date '+%F %T') ====="
                    echo "-- dumpsys activity processes --";  "$RISH_CMD" dumpsys activity processes 2>&1 || true
                    echo "-- dumpsys meminfo (top) --";       "$RISH_CMD" dumpsys meminfo 2>&1 | head -n 300 || true
                    echo "-- dumpsys netstats --";            "$RISH_CMD" dumpsys netstats 2>&1 | head -n 400 || true
                } >> "$LOG_DIR/dumpsys.periodic.txt"
                sleep "$SNAPSHOT_INTERVAL"
            done
        ) &
        DUMPSYS_PID=$!
        DEBUG "Dumpsys service started with PID $DUMPSYS_PID"
    fi
    else
        WARN "Shizuku/rish logging skipped by user."
    fi
else
    WARN "Shizuku disabled or 'rish' not found/installed; skipping logcat/dumpsys."
    LOGCAT_PID=""; DUMPSYS_PID=""
fi

## --------------- Root-only features: dmesg, audit, BPF (execsnoop/opensnoop), tcpdump
DMESG_PID=""; AUDIT_PID=""; BPF_EXECSNOOP_PID=""; BPF_OPENSNOOP_PID=""; TCPDUMP_PID=""
if [[ "$ENABLE_ROOT_FEATURES" == "1" ]]; then
    begin_group "feature:root"
    if ask_permission "Enable root feature set (dmesg/audit/BPF/tcpdump) now?" && ( is_root || find_root_runner >/dev/null ); then
        ## dmesg follower
        if [[ "$ENABLE_DMESG" == "1" ]] && have dmesg; then
            INFO "Starting dmesg -wT capture..."
            (
                run_as_root dmesg -wT 2>&1 |
                stdbuf -oL split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE"' - "$LOG_DIR/dmesg." 2>/dev/null
            ) &
            DMESG_PID=$!
            DEBUG "dmesg capture started with PID $DMESG_PID"
        elif [[ "$ENABLE_DMESG" == "1" ]]; then
            WARN "dmesg not found; skipping kernel log capture."
        fi

        ## Audit logs (best-effort; only if tools exist)
        if [[ "$ENABLE_AUDIT" == "1" ]]; then
            if have ausearch; then
                INFO "Starting periodic audit log capture (ausearch)..."
                (
                    while true; do
                        {
                            echo "===== $(date '+%F %T') ====="
                            run_as_root ausearch -m ALL -ts recent -i 2>&1 || true
                        } >> "$LOG_DIR/audit.periodic.txt"
                        sleep "$SNAPSHOT_INTERVAL"
                    done
                ) &
                AUDIT_PID=$!
                DEBUG "Audit capture started with PID $AUDIT_PID"
            else
                WARN "Audit tools not found (ausearch); skipping audit capture."
            fi
        fi

        ## BPF tools
        if [[ "$ENABLE_BPF" == "1" ]]; then
            if [[ "$BPF_EXECSNOOP" == "1" ]] && have execsnoop; then
                INFO "Starting BPF execsnoop..."
                run_as_root execsnoop > "$LOG_DIR/execsnoop.log" 2>&1 &
                BPF_EXECSNOOP_PID=$!
                DEBUG "execsnoop started with PID $BPF_EXECSNOOP_PID"
            elif [[ "$BPF_EXECSNOOP" == "1" ]]; then
                WARN "execsnoop not found; skipping."
            fi
            if [[ "$BPF_OPENSNOOP" == "1" ]] && have opensnoop; then
                INFO "Starting BPF opensnoop..."
                run_as_root opensnoop > "$LOG_DIR/opensnoop.log" 2>&1 &
                BPF_OPENSNOOP_PID=$!
                DEBUG "opensnoop started with PID $BPF_OPENSNOOP_PID"
            elif [[ "$BPF_OPENSNOOP" == "1" ]]; then
                WARN "opensnoop not found; skipping."
            fi
        fi

        ## tcpdump capture to rotating chunks (pcap)
        if [[ "$ENABLE_TCPDUMP" == "1" ]] && have tcpdump; then
            begin_group "feature:tcpdump"
            if ask_permission "Start tcpdump capture (pcap rotated to $LOG_DIR)?"; then
            INFO "Starting tcpdump capture..."
            TCPDUMP_CMD=(tcpdump -vv -s0 -U -w -)
            [[ -n "$TCPDUMP_IFACE" ]] && TCPDUMP_CMD+=( -i "$TCPDUMP_IFACE" )
            if [[ -n "$TCPDUMP_FILTER" ]]; then
                TCPDUMP_CMD+=( "$TCPDUMP_FILTER" )
            fi
            (
                run_as_root "${TCPDUMP_CMD[@]}" |
                split -b "${LOG_ROTATE_SIZE_MB}m" --filter='cat > "$FILE".pcap' - "$LOG_DIR/tcpdump." 2>/dev/null
            ) &
            TCPDUMP_PID=$!
            DEBUG "tcpdump started with PID $TCPDUMP_PID"
            else
                WARN "tcpdump capture skipped by user."
            fi
        elif [[ "$ENABLE_TCPDUMP" == "1" ]]; then
            WARN "tcpdump not found; skipping network packet capture."
        fi
    else
        WARN "Root not available (tsu/su not found or denied); skipping root-only features."
    fi
else
    DEBUG "Root features disabled by configuration."
fi

## --------------- Running target with TTY capture + strace/ltrace
BASH_LOG="$LOG_DIR/bash.log"
TTY_LOG="$LOG_DIR/tty.typescript"
RUN_PAYLOAD=( true ) ## Default: do nothing (if no target specified)

## Check for target file existence and how to run it
if [[ -x "./$TARGET" ]]; then
    RUN_PAYLOAD=( "./$TARGET" )
    elif [[ -n "${REPO_URL:-}" ]]; then
    RUN_PAYLOAD=( bash "./$TARGET" ) ## If we downloaded it but it's not executable, run with bash
else
    INFO "No target script specified (REPO_URL empty and ./$TARGET not found). Running 'true' as placeholder."
fi

## Construct command chain to run target
## Source helper scripts to disable clear/tput
RUN_PAYLOAD_CMD=$(array_to_quoted_string "${RUN_PAYLOAD[@]}")
CMD_CHAIN=( bash -xv -c "source '$ENV_SH' && source '$DISABLE_CLEAR_SH' && $RUN_PAYLOAD_CMD" )

## Run strace/ltrace if enabled
LAUNCH=( "${CMD_CHAIN[@]}" )
if [[ "$ENABLE_LTRACE" == "1" ]] && have ltrace; then
    LAUNCH=( ltrace -f -o "$LOG_DIR/ltrace.%p.log" -- "${LAUNCH[@]}" )
    INFO "ltrace enabled for payload."
fi
if [[ "$ENABLE_STRACE" == "1" ]] && have strace; then
    LAUNCH=( strace -ff -o "$LOG_DIR/strace.%p.log" -- "${LAUNCH[@]}" )
    INFO "strace enabled for payload."
fi

INFO "Launching payload with tracing..."
LAUNCH_CMD=$(array_to_quoted_string "${LAUNCH[@]}")
begin_group "target-exec"
if ! ask_permission "Execute TARGET script now?"; then
    WARN "User denied execution of target script. Skipping payload launch."
    WRAPPER_PID=""
elif [[ "$ENABLE_TTY_CAPTURE" == "1" ]]; then
    case "$TTY_RECORDER" in
        script)
            if have script; then
                INFO "Executing with TTY recorder 'script': $LAUNCH_CMD"
                script -q -f -c "$LAUNCH_CMD" "$TTY_LOG" &
                WRAPPER_PID=$!
                INFO "Payload wrapper (script) started with PID $WRAPPER_PID"
            else
                WARN "Requested TTY recorder 'script' not available. Running without TTY recording."
                bash -lc "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload started directly with PID $WRAPPER_PID"
            fi
            ;;
        0)
            INFO "TTY_RECORDER=0: Running without TTY recording."
            bash -lc "$LAUNCH_CMD" &
            WRAPPER_PID=$!
            INFO "Payload started directly with PID $WRAPPER_PID"
            ;;
        asciinema)
            if have asciinema; then
                INFO "Executing with TTY recorder 'asciinema': $LAUNCH_CMD"
                asciinema rec -q -c "$LAUNCH_CMD" "$LOG_DIR/tty-asciinema.cast" &
                WRAPPER_PID=$!
                INFO "Payload (asciinema) started with PID $WRAPPER_PID"
            else
                WARN "Requested TTY recorder 'asciinema' not available. Proceeding without TTY recording."
                bash -lc "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload started directly with PID $WRAPPER_PID"
            fi
            ;;
        ttyrec)
            if have ttyrec; then
                INFO "Executing with TTY recorder 'ttyrec': $LAUNCH_CMD"
                ttyrec -q "$LOG_DIR/tty.ttyrec" bash -c "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload (ttyrec) started with PID $WRAPPER_PID"
            else
                WARN "Requested TTY recorder 'ttyrec' not available. Proceeding without TTY recording."
                bash -lc "$LAUNCH_CMD" &
                WRAPPER_PID=$!
                INFO "Payload started directly with PID $WRAPPER_PID"
            fi
            ;;
        *)
            WARN "Unknown TTY_RECORDER='$TTY_RECORDER' or 'tee' selected. Running without TTY recording to preserve interactivity."
            bash -lc "$LAUNCH_CMD" &
            WRAPPER_PID=$!
            INFO "Payload started directly with PID $WRAPPER_PID"
            ;;
    esac
else
    ## Run target without TTY capture
    WARN "TTY capture disabled. Running interactively without additional recording."
    bash -lc "$LAUNCH_CMD" &
    WRAPPER_PID=$!
    INFO "Payload started directly with PID $WRAPPER_PID"
fi

## --------------- Command finish loop (interactive or automatic monitoring)
finish_time=""
if [[ "$AUTO_STOP_AFTER" -gt 0 ]]; then
    INFO "Logging will automatically stop in ${AUTO_STOP_AFTER} seconds."
    finish_time=$(( SECONDS + AUTO_STOP_AFTER ))
fi

## Setup traps to gracefully stop on signals
trap 'INFO "SIGINT received. Stopping monitors..."; break' INT
trap 'INFO "SIGTERM received. Stopping monitors..."; break' TERM
trap 'INFO "Exit detected. Stopping monitors..."' EXIT

INFO "Logging is running in background. To stop, type 'endinstall' and press Enter."
INFO "You can minimize Termux or run other commands while this is running."
while true; do
    if [[ -n "$finish_time" ]] && [[ "$SECONDS" -ge "$finish_time" ]]; then
        INFO "AUTO_STOP_AFTER limit reached. Stopping monitors..."
        break
    fi
    ## read with -t 1 times out every 1 second so we can check AUTO_STOP_AFTER
    read -r -t 1 -p "" CMD || continue ## Monitor user input in the background
    if [[ "$CMD" == "endinstall" ]]; then
        INFO "User requested to stop monitors. Stopping..."
        break
        elif [[ -n "$CMD" ]]; then
        INFO "Unknown command: '$CMD' (type 'endinstall' to finish)"
    fi
done

## --------------- Stopping background processes
## Function safe_kill for safely stopping processes
safe_kill() {
    local pid="$1"
    if [[ -z "$pid" ]]; then return 0; fi ## If PID is empty, do nothing
    
    INFO "Attempting to terminate PID $pid gracefully..."
    kill -TERM "$pid" 2>/dev/null || { DEBUG "PID $pid not found or already terminated with TERM."; return 0; }
    sleep 2 ## Give the process 2 seconds to respond to TERM
    
    if kill -0 "$pid" 2>/dev/null; then ## If process is still alive
        WARN "Process $pid did not terminate gracefully after SIGTERM. Sending SIGKILL."
        kill -KILL "$pid" 2>/dev/null || { WARN "Failed to send SIGKILL to PID $pid."; }
    else
        DEBUG "Process $pid terminated gracefully."
    fi
}

INFO "Terminating all background logging processes..."
for pid in "${INOTIFY_PIDS[@]:-}"; do safe_kill "$pid"; done
[[ -n "${SNAP_PID:-}" ]] && safe_kill "$SNAP_PID" || true
[[ "${RISH_OK}" -eq 1 && -n "${LOGCAT_PID:-}" ]] && safe_kill "$LOGCAT_PID" || true
[[ "${RISH_OK}" -eq 1 && -n "${DUMPSYS_PID:-}" ]] && safe_kill "$DUMPSYS_PID" || true
[[ -n "${DMESG_PID:-}" ]] && safe_kill "$DMESG_PID" || true
[[ -n "${AUDIT_PID:-}" ]] && safe_kill "$AUDIT_PID" || true
[[ -n "${BPF_EXECSNOOP_PID:-}" ]] && safe_kill "$BPF_EXECSNOOP_PID" || true
[[ -n "${BPF_OPENSNOOP_PID:-}" ]] && safe_kill "$BPF_OPENSNOOP_PID" || true
[[ -n "${TCPDUMP_PID:-}" ]] && safe_kill "$TCPDUMP_PID" || true
safe_kill "$WRAPPER_PID" || true

## --------------- Saving final snapshot and Checksums + Archiving
INFO "Saving final system snapshot..."
snapshot_once >> "$LOG_DIR/snapshots.log" ## Save the final snapshot

(
    cd "$BASE_DIR"
    INFO "Generating SHA256 checksums for all collected files..."
    ## Find all files and compute their SHA256 hashes
    find . -type f -print0 | xargs -0 sha256sum > "$LOG_DIR/checksums.sha256" || true
    INFO "Creating final archive of logs and files..."
    ## Compress logs and files directories into a tar.gz file
    tar -czf "$BASE_DIR/all-logs.$SESSION_ID.tar.gz" logs files
) || true

## --------------- Completion summary report with ANSI color coding
##* ANSI color codes
COLOR_RESET="\033[0m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"

total_logs=$(find "$LOG_DIR" -type f | wc -l)
total_files_collected=$(find "$FILES_DIR" -type f | wc -l)
warnings_count=$(grep -c 'WARN' "$LOG_DIR/bash.log" || true)
errors_count=$(grep -c 'ERROR' "$LOG_DIR/bash.log" || true)

INFO "================ DONE ================"
INFO "Summary Report for Session: $SESSION_ID"
INFO "  Total log files generated : $total_logs"
INFO "  Total collected files     : $total_files_collected"
INFO "  Total warnings in bash.log: ${COLOR_YELLOW}$warnings_count${COLOR_RESET}"
INFO "  Total errors in bash.log  : ${COLOR_RED}$errors_count${COLOR_RESET}"

##* Feature overview
INFO "  TTY capture                : ENABLE_TTY_CAPTURE=$ENABLE_TTY_CAPTURE, RECORDER=$TTY_RECORDER"
INFO "  Tracing                    : strace=$ENABLE_STRACE, ltrace=$ENABLE_LTRACE"
INFO "  Monitoring                 : inotify=$ENABLE_INOTIFY, snapshots=$ENABLE_SNAPSHOTS (@${SNAPSHOT_INTERVAL}s)"
INFO "  Android/Shizuku            : enabled=$ENABLE_SHIZUKU, rish_ok=$RISH_OK, extra_dumps=$SHIZUKU_EXTRA_DUMPS"
INFO "  Root features              : master=$ENABLE_ROOT_FEATURES, dmesg=$ENABLE_DMESG, audit=$ENABLE_AUDIT, bpf=$ENABLE_BPF, tcpdump=$ENABLE_TCPDUMP"
INFO "  Tcpdump opts               : iface='${TCPDUMP_IFACE:-}' filter='${TCPDUMP_FILTER:-}'"

##? Inotify paths summary (word-count; quoted paths may contain spaces)
INFO "  Inotify paths (count)      : $(printf '%s\n' $INOTIFY_PATHS | wc -w 2>/dev/null || echo 0)"

INFO "All logs and files are saved in: ${COLOR_GREEN}$BASE_DIR${COLOR_RESET}"
INFO "A compressed archive is available at  : ${COLOR_GREEN}$(ls "$BASE_DIR"/all-logs*.tar.gz 2>/dev/null | head -n1)${COLOR_RESET}"
INFO "Thank you for using Ultra-Logger!"
exit 0