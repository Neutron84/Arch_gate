#!/bin/bash
# =============================================================================
# PACKAGE MANAGEMENT SYSTEM - Supports pacman, pacstrap, and AUR
# =============================================================================

# Source required modules
[[ -f "${0%/*}/colors.sh" ]] && source "${0%/*}/colors.sh"
[[ -f "${0%/*}/logging.sh" ]] && source "${0%/*}/logging.sh"
[[ -f "${0%/*}/utils.sh" ]] && source "${0%/*}/utils.sh"

# Global variables for package management
PACKAGE_MANAGER="pacman"
AUR_HELPER="yay"
ENABLE_AUR=false

# Cache cleaning configuration
AUTO_CLEAN_CACHE="${AUTO_CLEAN_CACHE:-true}"
CACHE_CLEAN_STRATEGY="${CACHE_CLEAN_STRATEGY:-immediate}"
CACHE_BATCH_THRESHOLD="${CACHE_BATCH_THRESHOLD:-5}"
CACHE_BATCH_COUNTER=0

function detect_aur_helper() {
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        ENABLE_AUR=true
        log_debug "AUR helper detected: yay"
    elif command -v paru &>/dev/null; then
        AUR_HELPER="paru"
        ENABLE_AUR=true
        log_debug "AUR helper detected: paru"
    else
        ENABLE_AUR=false
        log_debug "No AUR helper found"
    fi
}

function install_aur_helper() {
    local helper_choice="${1:-yay}"
    
    if [[ "$ENABLE_AUR" == "true" ]]; then
        print_success "AUR helper already installed: $AUR_HELPER"
        return 0
    fi

    print_msg "Installing AUR helper: $helper_choice"
    
    case "$helper_choice" in
        "yay")
            package_install_pacman "base-devel git" || return 1
            cd /tmp || return 1
            git clone https://aur.archlinux.org/yay.git || return 1
            cd yay || return 1
            if ! command -v makepkg &>/dev/null; then
                print_msg "makepkg not found; installing base-devel"
                package_install_pacman "base-devel" || return 1
            fi
            makepkg -si --noconfirm || return 1
            cd ..
            rm -rf yay
            AUR_HELPER="yay"
            ;;
        "paru")
            package_install_pacman "base-devel git" || return 1
            cd /tmp || return 1
            git clone https://aur.archlinux.org/paru.git || return 1
            cd paru || return 1
            if ! command -v makepkg &>/dev/null; then
                print_msg "makepkg not found; installing base-devel"
                package_install_pacman "base-devel" || return 1
            fi
            makepkg -si --noconfirm || return 1
            cd ..
            rm -rf paru
            AUR_HELPER="paru"
            ;;
        *)
            print_failed "Unknown AUR helper: $helper_choice"
            return 1
            ;;
    esac

    if command -v "$AUR_HELPER" &>/dev/null; then
        ENABLE_AUR=true
        print_success "AUR helper installed successfully: $AUR_HELPER"
        return 0
    else
        print_failed "Failed to install AUR helper: $helper_choice"
        return 1
    fi
}

