#!/bin/bash
set -euo pipefail

# Arch Gate bootstrap launcher
# - Verifies root, curl, git
# - Clones repo into /tmp/arch-gate
# - Runs Stage 1 installer

REPO_URL="https://github.com/Neutron84/Arch_gate.git"
WORKDIR_BASE="/tmp"
WORKDIR="$WORKDIR_BASE/Arch-gate"

# Lock file to prevent multiple instances
LOCKFILE="/var/lock/archgate.lock"
LOCKFILE_ALT="/tmp/archgate.lock"

# Function to acquire lock
acquire_lock() {
    # Try /var/lock first (standard location), fallback to /tmp
    local lockfile="$LOCKFILE"
    if [[ ! -w "/var/lock" ]] 2>/dev/null; then
        lockfile="$LOCKFILE_ALT"
    fi
    
    # Check if lockfile exists and process is still running
    if [[ -f "$lockfile" ]]; then
        local pid
        pid=$(cat "$lockfile" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            fail "Another instance of Arch Gate is already running (PID: $pid)"
            fail "If you're sure no other instance is running, remove: $lockfile"
            exit 1
        else
            # Stale lockfile, remove it
            rm -f "$lockfile" || true
        fi
    fi
    
    # Create lockfile with current PID
    echo $$ > "$lockfile" || {
        fail "Failed to create lockfile: $lockfile"
        exit 1
    }
    
    # Export lockfile path for cleanup
    export LOCKFILE_PATH="$lockfile"
}

prepare_environment_hack() {
    info "Applying Live Environment Hacks (ZRAM + COW Resize)..."

    # 1. Load ZRAM for compression efficiency
    if modprobe zram >/dev/null 2>&1; then
        # Create a 8GB ZRAM device (doesn't use RAM until needed)
        echo 8G > /sys/block/zram0/disksize
        mkswap /dev/zram0 >/dev/null
        swapon /dev/zram0 -p 100
        success "ZRAM enabled (8GB swap)"
    else
        warn "Could not load ZRAM module"
    fi

    # 2. Resize COW space dynamically
    # Get 75% of Total RAM size to differeniate betwen low/high RAM systems
    # Or just force a static 4G/8G if you know the hardware
    if mount -o remount,size=6G /run/archiso/cowspace; then
         success "COW space resized to 6GB"
    else
         warn "Failed to resize COW space"
    fi
}

# Unified cleanup function for all signals
cleanup() {
    local signal="${1:-EXIT}"
    local exit_code=${2:-$?}
    
    # Prevent multiple cleanup calls
    if [[ "${CLEANUP_DONE:-}" == "true" ]]; then
        return
    fi
    export CLEANUP_DONE=true
    
    echo -e "\n[INFO] Cleaning up..." >/dev/tty
    
    # Remove lockfile
    if [[ -n "${LOCKFILE_PATH:-}" ]] && [[ -f "${LOCKFILE_PATH}" ]]; then
        rm -f "${LOCKFILE_PATH}" || true
    fi
    
    # Clean up workdir
    if [[ -d "$WORKDIR" ]]; then
        rm -rf "$WORKDIR" || true
    fi
    
    # Set appropriate exit code for signals
    if [[ "$signal" == "INT" || "$signal" == "TERM" ]]; then
        echo "[INFO] Installation cancelled by user" >/dev/tty
        exit_code=130
    fi
    
    exit $exit_code
}

# Set up unified signal handlers
# Use a single trap that handles all signals properly
trap 'cleanup INT 130' INT
trap 'cleanup TERM 143' TERM
trap 'cleanup EXIT' EXIT

set -o monitor

info()  { echo "[INFO]  $*" >/dev/tty; }
success(){ echo "[OK]    $*" >/dev/tty; }
warn()  { echo "[WARN]  $*" >/dev/tty; }
fail()  { echo "[ERROR] $*" >/dev/tty; }

require_root() {
	if [[ $EUID -ne 0 ]]; then
		fail "This script must be run as root. Try: sudo bash gate.sh"
		exit 1
	fi
}

check_prereqs() {
	local missing=()
	command -v curl >/dev/null 2>&1 || missing+=(curl)
	command -v git  >/dev/null 2>&1 || missing+=(git)
    
	if ((${#missing[@]})); then
		info "Missing prerequisites: ${missing[*]}. Attempting to install..."
		
		if command -v pacman >/dev/null 2>&1; then
			info "Detected pacman. Installing..."
			pacman -Sy --needed --noconfirm "${missing[@]}"
		elif command -v apt-get >/dev/null 2>&1; then
			info "Detected apt-get. Installing..."
			apt-get update && apt-get install -y "${missing[@]}"
		elif command -v dnf >/dev/null 2>&1; then
			info "Detected dnf. Installing..."
			dnf install -y "${missing[@]}"
		else
			fail "Could not find a supported package manager (pacman, apt-get, dnf)."
			warn "Please install the following prerequisites manually: ${missing[*]}"
			exit 1
		fi

		# Re-check to ensure they were actually installed
		local still_missing=()
		command -v curl >/dev/null 2>&1 || still_missing+=(curl)
		command -v git  >/dev/null 2>&1 || still_missing+=(git)
		if ((${#still_missing[@]})); then
			fail "Installation failed for: ${still_missing[*]}. Please install them manually."
			exit 1
		else
			success "Prerequisites installed."
		fi
	fi
}

prepare_workdir() {
	mkdir -p "$WORKDIR_BASE"
	if [[ -d "$WORKDIR" ]]; then
		info "Removing previous workdir: $WORKDIR"
		rm -rf "$WORKDIR" || {
			fail "Failed to remove previous workdir"
			exit 1
		}
	fi
}

clone_repo() {
	info "Cloning Arch Gate into $WORKDIR ..."
	if ! git clone --depth 1 "$REPO_URL" "$WORKDIR" 2>&1; then
		fail "Failed to clone repository from $REPO_URL"
		fail "Please check your internet connection and try again"
		exit 1
	fi
	success "Repository cloned"
}

run_stage1() {
	local stage1="$WORKDIR/stages/stage1.sh"
	if [[ ! -x "$stage1" ]]; then
		if [[ -f "$stage1" ]]; then
			chmod +x "$stage1" || {
				fail "Failed to make stage1.sh executable"
				exit 1
			}
		else
			fail "stage1.sh not found at $stage1"
			exit 1
		fi
	fi
	info "Starting Stage 1 installer..."
	# Run without exec to preserve parent traps and allow cleanup
	"$stage1"
	local stage1_exit_code=$?
	if [[ $stage1_exit_code -ne 0 ]]; then
		fail "Stage 1 installer exited with code: $stage1_exit_code"
		exit $stage1_exit_code
	fi
}

main() {
	require_root
	acquire_lock
	prepare_environment_hack
	check_prereqs
	prepare_workdir
	clone_repo
	run_stage1
	success "Stage 1 finished (or handed off). You can safely remove $WORKDIR afterwards."
}

main "$@"
