#!/bin/bash
# =============================================================================
# ADVANCED OPTIMIZATIONS MODULE
# =============================================================================
# This module provides advanced system optimizations
# Features:
# - Bcachefs optimization
# - Smart prefetch system
# - Hardware profile management
# - Advanced write optimizer
# - Vulkan configuration


# Include guard
if [[ -n "${_ARCHGATE_OPTIMIZATIONS_SH_LOADED:-}" ]]; then
  return 0
fi
_ARCHGATE_OPTIMIZATIONS_SH_LOADED=true

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

# Setup Bcachefs optimization
setup_bcachefs_optimization() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_bcachefs_optimization: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up Bcachefs optimization..."
    
    # Create optimize-bcachefs script
    cat > "$chroot_dir/usr/local/bin/optimize-bcachefs" <<'EOF'
#!/bin/bash

# Optimize parameters for persistent partition
if command -v bcachefs &>/dev/null && [[ -b /dev/disk/by-label/ARCH_PERSIST ]]; then
    bcachefs set-option /dev/disk/by-label/ARCH_PERSIST \
        background_target=ssd \
        background_compression=zstd \
        inodes_32bit=1 \
        gc_after_writeback=1 \
        write_buffer_size=512M \
        journal_flush_delay=1000 \
        fsck_fix_errors=yes || true

    # Enable advanced cache features
    bcachefs set-option /dev/disk/by-label/ARCH_PERSIST \
        reflink=1 \
        promote_target=4096 \
        writeback_percentage=20 || true

    echo "Bcachefs optimizations applied"
else
    echo "Bcachefs not available or ARCH_PERSIST partition not found"
fi
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/optimize-bcachefs"
    
    # Create Bcachefs optimization service
    cat > "$chroot_dir/etc/systemd/system/bcachefs-optimize.service" <<'EOF'
[Unit]
Description=Bcachefs Optimizations
DefaultDependencies=no
After=local-fs.target
Before=network.target atomic-update.service
Conflicts=atomic-update.service
ConditionPathExists=/usr/local/bin/optimize-bcachefs
ConditionVirtualization=!container

[Service]
Type=oneshot
ExecStart=/usr/local/bin/optimize-bcachefs
RemainAfterExit=yes
Nice=19
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
TimeoutStartSec=5min
Restart=on-failure
RestartSec=30s

[Install]
WantedBy=sysinit.target
EOF
    
    print_success "Bcachefs optimization configured"
    return 0
}

# Setup smart prefetch system
setup_smart_prefetch() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_smart_prefetch: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up smart prefetch system..."
    
    # Create smart-prefetch script
    cat > "$chroot_dir/usr/local/bin/smart-prefetch" <<'EOF'
#!/bin/bash
PREFETCH_LOG="/var/log/prefetch.log"
PREFETCH_CACHE="/var/cache/prefetch"
APPLICATION_PROFILES="/etc/prefetch/profiles"

# Create directory structure
mkdir -p "$PREFETCH_CACHE" "$APPLICATION_PROFILES"

# Function to analyze application usage
analyze_application_usage() {
    # Collect application usage statistics
    ps aux --sort=-%cpu 2>/dev/null | head -10 | awk '{print $11}' | sort | uniq > "/tmp/top_processes" 2>/dev/null || true

    # Check logs of started services
    journalctl --since="1 hour ago" -t systemd 2>/dev/null | grep "Started.*service" | \
        awk '{print $8}' | sed 's/\.service//' > "/tmp/recent_services" 2>/dev/null || true
}