function package_install_and_check() {
    local packs_list="$*"
    local install_success=true
    
    log_debug "Starting package installation for: $packs_list"
    
    IFS=' ' read -r -a packs_array <<< "$packs_list"
    
    for package_name in "${packs_array[@]}"; do
        if [[ -z "$package_name" ]]; then
            continue
        fi
        
        if [[ "$package_name" == aur/* ]]; then
            local aur_package="${package_name#aur/}"
            if [[ "$ENABLE_AUR" == "true" ]]; then
                package_install_aur "$aur_package" || install_success=false
            else
                print_warn "AUR not enabled, skipping: $aur_package"
                install_success=false
            fi
        else
            if command -v pacman &>/dev/null; then
                package_install_pacman "$package_name" || install_success=false
            elif command -v pacstrap &>/dev/null; then
                package_install_pacstrap "$package_name" || install_success=false
            else
                print_failed "No package manager available"
                return 1
            fi
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

function package_install_pacman() {
    local package_name="$1"
    
    if [[ "$package_name" == *"*"* ]]; then
        log_debug "Processing wildcard pattern: $package_name"
        local packages
        packages=$(pacman -Ssq 2>/dev/null | grep -E "^${package_name//\*/.*}$")
        
        if [[ -z "$packages" ]]; then
            print_warn "No packages found matching pattern: $package_name"
            return 1
        fi
        
        log_debug "Matched packages: $packages"
        
        for package in $packages; do
            if ! package_install_pacman_single "$package"; then
                return 1
            fi
        done
        return 0
    else
        package_install_pacman_single "$package_name"
    fi
}

function package_install_pacman_single() {
    local package_name="$1"
    local retry_count=0
    local max_retries=5
    local install_success=false
    
    if pacman -Qi "$package_name" &>/dev/null; then
        print_success "Package already installed: ${C}$package_name"
        return 0
    fi
    
    while [[ "$retry_count" -lt "$max_retries" && "$install_success" == false ]]; do
        retry_count=$((retry_count + 1))
        
        safe_handle_pacman_lock 60 || print_warn "pacman lock handling returned non-zero"
        
        print_msg "Installing package (pacman): ${C}$package_name"
        
        if pacman -S --noconfirm --needed "$package_name" 2>/dev/null; then
            if pacman -Qi "$package_name" &>/dev/null; then
                print_success "Successfully installed package: ${C}$package_name"
                install_success=true
                handle_post_install_cache_clean "$package_name"
            else
                print_warn "Package installed but verification failed: ${C}$package_name"
            fi
        else
            print_warn "Failed to install package: ${C}$package_name. Retrying... ($retry_count/$max_retries)"
            pacman -Sy --noconfirm 2>/dev/null
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        print_failed "Failed to install package after $max_retries attempts: ${C}$package_name"
        return 1
    fi
}

function package_install_pacstrap() {
    local package_name="$1"
    local chroot_dir="${2:-/mnt}"
    local retry_count=0
    local max_retries=5
    local install_success=false
    
    print_msg "Installing package (pacstrap): ${C}$package_name"
    
    while [[ "$retry_count" -lt "$max_retries" && "$install_success" == false ]]; do
        retry_count=$((retry_count + 1))
        
        if pacstrap -c -K "$chroot_dir" "$package_name" 2>/dev/null; then
            if arch-chroot "$chroot_dir" pacman -Qi "$package_name" &>/dev/null; then
                print_success "Successfully installed package in chroot: ${C}$package_name"
                install_success=true
            else
                print_warn "Package installed in chroot but verification failed: ${C}$package_name"
            fi
        else
            print_warn "Failed to install package in chroot: ${C}$package_name. Retrying... ($retry_count/$max_retries)"
            arch-chroot "$chroot_dir" pacman -Sy --noconfirm 2>/dev/null
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        print_failed "Failed to install package in chroot after $max_retries attempts: ${C}$package_name"
        return 1
    fi
}

function package_install_aur() {
    local package_name="$1"
    local retry_count=0
    local max_retries=3
    local install_success=false
    
    if [[ "$ENABLE_AUR" != "true" ]]; then
        print_warn "AUR not enabled, skipping: $package_name"
        return 1
    fi
    
    print_msg "Installing AUR package: ${C}$package_name"
    
    while [[ "$retry_count" -lt "$max_retries" && "$install_success" == false ]]; do
        retry_count=$((retry_count + 1))
        
        if [[ "$AUR_HELPER" == "yay" ]]; then
            if yay -S --noconfirm --needed "$package_name" 2>/dev/null; then
                if pacman -Qi "$package_name" &>/dev/null; then
                    print_success "Successfully installed AUR package: ${C}$package_name"
                    install_success=true
                fi
            fi
        elif [[ "$AUR_HELPER" == "paru" ]]; then
            if paru -S --noconfirm --needed "$package_name" 2>/dev/null; then
                if pacman -Qi "$package_name" &>/dev/null; then
                    print_success "Successfully installed AUR package: ${C}$package_name"
                    install_success=true
                fi
            fi
        fi
        
        if [[ "$install_success" != "true" ]]; then
            print_warn "Failed to install AUR package: ${C}$package_name. Retrying... ($retry_count/$max_retries)"
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        print_failed "Failed to install AUR package after $max_retries attempts: ${C}$package_name"
        return 1
    fi
}

function clean_package_cache() {
    if [[ "$AUTO_CLEAN_CACHE" != "true" ]]; then
        return 0
    fi
    
    print_msg "Cleaning package cache..."
    
    if command -v pacman &>/dev/null; then
        pacman -Sc --noconfirm 2>/dev/null && print_success "Package cache cleaned" || print_warn "Cache clean had issues"
    fi
}

function smart_cache_clean() {
    local package_name="$1"
    local package_size=0
    
    if [[ "$AUTO_CLEAN_CACHE" != "true" ]]; then
        return 0
    fi
    
    if [[ "$CACHE_CLEAN_STRATEGY" != "smart" ]]; then
        return 0
    fi
    
    if command -v pacman &>/dev/null; then
        package_size=$(pacman -Si "$package_name" 2>/dev/null | grep "Installed Size" | awk '{print $4$5}')
        # If package is > 100MB, clean cache
        if [[ "$package_size" =~ [0-9]+[MG] ]]; then
            local num=$(echo "$package_size" | sed 's/[^0-9]//g')
            if [[ "$package_size" == *"G"* ]] || [[ "$num" -gt 100 ]]; then
                clean_package_cache
            fi
        fi
    fi
}

function handle_post_install_cache_clean() {
    local package_name="$1"
    
    if [[ "$AUTO_CLEAN_CACHE" != "true" ]]; then
        return 0
    fi
    
    case "$CACHE_CLEAN_STRATEGY" in
        immediate)
            clean_package_cache
            ;;
        batch)
            CACHE_BATCH_COUNTER=$((CACHE_BATCH_COUNTER + 1))
            if [[ $CACHE_BATCH_COUNTER -ge $CACHE_BATCH_THRESHOLD ]]; then
                clean_package_cache
                CACHE_BATCH_COUNTER=0
            fi
            ;;
        smart)
            smart_cache_clean "$package_name"
            ;;
    esac
}

