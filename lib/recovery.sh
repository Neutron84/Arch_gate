#!/usr/bin/env bash
# Recovery utilities for Arch_gate: create and list recovery points


# Include guard
if [[ -n "${_ARCHGATE_RECOVERY_SH_LOADED:-}" ]]; then
  return 0
fi
_ARCHGATE_RECOVERY_SH_LOADED=true

_RECOVERY_DIR="/var/lib/archgate/recovery"

mkdir -p "${_RECOVERY_DIR}" 2>/dev/null || true

create_recovery_point() {
    local point_name="$1"
    if [[ -z "$point_name" ]]; then
        print_warn "Usage: create_recovery_point <name>"
        return 1
    fi
    
    local timestamp
    timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
    local base="${_RECOVERY_DIR}/${point_name}_${timestamp}"
    mkdir -p "${base}" || { print_failed "Cannot create recovery dir: ${base}"; return 1; }
    
    # Save lists into files
    pacman -Q > "${base}/packages.list" 2>/dev/null || true
    systemctl list-units --state=running > "${base}/services.list" 2>/dev/null || true
    mount > "${base}/mounts.list" 2>/dev/null || true
    df -h > "${base}/df.list" 2>/dev/null || true
    uname -a > "${base}/uname.txt" 2>/dev/null || true
    
    # Snapshot key config files if readable
    for f in /etc/pacman.conf /etc/fstab /etc/mkinitcpio.conf; do
        if [[ -r "$f" ]]; then
            cp -a "$f" "${base}/" 2>/dev/null || true
        fi
    done
    
    print_success "Recovery point created: ${base}"
    return 0
}

list_recovery_points() {
    ls -1 "${_RECOVERY_DIR}" 2>/dev/null || true
}

export -f create_recovery_point list_recovery_points
