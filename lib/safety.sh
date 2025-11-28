#!/bin/bash
# =============================================================================
# SAFETY AND RECOVERY SYSTEMS MODULE
# =============================================================================
# This module provides advanced safety and recovery systems
# Features:
# - Enforced sync for critical writes
# - I/O health monitoring
# - Power failure detection
# - System snapshot creation
# - Performance telemetry
# - Busybox fallback mode

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

# Setup enforced sync system
setup_enforced_sync() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_enforced_sync: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up enforced sync system..."
    
    # Create enforced-sync script
    cat > "$chroot_dir/usr/local/bin/enforced-sync" <<'EOF'
#!/bin/bash
# For critical operations, enforce fsync
sync
[ -w "/sys/block/*/queue/rotational" ] && echo 0 > /sys/block/*/queue/rotational 2>/dev/null || true
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/enforced-sync"
    
    # Create periodic sync service
    cat > "$chroot_dir/etc/systemd/system/periodic-sync.service" <<'EOF'
[Unit]
Description=Periodic filesystem sync
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/enforced-sync
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Create periodic sync timer
    cat > "$chroot_dir/etc/systemd/system/periodic-sync.timer" <<'EOF'
[Unit]
Description=Periodic filesystem sync every 5 minutes
Requires=periodic-sync.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    print_success "Enforced sync system configured"
    return 0
}

# Setup I/O health monitoring
setup_io_health_monitor() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_io_health_monitor: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up I/O health monitoring..."
    
    # Create I/O health monitor script
    cat > "$chroot_dir/usr/local/bin/io-health-monitor" <<'EOF'
#!/bin/bash
MAX_IO_ERRORS=10
IO_ERROR_COUNT=0
LOG_FILE="/var/log/io-health.log"

# Function to check I/O errors using journalctl
check_io_errors() {
    local error_count=0
    local current_time=$(date +%s)
    local check_interval=300  # Check errors in the last 5 minutes

    # Use journalctl to check for I/O errors in the specified time range
    error_count=$(journalctl -k -p err -S "@$((current_time - check_interval))" 2>/dev/null | \
                 grep -iE "I/O error|buffer I/O error|error on device|read-only filesystem" | \
                 wc -l)

    # Log the error count for debugging
    echo "$(date): Detected $error_count I/O errors in last ${check_interval}s" >> "$LOG_FILE"

    if [ "$error_count" -gt "$MAX_IO_ERRORS" ]; then
        echo "$(date): ⚠️ Excessive I/O errors ($error_count) detected in last ${check_interval}s!" >> "$LOG_FILE"
        echo "$(date): Error details:" >> "$LOG_FILE"
        journalctl -k -p err -S "@$((current_time - check_interval))" 2>/dev/null | \
            grep -iE "I/O error|buffer I/O error|error on device|read-only filesystem" >> "$LOG_FILE"
        switch_to_readonly
    fi
}

# Switch to read-only mode with improved error handling and logging
switch_to_readonly() {
    echo "$(date): 🔒 Initiating read-only mode..." >> "$LOG_FILE"

    # Disable write services
    local services_to_stop=(
        "periodic-sync.timer"
        "systemd-journal-flush.service"
        "atomic-update.service"
        "system-snapshot.timer"
    )

    for service in "${services_to_stop[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            if systemctl stop "$service"; then
                echo "$(date): Stopped $service" >> "$LOG_FILE"
            else
                echo "$(date): Failed to stop $service" >> "$LOG_FILE"
            fi
        fi
    done

    # Flush buffers before read-only
    sync

    # Remount partitions as read-only with error handling
    local partitions_to_remount=(
        "/"
        "/persistent"
    )

    for mount_point in "${partitions_to_remount[@]}"; do
        if mount | grep -q " on $mount_point "; then
            if mount -o remount,ro "$mount_point" 2>/dev/null; then
                echo "$(date): Successfully remounted $mount_point as read-only" >> "$LOG_FILE"
            else
                echo "$(date): ⚠️ Failed to remount $mount_point as read-only" >> "$LOG_FILE"
            fi
        fi
    done

    # Check filesystem status
    local fsck_needed=false
    for dev in $(findmnt -n -o SOURCE /persistent 2>/dev/null); do
        if ! tune2fs -l "$dev" &>/dev/null && ! bcachefs fsck "$dev" &>/dev/null; then
            echo "$(date): ⚠️ Filesystem errors detected on $dev" >> "$LOG_FILE"
            fsck_needed=true
        fi
    done

    if [ "$fsck_needed" = true ]; then
        echo "$(date): 🔧 Filesystem check recommended after reboot" >> "$LOG_FILE"
        touch /.autorelabel
    fi

    # Notify the user
    local error_message="⚠️ System switched to read-only mode due to I/O errors!\n"
    error_message+="Please check system logs (/var/log/io-health.log) for details.\n"
    error_message+="A filesystem check will be performed on next boot."

    wall "$error_message"

    # Log the event with more details
    logger -t safety-system "Emergency read-only mode activated due to excessive I/O errors"
    logger -t safety-system "System status: $(date)"
    logger -t safety-system "Last recorded disk stats: $(cat /proc/diskstats | grep -i "sd")"
}

# Continuous monitoring loop with error management
monitoring_loop() {
    local retry_count=0
    local max_retries=3

    while true; do
        if ! check_io_errors; then
            retry_count=$((retry_count + 1))
            echo "$(date): Error in monitoring cycle. Retry $retry_count of $max_retries" >> "$LOG_FILE"

            if [ "$retry_count" -ge "$max_retries" ]; then
                echo "$(date): ⚠️ Critical: Monitoring failed after $max_retries retries" >> "$LOG_FILE"
                logger -t safety-system "Critical: I/O monitoring failed, system integrity might be compromised"
                wall "⚠️ Warning: I/O health monitoring system has failed!"
                exit 1
            fi

            sleep 10  # Wait longer for retry
        else
            retry_count=0  # Reset counter on success
            sleep 30
        fi
    done
}

# Start monitoring by registering PID
echo $$ > /var/run/io-health-monitor.pid
trap 'rm -f /var/run/io-health-monitor.pid' EXIT

# Register service start
echo "$(date): I/O health monitoring service started" >> "$LOG_FILE"
logger -t safety-system "I/O health monitoring service initialized"

monitoring_loop
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/io-health-monitor"
    
    # Create I/O health monitoring service
    cat > "$chroot_dir/etc/systemd/system/io-health-monitor.service" <<'EOF'
[Unit]
Description=I/O Health Monitoring Service
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/io-health-monitor
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "I/O health monitoring configured"
    return 0
}

# Setup power failure detection
setup_power_failure_detector() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_power_failure_detector: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up power failure detection..."
    
    # Create power failure detector script
    cat > "$chroot_dir/usr/local/bin/power-failure-detector" <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/power-events.log"
LAST_STATE="normal"

check_power_state() {
    if [ -d "/sys/class/power_supply" ]; then
        local ac_state=$(cat /sys/class/power_supply/AC/online 2>/dev/null || echo "1")
        if [ "$ac_state" = "0" ]; then
            echo "battery"
        else
            echo "ac"
        fi
    else
        echo "ac"
    fi
}

handle_power_failure() {
    echo "$(date): Power failure detected! Initiating safe shutdown..." >> "$LOG_FILE"
    logger -t power-manager "Power failure detected - emergency procedures activated"

    if [[ -x /usr/local/bin/enforced-sync ]]; then
        /usr/local/bin/enforced-sync
    fi
    mount -o remount,ro /persistent 2>/dev/null || true

    wall "⚠️  Power failure detected! System is switching to safe mode."
}

while true; do
    current_state=$(check_power_state)

    if [ "$LAST_STATE" = "ac" ] && [ "$current_state" = "battery" ]; then
        handle_power_failure
    fi

    LAST_STATE=$current_state
    sleep 5
done
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/power-failure-detector"
    
    # Create power failure detection service
    cat > "$chroot_dir/etc/systemd/system/power-failure-detector.service" <<'EOF'
[Unit]
Description=Power Failure Detection Service
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/power-failure-detector
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Power failure detection configured"
    return 0
}

# Setup system snapshot creation
setup_system_snapshot() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_system_snapshot: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up system snapshot creation..."
    
    # Create system snapshot script
    cat > "$chroot_dir/usr/local/bin/create-system-snapshot" <<'EOF'
#!/bin/bash
SNAPSHOT_DIR="/persistent/snapshots"
DATE=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="system-snapshot-$DATE"

echo "Creating system snapshot: $SNAPSHOT_NAME"

mkdir -p "$SNAPSHOT_DIR/$SNAPSHOT_NAME"

# Copy important configuration files
cp -a /etc "$SNAPSHOT_DIR/$SNAPSHOT_NAME/"
cp -a /var/lib "$SNAPSHOT_DIR/$SNAPSHOT_NAME/" 2>/dev/null || true

# Create archive of package status
pacman -Q > "$SNAPSHOT_DIR/$SNAPSHOT_NAME/installed-packages.list"

# Compress snapshot
tar -czf "$SNAPSHOT_DIR/$SNAPSHOT_NAME.tar.gz" -C "$SNAPSHOT_DIR" "$SNAPSHOT_NAME"
rm -rf "$SNAPSHOT_DIR/$SNAPSHOT_NAME"

echo "Snapshot created: $SNAPSHOT_DIR/$SNAPSHOT_NAME.tar.gz"
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/create-system-snapshot"
    
    # Create periodic snapshot service
    cat > "$chroot_dir/etc/systemd/system/system-snapshot.service" <<'EOF'
[Unit]
Description=Create system snapshot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/create-system-snapshot
User=root
EOF
    
    # Create periodic snapshot timer
    cat > "$chroot_dir/etc/systemd/system/system-snapshot.timer" <<'EOF'
[Unit]
Description=Daily system snapshot
Requires=system-snapshot.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    print_success "System snapshot creation configured"
    return 0
}

# Setup performance telemetry
setup_performance_telemetry() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_performance_telemetry: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up performance telemetry..."
    
    # Create performance telemetry script
    cat > "$chroot_dir/usr/local/bin/performance-telemetry" <<'EOF'
#!/bin/bash
TELEMETRY_DIR="/persistent/telemetry"
METRICS_FILE="$TELEMETRY_DIR/performance-metrics.csv"

mkdir -p "$TELEMETRY_DIR"

# Create header if file does not exist
if [ ! -f "$METRICS_FILE" ]; then
    echo "timestamp,io_operations,rollback_count,ram_usage,swap_usage,boot_time" > "$METRICS_FILE"
fi

collect_metrics() {
    local timestamp=$(date +%s)
    local io_ops=$(cat /sys/block/*/stat 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    local rollback_count=$(journalctl -u system-update --since="1 hour ago" 2>/dev/null | grep -c "rollback" || echo "0")
    local ram_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}' || echo "0")
    local swap_usage=$(free -m | awk 'NR==3{printf "%.2f", $3*100/$2}' || echo "0")
    local boot_time=$(systemd-analyze 2>/dev/null | awk '/Startup/ {print $3}' | tr -d 's' || echo "0")

    echo "$timestamp,$io_ops,$rollback_count,$ram_usage,$swap_usage,$boot_time" >> "$METRICS_FILE"
}