# Function to prefetch application files
prefetch_application() {
    local app_name="$1"
    local app_profile="$APPLICATION_PROFILES/${app_name}.profile"

    if [[ -f "$app_profile" ]]; then
        echo "Prefetching $app_name using profile..." >> "$PREFETCH_LOG"
        while IFS= read -r file_pattern; do
            [[ -z "$file_pattern" ]] && continue
            find /usr -type f -path "*$file_pattern*" 2>/dev/null | head -20 | \
                xargs -I {} cat "{}" > /dev/null 2>&1 &
        done < "$app_profile"
    else
        echo "General prefetch for $app_name..." >> "$PREFETCH_LOG"
        local app_bin=$(which "$app_name" 2>/dev/null)
        if [[ -n "$app_bin" ]]; then
            local app_files=$(ldd "$app_bin" 2>/dev/null | awk '{print $3}' | grep -v null)
            for lib in $app_files; do
                [[ -f "$lib" ]] && cat "$lib" > /dev/null 2>&1 &
            done
        fi
    fi
    wait
}

# Main prefetch function
run_smart_prefetch() {
    echo "$(date): Starting smart prefetch analysis" >> "$PREFETCH_LOG"

    analyze_application_usage

    while read -r process; do
        [[ -z "$process" ]] && continue
        local app_name=$(basename "$process")
        prefetch_application "$app_name" &
    done < "/tmp/top_processes"

    while read -r service; do
        [[ -z "$service" ]] && continue
        prefetch_application "$service" &
    done < "/tmp/recent_services"

    wait
    echo "$(date): Smart prefetch completed" >> "$PREFETCH_LOG"
}

run_smart_prefetch
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/smart-prefetch"
    
    # Create prefetch profiles directory and sample profiles
    mkdir -p "$chroot_dir/etc/prefetch/profiles"
    
    # Firefox profile
    cat > "$chroot_dir/etc/prefetch/profiles/firefox.profile" <<'EOF'
/bin/firefox
/lib/firefox
/usr/lib/firefox
/usr/share/firefox
EOF
    
    # Hyprland profile
    cat > "$chroot_dir/etc/prefetch/profiles/hyprland.profile" <<'EOF'
/bin/hyprland
/usr/lib/hyprland
/usr/share/hyprland
EOF
    
    # VSCode profile
    cat > "$chroot_dir/etc/prefetch/profiles/code.profile" <<'EOF'
/bin/code
/usr/lib/code
/usr/share/code
EOF
    
    # Create smart prefetch service
    cat > "$chroot_dir/etc/systemd/system/smart-prefetch.service" <<'EOF'
[Unit]
Description=Smart Application Prefetch
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/smart-prefetch
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF
    
    # Create smart prefetch timer
    cat > "$chroot_dir/etc/systemd/system/smart-prefetch.timer" <<'EOF'
[Unit]
Description=Run smart prefetch every 6 hours
Requires=smart-prefetch.service

[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF
    
    print_success "Smart prefetch system configured"
    return 0
}

# Setup hardware profile manager
setup_hardware_profile_manager() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_hardware_profile_manager: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up hardware profile manager..."
    
    # Create hardware profile manager script
    cat > "$chroot_dir/usr/local/bin/hardware-profile-manager" <<'EOF'
#!/bin/bash
PROFILE_DIR="/etc/hardware-profiles"
CURRENT_PROFILE_FILE="/var/lib/hardware-profile/current"

detect_hardware() {
    # Detect GPU
    if lspci | grep -qi "nvidia"; then
        GPU="nvidia"
    elif lspci | grep -qi "amd.*radeon"; then
        GPU="amd"
    elif lspci | grep -qi "intel.*graphics"; then
        GPU="intel"
    else
        GPU="generic"
    fi

    # Detect CPU
    CPU_VENDOR=$(grep "vendor_id" /proc/cpuinfo | head -1 | awk '{print $3}')
    if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        CPU="intel"
    elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
        CPU="amd"
    else
        CPU="generic"
    fi

    # Detect RAM
    RAM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
    if [[ $RAM_MB -lt 2048 ]]; then
        RAM_PROFILE="low"
    elif [[ $RAM_MB -lt 8192 ]]; then
        RAM_PROFILE="medium"
    else
        RAM_PROFILE="high"
    fi
}

