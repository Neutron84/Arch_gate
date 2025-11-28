#!/usr/bin/env bash
# Helpers for safe pacman operations: lock handling, disk checks, and safe installs


# Include guard
if [[ -n "${_ARCHGATE_PACMAN_UTILS_SH_LOADED:-}" ]]; then
  return 0
fi
_ARCHGATE_PACMAN_UTILS_SH_LOADED=true

# Wait for or remove pacman lock safely
safe_handle_pacman_lock() {
    local timeout=${1:-300} # seconds to wait for other pacman processes
    local lock_file="/var/lib/pacman/db.lck"
    local waited=0
    
    # If pacman process running, wait until it finishes or timeout
    if pgrep -x pacman >/dev/null 2>&1; then
        log_debug "Waiting for existing pacman processes to finish..."
        while pgrep -x pacman >/dev/null 2>&1 && [[ $waited -lt $timeout ]]; do
            sleep 5
            waited=$((waited + 5))
        done
    fi
    
    # If lock file exists and not used by any process, consider removing stale lock
    if [[ -f "$lock_file" ]] && ! fuser "$lock_file" >/dev/null 2>&1; then
        # stat -c %Y gives modification time in epoch seconds on GNU
        if stat --version >/dev/null 2>&1; then
            local lock_age=$(( $(date +%s) - $(stat -c %Y "$lock_file") ))
        else
            # Fallback for systems without GNU stat (shouldn't happen on Arch)
            local lock_age=9999
        fi
        
        # remove stale locks older than 5 minutes
        if [[ $lock_age -gt 300 ]]; then
            print_warn "Removing stale pacman lock file"
            rm -f "$lock_file" || print_warn "Failed to remove stale lock file"
        fi
    fi
    
    # Final check: if pacman still running, return non-zero
    if pgrep -x pacman >/dev/null 2>&1; then
        print_warn "pacman processes still running after wait"
        return 1
    fi
    
    return 0
}

# Convert human readable sizes from pacman (e.g. "12.34 MiB") to KiB integer
convert_size_to_kib() {
    local size_str="$1"
    # trim
    size_str=$(echo "$size_str" | sed 's/^ *//;s/ *$//')
    
    # If empty, return 0
    if [[ -z "$size_str" ]]; then
        echo 0
        return
    fi
    
    # Split value and unit
    local val=$(echo "$size_str" | awk '{print $1}')
    local unit=$(echo "$size_str" | awk '{print $2}')
    
    # Ensure decimal point uses dot
    val=$(echo "$val" | tr ',' '.')
    
    case "$unit" in
        KiB|Ki)
            awk -v v="$val" 'BEGIN{printf "%d", v}'
        ;;
        MiB|Mi)
            awk -v v="$val" 'BEGIN{printf "%d", v*1024}'
        ;;
        GiB|Gi)
            awk -v v="$val" 'BEGIN{printf "%d", v*1024*1024}'
        ;;
        B)
            awk -v v="$val" 'BEGIN{printf "%d", v/1024}'
        ;;
        *)
            # If unit missing, assume KiB
            awk -v v="$val" 'BEGIN{printf "%d", v}'
        ;;
    esac
}

# Check basic network connectivity (DNS + gateway) - returns 0 if online
is_network_online() {
    # Try resolving a reliable name
    if command -v ping >/dev/null 2>&1; then
        if ping -c 1 -w 2 archlinux.org >/dev/null 2>&1; then
            return 0
        fi
    fi
    # fallback to curl
    if command -v curl >/dev/null 2>&1; then
        if curl -s --head --fail https://archlinux.org/ >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Install packages with disk checks, retries, and pacman lock handling
safe_package_install() {
    local packages=($@)
    local chroot_dir=""
    # If last arg is a directory path and directory exists, treat as chroot
    if [[ -n "${packages[-1]}" && -d "${packages[-1]}" ]]; then
        chroot_dir="${packages[-1]}"
        unset 'packages[-1]'
    fi
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        print_warn "No packages provided to safe_package_install"
        return 1
    fi
    
    # Calculate required download size in KiB
    local required_kib=0
    for pkg in "${packages[@]}"; do
        local dl=$(pacman -Si "$pkg" 2>/dev/null | awk -F: '/Download Size/{print $2}')
        local k=$(convert_size_to_kib "$dl")
        required_kib=$((required_kib + k))
    done
    
    # Available space where cache lives
    local cache_dir="/var/cache/pacman/pkg"
    local avail_kib=$(df -k --output=avail "$cache_dir" 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [[ -z "$avail_kib" ]]; then
        avail_kib=0
    fi
    
    if [[ $required_kib -gt $avail_kib ]]; then
        print_failed "Insufficient disk space for package installation: required ${required_kib} KiB, available ${avail_kib} KiB"
        return 2
    fi
    
    local max_retries=3
    local attempt=0
    local backoff=5
    
    while [[ $attempt -lt $max_retries ]]; do
        attempt=$((attempt + 1))
        
        safe_handle_pacman_lock 60 || print_warn "pacman lock handler reported an issue"
        
        if [[ -n "$chroot_dir" ]]; then
            print_msg "Installing packages in chroot: ${packages[*]}"
            if pacstrap -c -K "$chroot_dir" "${packages[@]}" 2>/dev/null; then
                return 0
            fi
        else
            print_msg "Installing packages: ${packages[*]}"
            
            if ! is_network_online; then
                print_warn "Network appears offline; will retry (attempt $attempt/$max_retries)"
                sleep $backoff
                backoff=$((backoff * 2))
                continue
            fi
            
            if pacman -S --noconfirm --needed "${packages[@]}"; then
                print_success "Packages installed: ${packages[*]}"
                return 0
            else
                print_warn "pacman install failed (attempt $attempt/$max_retries). Refreshing DB and retrying"
                pacman -Sy --noconfirm 2>/dev/null || true
            fi
        fi
        
        sleep $backoff
        backoff=$((backoff * 2))
    done
    
    print_failed "Failed to install packages after $max_retries attempts: ${packages[*]}"
    return 1
}

export -f safe_handle_pacman_lock convert_size_to_kib is_network_online safe_package_install