collect_metrics
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/performance-telemetry"
    
    # Create telemetry service
    cat > "$chroot_dir/etc/systemd/system/performance-telemetry.service" <<'EOF'
[Unit]
Description=Performance telemetry collection
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/performance-telemetry
User=root
EOF
    
    # Create telemetry timer
    cat > "$chroot_dir/etc/systemd/system/performance-telemetry.timer" <<'EOF'
[Unit]
Description=Collect performance metrics every hour
Requires=performance-telemetry.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    print_success "Performance telemetry configured"
    return 0
}

# Setup Busybox fallback mode
setup_busybox_fallback() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_busybox_fallback: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up Busybox fallback mode..."
    
    # Check if busybox is installed
    if ! command -v busybox &>/dev/null; then
        print_warn "Busybox not found, installing..."
        if command -v pacman &>/dev/null; then
            pacman --root "$chroot_dir" -S --noconfirm busybox || {
                print_warn "Failed to install busybox"
                return 1
            }
        fi
    fi
    
    # Create custom initramfs fallback config
    cat > "$chroot_dir/etc/mkinitcpio.conf.fallback" <<'EOF'
MODULES=(overlay squashfs)
BINARIES=(busybox)
FILES=()
HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)
COMPRESSION="zstd"
EOF
    
    print_success "Busybox fallback mode configured"
    print_msg "To create fallback initramfs, run: mkinitcpio -c /etc/mkinitcpio.conf.fallback -g /boot/initramfs-linux-fallback.img"
    return 0
}

# Setup all safety systems
setup_safety_systems() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_safety_systems: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up all safety and recovery systems..."
    
    setup_enforced_sync "$chroot_dir"
    setup_io_health_monitor "$chroot_dir"
    setup_power_failure_detector "$chroot_dir"
    setup_system_snapshot "$chroot_dir"
    setup_performance_telemetry "$chroot_dir"
    setup_busybox_fallback "$chroot_dir"
    
    print_success "All safety and recovery systems configured"
    return 0
}