function package_check_and_remove() {
    local packs_list="$*"
    log_debug "Starting package removal for: $packs_list"
    
    IFS=' ' read -r -a packs_array <<< "$packs_list"
    
    for package_name in "${packs_array[@]}"; do
        if [[ -z "$package_name" ]]; then
            continue
        fi
        
        if command -v pacman &>/dev/null; then
            package_remove_pacman "$package_name"
        fi
    done
}

function package_remove_pacman() {
    local package_name="$1"
    
    if ! pacman -Qi "$package_name" &>/dev/null; then
        print_success "Package not installed: ${C}$package_name"
        return 0
    fi
    
    print_msg "Removing package: ${C}$package_name"
    safe_handle_pacman_lock 60
    
    if pacman -Rns --noconfirm "$package_name" 2>/dev/null; then
        print_success "Successfully removed package: ${C}$package_name"
        return 0
    else
        print_failed "Failed to remove package: ${C}$package_name"
        return 1
    fi
}

function package_update_all() {
    print_msg "Updating package repositories and system packages..."
    safe_handle_pacman_lock 60
    
    if pacman -Sy --noconfirm 2>/dev/null; then
        if pacman -Su --noconfirm 2>/dev/null; then
            print_success "System packages updated"
            return 0
        else
            print_warn "Repository updated but system upgrade had issues"
            return 1
        fi
    else
        print_failed "Failed to update repositories"
        return 1
    fi
}

function check_dependencies() {
    local deps=(
        pacman git makepkg wget curl parted lsblk blkid mkfs.ext4 mkfs.fat
        dkms modprobe systemctl udevadm tput
    )

    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            print_warn "Dependency missing: $cmd"
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_debug "All dependencies present"
        return 0
    fi

    if command -v pacman &>/dev/null; then
        print_msg "Attempting to install missing dependencies via pacman: ${missing[*]}"
        for pkg in "${missing[@]}"; do
            if ! package_install_and_check "$pkg"; then
                print_warn "Auto-install failed for $pkg; attempting direct pacman"
                local sudo_cmd=""
                if command -v sudo &>/dev/null; then
                    sudo_cmd="sudo"
                fi

                if ! $sudo_cmd pacman -S --noconfirm --needed "$pkg" &>/dev/null; then
                    print_failed "Failed to install dependency: $pkg"
                else
                    print_success "Installed dependency: $pkg"
                fi
            else
                print_success "Installed dependency: $pkg"
            fi
        done
    else
        print_failed "pacman not available; cannot auto-install missing dependencies: ${missing[*]}"
        return 1
    fi

    local still_missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            still_missing+=("$cmd")
        fi
    done

    if [[ ${#still_missing[@]} -ne 0 ]]; then
        print_failed "Still missing required commands: ${still_missing[*]}"
        return 1
    fi

    return 0
}