apply_profile() {
    local profile="$1"
    local profile_file="$PROFILE_DIR/$profile.conf"

    if [[ ! -f "$profile_file" ]]; then
        echo "Profile file not found: $profile_file"
        return 1
    fi

    echo "Applying hardware profile: $profile"
    source "$profile_file"

    # Save current profile
    mkdir -p "$(dirname "$CURRENT_PROFILE_FILE")"
    echo "$profile" > "$CURRENT_PROFILE_FILE"
}

detect_hardware

# Create profile directory
mkdir -p "$PROFILE_DIR"

# Apply profile based on detected hardware
PROFILE="${GPU}-${CPU}-${RAM_PROFILE}"
if [[ -f "$PROFILE_DIR/$PROFILE.conf" ]]; then
    apply_profile "$PROFILE"
else
    echo "Using generic profile"
    apply_profile "generic" || echo "Generic profile not found"
fi
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/hardware-profile-manager"
    
    # Create profile directory and sample profiles
    mkdir -p "$chroot_dir/etc/hardware-profiles"
    
    # NVIDIA profile
    cat > "$chroot_dir/etc/hardware-profiles/nvidia-intel-high.conf" <<'EOF'
export VULKAN_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH=/persistent/.nv-shader-cache
EOF
    
    # AMD profile
    cat > "$chroot_dir/etc/hardware-profiles/amd-amd-high.conf" <<'EOF'
export VULKAN_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
export AMD_VULKAN_ICD=RADV
EOF
    
    # Intel profile
    cat > "$chroot_dir/etc/hardware-profiles/intel-intel-high.conf" <<'EOF'
export VULKAN_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json
export MESA_LOADER_DRIVER_OVERRIDE=iris
EOF
    
    # Generic profile
    cat > "$chroot_dir/etc/hardware-profiles/generic.conf" <<'EOF'
# Generic hardware profile
export MESA_LOADER_DRIVER_OVERRIDE=auto
EOF
    
    # Create hardware profile service
    cat > "$chroot_dir/etc/systemd/system/hardware-profile.service" <<'EOF'
[Unit]
Description=Hardware Profile Manager
After=local-fs.target
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hardware-profile-manager
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Hardware profile manager configured"
    return 0
}

# Setup advanced write optimizer
setup_advanced_write_optimizer() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_advanced_write_optimizer: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up advanced write optimizer..."
    
    # Create advanced write optimizer script
    cat > "$chroot_dir/usr/local/bin/advanced-write-optimizer" <<'EOF'
#!/bin/bash

# Optimize I/O scheduler for USB devices
for device in /sys/block/*/queue/scheduler; do
    if [[ -w "$device" ]]; then
        echo "mq-deadline" > "$device" 2>/dev/null || echo "none" > "$device" 2>/dev/null || true
    fi
done

# Optimize read-ahead for USB devices
for device in /sys/block/*/queue/read_ahead_kb; do
    if [[ -w "$device" ]]; then
        echo "512" > "$device" 2>/dev/null || true
    fi
done

# Optimize write cache settings
for device in /sys/block/*/queue/write_cache; do
    if [[ -w "$device" ]]; then
        echo "write back" > "$device" 2>/dev/null || true
    fi
done

echo "Write optimization applied"
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/advanced-write-optimizer"
    
    # Create I/O optimizer service
    cat > "$chroot_dir/etc/systemd/system/io-optimizer.service" <<'EOF'
[Unit]
Description=Advanced Write Optimizer
After=local-fs.target
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/advanced-write-optimizer
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Advanced write optimizer configured"
    return 0
}

# Setup all optimizations
setup_all_optimizations() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_all_optimizations: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up all advanced optimizations..."
    
    setup_bcachefs_optimization "$chroot_dir"
    setup_smart_prefetch "$chroot_dir"
    setup_hardware_profile_manager "$chroot_dir"
    setup_advanced_write_optimizer "$chroot_dir"
    
    print_success "All advanced optimizations configured"
    return 0
}

