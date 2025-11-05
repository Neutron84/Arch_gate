#!/bin/bash
# =============================================================================
# USB HEALTH CHECK MODULE (USB Memory Specific)
# =============================================================================
# This module provides USB health monitoring for USB memory devices
# Features:
# - SMART support checking
# - hdparm information
# - Disk statistics
# - USB health monitoring service

# Source required modules
[[ -f "${0%/*}/../../../lib/colors.sh" ]] && source "${0%/*}/../../../lib/colors.sh"
[[ -f "${0%/*}/../../../lib/logging.sh" ]] && source "${0%/*}/../../../lib/logging.sh"
[[ -f "${0%/*}/../../../lib/utils.sh" ]] && source "${0%/*}/../../../lib/utils.sh"

# Setup USB health check
setup_usb_health_check() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_usb_health_check: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up USB health check..."
    
    # Create check-usb-health script
    cat > "$chroot_dir/usr/local/bin/check-usb-health" <<'EOF'
#!/bin/bash

# Function to check for the existence of a command
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Warning: $1 command not found"
        return 1
    fi
    return 0
}

# Function to check for the existence of a file or directory
check_path() {
    if [[ ! -e "$1" ]]; then
        echo "Warning: $1 not found"
        return 1
    fi
    return 0
}

# File reading check function
read_sys_file() {
    local file="$1"
    local default="$2"
    if [[ -r "$file" ]]; then
        cat "$file" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# Find the real disk path
get_disk_path() {
    local label="$1"
    local disk_path

    # Try to find by label
    if disk_path=$(readlink -f "/dev/disk/by-label/$label" 2>/dev/null); then
        echo "$disk_path"
        return 0
    fi

    # Attempt to find via UUID
    if disk_path=$(blkid -L "$label" 2>/dev/null); then
        echo "$disk_path"
        return 0
    fi

    # If not found
    echo ""
    return 1
}

# Check for SMART support
check_smart_support() {
    local disk="$1"
    if ! check_command smartctl; then
        return 1
    fi

    # Check SMART support
    if smartctl -i "$disk" 2>/dev/null | grep -q "SMART support is: Enabled"; then
        return 0
    fi
    return 1
}

# Get SMART information
get_smart_info() {
    local disk="$1"
    if ! check_command smartctl; then
        echo "smartctl not available"
        return 1
    fi

    echo "Basic device info:"
    smartctl -i "$disk" 2>/dev/null || echo "- Could not get device info"
    
    if check_smart_support "$disk"; then
        echo -e "\nSMART Status:"
        smartctl -H "$disk" 2>/dev/null || echo "- Could not get SMART health"
        
        echo -e "\nSMART Attributes:"
        smartctl -A "$disk" 2>/dev/null || echo "- Could not get SMART attributes"
    else
        echo -e "\nSMART support is not available for this device"
        echo "This is normal for many USB flash drives"
    fi
}

# Get hdparm information
get_hdparm_info() {
    local disk="$1"
    if ! check_command hdparm; then
        echo "hdparm not available"
        return 1
    fi

    echo "Basic drive info:"
    if hdparm -I "$disk" 2>/dev/null; then
        return 0
    fi
    
    echo "Trying simplified drive info..."
    if hdparm -i "$disk" 2>/dev/null; then
        return 0
    fi

    # If both methods fail, show basic information
    echo "Advanced drive information not available"
    echo "Checking basic parameters..."

    # Try to get basic information
    hdparm -g "$disk" 2>/dev/null || echo "- Could not get geometry"
    hdparm -C "$disk" 2>/dev/null || echo "- Could not get power status"
    
    return 1
}

# Get disk statistics information
get_disk_stats() {
    local disk="$1"
    local base_name=$(basename "$disk")
    local stats_file="/sys/block/$base_name/stat"
    
    if [[ -r "$stats_file" ]]; then
        local stats=$(read_sys_file "$stats_file" "0 0 0 0 0 0 0 0 0 0 0")
        echo "Write cycles: $(echo "$stats" | awk '{print $7}')"
    else
        echo "Disk statistics not available"
        return 1
    fi
}

# Find the disk
disk_path=$(get_disk_path "ARCH_ESP")
if [[ -z "$disk_path" ]]; then
    echo "Error: Could not find USB drive"
    exit 1
fi

echo "=== USB Health Check ==="
echo "Device: $disk_path"
echo
echo "=== SMART Information ==="
get_smart_info "$disk_path"
echo
echo "=== Drive Parameters ==="
get_hdparm_info "$disk_path"
echo
echo "=== Disk Statistics ==="
get_disk_stats "$disk_path"
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/check-usb-health"
    
    # Create USB health service
    cat > "$chroot_dir/etc/systemd/system/usb-health.service" <<'EOF'
[Unit]
Description=USB Health Monitoring
After=local-fs.target
Before=atomic-update.service
Conflicts=atomic-update.service
ConditionVirtualization=!container
ConditionPathExists=/usr/local/bin/check-usb-health

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-usb-health
Nice=19
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
TimeoutSec=300
Restart=on-failure
RestartSec=30s
EOF
    
    # Create USB health timer
    cat > "$chroot_dir/etc/systemd/system/usb-health.timer" <<'EOF'
[Unit]
Description=Check USB health periodically
Requires=usb-health.service
After=local-fs.target system-update.target

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
RandomizedDelaySec=300
AccuracySec=1m

[Install]
WantedBy=timers.target
EOF
    
    print_success "USB health check configured"
    return 0
}

