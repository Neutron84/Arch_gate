#!/bin/bash
set -euo pipefail

# Arch Gate bootstrap launcher
# - Verifies root, curl, git
# - Clones repo into /tmp/arch-gate
# - Runs Stage 1 installer

# Enable proper interrupt handling
trap cleanup_and_exit INT TERM EXIT
set -o monitor

REPO_URL="https://github.com/Neutron84/Arch_gate.git"
WORKDIR_BASE="/tmp"
WORKDIR="$WORKDIR_BASE/Arch-gate"

cleanup_and_exit() {
    local exit_code=$?
    echo -e "\n[INFO] Cleaning up..."
    if [[ -d "$WORKDIR" ]]; then
        rm -rf "$WORKDIR"
    fi
    if [[ $1 == INT || $1 == TERM ]]; then
        echo "[INFO] Installation cancelled by user"
        exit 130
    fi
    exit $exit_code
}

info()  { echo "[INFO]  $*"; }
success(){ echo "[OK]    $*"; }
warn()  { echo "[WARN]  $*"; }
fail()  { echo "[ERROR] $*" >&2; }

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
		fail "Missing prerequisites: ${missing[*]}"
		warn "Install them and retry. On Arch: pacman -Sy --needed ${missing[*]}"
		exit 1
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
	git clone --depth 1 "$REPO_URL" "$WORKDIR"
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
	exec "$stage1"  # Use exec to properly handle signals
}

main() {
	require_root
	check_prereqs
	prepare_workdir
	clone_repo
	run_stage1
	success "Stage 1 finished (or handed off). You can safely remove $WORKDIR afterwards."
}

main "$@"
