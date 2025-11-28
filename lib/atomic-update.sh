#!/bin/bash
# =============================================================================
# ATOMIC UPDATE SYSTEM MODULE
# =============================================================================
# This module provides atomic update system with transaction support
# Features:
# - Atomic update manager with transaction support
# - Rollback capability
# - Squashfs integrity checking
# - Staging environment for updates
# - Atomic snapshot and recovery tools

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"
[[ -f "$_LIB_DIR/overlay.sh" ]] && source "$_LIB_DIR/overlay.sh"

# Setup atomic update system
setup_atomic_update() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_atomic_update: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up atomic update system..."
    
    # Create directory structure
    mkdir -p "$chroot_dir/var/lib/system-update"{/staging,/backup,/transactions}
    mkdir -p "$chroot_dir/etc/system-update/profile"
    
    # Create atomic update manager script
    cat > "$chroot_dir/usr/local/bin/atomic-update-manager" <<'EOF'
#!/bin/bash
set -euo pipefail

# Paths
STAGING_ROOT="/persistent/update_staging"
BACKUP_DIR="/persistent/system_backup"
TRANSACTION_DIR="/var/lib/system-update/transactions"
LOG_FILE="/var/log/atomic-updates.log"
ESP_MOUNT="/boot"
TRANSACTION_ID=$(date +%Y%m%d-%H%M%S)-${RANDOM}

# Logging functions
log() {
    echo "$(date): $1" >> "$LOG_FILE"
    logger -t atomic-update "$1"
}

# Error handling function
error_exit() {
    log "ERROR: $1 - Transaction $TRANSACTION_ID failed"
    rollback_transaction
    exit 1
}

# Verify squashfs integrity
verify_squashfs_integrity() {
    local file="$1"
    log "Verifying squashfs integrity: $file"
    if ! unsquashfs -n "$file" >/dev/null 2>&1; then
        error_exit "Squashfs integrity check failed: $file"
    fi
    log "Squashfs integrity check passed: $file"
}

# Start transaction function
begin_transaction() {
    log "Starting transaction $TRANSACTION_ID"
    mkdir -p "$TRANSACTION_DIR/$TRANSACTION_ID"
    echo "started" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
}

# Transaction commit function
commit_transaction() {
    log "Committing transaction $TRANSACTION_ID"

    # Force sync before commit
    sync
    if [[ -x /usr/local/bin/enforced-sync ]]; then
        /usr/local/bin/enforced-sync
    fi

    # Mark transaction as committed
    echo "committed" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
    echo "$(date)" > "$TRANSACTION_DIR/$TRANSACTION_ID/commit_time"

    log "Transaction $TRANSACTION_ID successfully committed"
}

# Rollback transaction function
rollback_transaction() {
    log "Rolling back transaction $TRANSACTION_ID"
    local rollback_success=true
    local OLD_SQUASHFS="/persistent/arch/root.squashfs"
    local OLD_SQUASHFS_BACKUP="${OLD_SQUASHFS}.old"

    # Rollback root filesystem
    log "Rolling back root filesystem..."
    if [[ -f "$OLD_SQUASHFS_BACKUP" ]]; then
        rm -f "$OLD_SQUASHFS"
        mv "$OLD_SQUASHFS_BACKUP" "$OLD_SQUASHFS"
        log "Successfully rolled back $OLD_SQUASHFS"
    else
        log "ERROR: Cannot rollback rootfs. Backup $OLD_SQUASHFS_BACKUP not found!"
        rollback_success=false
    fi

    # Restore previous kernel files
    log "Rolling back kernel files..."
    if [[ -f "${ESP_MOUNT}/arch/vmlinuz-linux.old" ]] && [[ -f "${ESP_MOUNT}/arch/initramfs-linux.img.old" ]]; then
        rm -f "${ESP_MOUNT}/arch/vmlinuz-linux"
        rm -f "${ESP_MOUNT}/arch/initramfs-linux.img"

        mv "${ESP_MOUNT}/arch/vmlinuz-linux.old" "${ESP_MOUNT}/arch/vmlinuz-linux"
        mv "${ESP_MOUNT}/arch/initramfs-linux.img.old" "${ESP_MOUNT}/arch/initramfs-linux.img"

        # Copy to persistent partition
        cp "${ESP_MOUNT}/arch/vmlinuz-linux" "/persistent/arch/" 2>/dev/null || true
        cp "${ESP_MOUNT}/arch/initramfs-linux.img" "/persistent/arch/" 2>/dev/null || true

        log "Successfully rolled back kernel files"
    else
        log "ERROR: Backup kernel files not found in ESP. Kernel rollback failed."
        rollback_success=false
    fi

    # Remove staging files
    rm -rf "$STAGING_ROOT"

    if [[ "$rollback_success" == "true" ]]; then
        echo "rolledback" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
        log "Transaction $TRANSACTION_ID rolled back successfully"
    else
        echo "rollback_failed" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
        log "CRITICAL: Transaction $TRANSACTION_ID rollback FAILED. System may be unstable."
    fi

    # Force sync after rollback
    sync
    if [[ -x /usr/local/bin/enforced-sync ]]; then
        /usr/local/bin/enforced-sync
    fi
}

# Update packages in chroot environment
update_packages() {
    local CHROOT_DIR="$1"
    local LOG_FILE="$2"

    log "Updating packages in target root: $CHROOT_DIR"

    # Use pacman with --root to operate directly on the target root
    if ! pacman --root "$CHROOT_DIR" -Syu --noconfirm >> "$LOG_FILE" 2>&1; then
        error_exit "pacman update failed for root: $CHROOT_DIR"
    fi

    # Bind mount minimal pseudo-filesystems for mkinitcpio
    local MOUNTS_MADE=()
    for m in dev proc sys run; do
        if ! mountpoint -q "$CHROOT_DIR/$m"; then
            mkdir -p "$CHROOT_DIR/$m"
            mount --bind "/$m" "$CHROOT_DIR/$m" || {
                log "Warning: failed to bind mount /$m into $CHROOT_DIR (continuing)"
                continue
            }
            MOUNTS_MADE+=("$CHROOT_DIR/$m")
        fi
    done

    # Run mkinitcpio inside the target root
    if ! arch-chroot "$CHROOT_DIR" /usr/bin/mkinitcpio -P >> "$LOG_FILE" 2>&1; then
        # Cleanup mounts before failing
        for mp in "${MOUNTS_MADE[@]}"; do
            umount -l "$mp" 2>/dev/null || true
        done
        error_exit "mkinitcpio failed in target root: $CHROOT_DIR"
    fi

    # Cleanup bind mounts
    for mp in "${MOUNTS_MADE[@]}"; do
        umount -l "$mp" 2>/dev/null || true
    done

    log "Package update and initramfs generation completed for $CHROOT_DIR"
}

# Update system with squashfs support
update_system() {
    # Main paths for system files
    mkdir -p "/persistent/arch"
    local NEW_SQUASHFS="/persistent/arch/root.squashfs.new"
    local OLD_SQUASHFS="/persistent/arch/root.squashfs"
    local OLD_SQUASHFS_BACKUP="${BACKUP_DIR}/root.squashfs.$(date +%Y%m%d-%H%M%S)"
    ESP_MOUNT="/boot"
    mkdir -p "${ESP_MOUNT}/arch"

    begin_transaction

    log "Starting system update process"

    # Create staging environment
    rm -rf "$STAGING_ROOT"
    mkdir -p "$STAGING_ROOT"

    # Copy current system to staging environment
    log "Copying current system to staging environment"
    if [[ -d /squashfs ]]; then
        cp -a /squashfs/. "$STAGING_ROOT/"
    else
        log "WARNING: /squashfs not found, using root filesystem"
        # Fallback: copy from actual root
        rsync -a --exclude={/dev,/proc,/sys,/run,/tmp,/var/cache,/var/tmp} / "$STAGING_ROOT/" 2>/dev/null || true
    fi

    # Update in staging environment
    update_packages "$STAGING_ROOT" "$LOG_FILE"

    # Clean package caches inside the staging root
    log "Cleaning package caches inside staging root: $STAGING_ROOT"
    pacman --root "$STAGING_ROOT" -Scc --noconfirm >/dev/null 2>&1 || true
    rm -rf "$STAGING_ROOT/var/cache/pacman/pkg/*" 2>/dev/null || true
    log "Staging cache cleaned before creating squashfs"

    # Create new squashfs image
    log "Creating new squashfs image"
    mkdir -p "$(dirname "$NEW_SQUASHFS")"

    # Try EROFS first, fallback to Squashfs
    local use_erofs=false
    if command -v mkfs.erofs &>/dev/null && modprobe erofs &>/dev/null; then
        use_erofs=true
        log "Using erofs with LZ4HC compression"
        mkfs.erofs -zlz4hc,12 --uid-offset=0 --gid-offset=0 \
            --mount-point=/ --exclude-path="/tmp/*" \
            "$NEW_SQUASHFS" "$STAGING_ROOT" || {
            log "EROFS creation failed, falling back to Squashfs"
            use_erofs=false
        }
    fi

    if [[ "$use_erofs" == "false" ]]; then
        log "Using squashfs with ZSTD compression"
        if ! mksquashfs "$STAGING_ROOT" "$NEW_SQUASHFS" \
            -comp zstd -Xcompression-level 15 -noappend -processors "$(nproc)"; then
            error_exit "Failed to create new squashfs image"
        fi
    fi

    # Verify integrity of new squashfs file
    if [[ "$use_erofs" == "false" ]]; then
        verify_squashfs_integrity "$NEW_SQUASHFS"
    fi

    # Backup old file
    mkdir -p "$BACKUP_DIR"
    cp "$OLD_SQUASHFS" "$OLD_SQUASHFS_BACKUP"

    # Verify backup integrity
    if [[ "$use_erofs" == "false" ]]; then
        verify_squashfs_integrity "$OLD_SQUASHFS_BACKUP"
    fi

    # Replace files keeping old versions
    mv "$OLD_SQUASHFS" "${OLD_SQUASHFS}.old"
    mv "$NEW_SQUASHFS" "$OLD_SQUASHFS"

    # Clean old files from ESP
    rm -f "${ESP_MOUNT}/arch/"*.old

    # Backup current kernel and initramfs in ESP
    for file in vmlinuz-linux initramfs-linux.img; do
        if [[ -f "${ESP_MOUNT}/arch/$file" ]]; then
            mv "${ESP_MOUNT}/arch/$file" "${ESP_MOUNT}/arch/$file.old"
        fi
    done

    # Copy new kernel and initramfs to ESP
    if [[ ! -f "${STAGING_ROOT}/boot/vmlinuz-linux" ]]; then
        error_exit "Kernel file not found in staging area: ${STAGING_ROOT}/boot/vmlinuz-linux"
    fi
    if [[ ! -f "${STAGING_ROOT}/boot/initramfs-linux.img" ]]; then
        error_exit "Initramfs file not found in staging area: ${STAGING_ROOT}/boot/initramfs-linux.img"
    fi

    cp "${STAGING_ROOT}/boot/vmlinuz-linux" "${ESP_MOUNT}/arch/"
    cp "${STAGING_ROOT}/boot/initramfs-linux.img" "${ESP_MOUNT}/arch/"

    # Copy kernel and initramfs to persistent partition
    cp "${STAGING_ROOT}/boot/vmlinuz-linux" "/persistent/arch/"
    cp "${STAGING_ROOT}/boot/initramfs-linux.img" "/persistent/arch/"

    # Force sync to ensure changes are written
    sync
    if [[ -x /usr/local/bin/enforced-sync ]]; then
        /usr/local/bin/enforced-sync
    fi

    # Cleanup
    rm -rf "$STAGING_ROOT"
    sync

    commit_transaction
    log "System update completed successfully. Reboot recommended."
}

# Management of arguments
case "${1:-}" in
    update-system)
        update_system
        ;;
    rollback)
        rollback_transaction
        ;;
    status)
        echo "Current transaction: $TRANSACTION_ID"
        find "$TRANSACTION_DIR" -name "status" -exec cat {} \;
        ;;
    *)
        echo "Usage: $0 {update-system|rollback|status}"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/atomic-update-manager"
    
    # Create atomic update service
    cat > "$chroot_dir/etc/systemd/system/atomic-update.service" <<'EOF'
[Unit]
Description=Atomic System Update Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/atomic-update-manager update-system
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Create atomic update timer
    cat > "$chroot_dir/etc/systemd/system/atomic-update.timer" <<'EOF'
[Unit]
Description=Weekly atomic system update
Requires=atomic-update.service

[Timer]
OnCalendar=Mon 03:00:00
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
EOF
    
    # Create atomic snapshot script
    cat > "$chroot_dir/usr/local/bin/atomic-snapshot" <<'EOF'
#!/bin/bash
set -euo pipefail

SNAPSHOT_BASE="/persistent/snapshots"
DATE=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="atomic-snapshot-$DATE"
SNAPSHOT_DIR="$SNAPSHOT_BASE/$SNAPSHOT_NAME"
MAX_SNAPSHOTS=5
LOG_FILE="/var/log/atomic-snapshots.log"

log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Snapshot rotation function
rotate_snapshots() {
    local count=$(find "$SNAPSHOT_BASE" -name "atomic-snapshot-*.tar.gz" 2>/dev/null | wc -l)
    log "Current snapshot count: $count"

    if [[ "$count" -gt "$MAX_SNAPSHOTS" ]]; then
        log "Rotating snapshots (keeping last $MAX_SNAPSHOTS)"
        local excess=$((count - MAX_SNAPSHOTS))

        # Remove oldest snapshots
        find "$SNAPSHOT_BASE" -name "atomic-snapshot-*.tar.gz" | \
            sort | \
            head -n "$excess" | \
            while read -r old_snapshot; do
                log "Removing old snapshot: $(basename "$old_snapshot")"
                rm -f "$old_snapshot"
            done

        log "Rotation complete. Removed $excess old snapshot(s)"
    else
        log "No rotation needed (current count: $count, max: $MAX_SNAPSHOTS)"
    fi
}

create_atomic_snapshot() {
    log "Creating atomic snapshot: $SNAPSHOT_NAME"

    # Stop critical services for snapshot consistency
    systemctl stop io-health-monitor.service 2>/dev/null || true
    systemctl stop power-failure-detector.service 2>/dev/null || true

    # Force sync
    sync
    if [[ -x /usr/local/bin/enforced-sync ]]; then
        /usr/local/bin/enforced-sync
    fi

    # Create snapshot directory
    mkdir -p "$SNAPSHOT_DIR"

    # Copy critical system files
    cp -a /etc "$SNAPSHOT_DIR/"
    cp -a /var/lib/pacman "$SNAPSHOT_DIR/" 2>/dev/null || true
    cp -a /boot "$SNAPSHOT_DIR/" 2>/dev/null || true

    # Package status
    pacman -Q > "$SNAPSHOT_DIR/installed-packages.list"

    # Transaction information
    cp -a /var/lib/system-update/transactions "$SNAPSHOT_DIR/" 2>/dev/null || true

    # Restart services
    systemctl start io-health-monitor.service 2>/dev/null || true
    systemctl start power-failure-detector.service 2>/dev/null || true

    # Compress snapshot
    tar -czf "$SNAPSHOT_DIR.tar.gz" -C "$SNAPSHOT_BASE" "$SNAPSHOT_NAME"
    rm -rf "$SNAPSHOT_DIR"

    log "Atomic snapshot created: $SNAPSHOT_DIR.tar.gz"

    # Rotate snapshots after creating new one
    rotate_snapshots
}

# Show snapshot information
show_snapshots_info() {
    echo "Snapshot Information:"
    echo "===================="
    echo "Maximum snapshots kept: $MAX_SNAPSHOTS"
    echo "Snapshot location: $SNAPSHOT_BASE"
    echo
    echo "Current snapshots:"
    if [[ -d "$SNAPSHOT_BASE" ]]; then
        find "$SNAPSHOT_BASE" -name "atomic-snapshot-*.tar.gz" -type f -printf "%T@ %p\n" | \
            sort -rn | \
            cut -d' ' -f2- | \
            while read -r snapshot; do
                local size=$(du -h "$snapshot" | cut -f1)
                local date=$(date -r "$snapshot" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || stat -f "%Sm" "$snapshot" 2>/dev/null || echo "unknown")
                echo "- $(basename "$snapshot")"
                echo "  Size: $size"
                echo "  Date: $date"
            done
    else
        echo "No snapshots found"
    fi
}

case "${1:-}" in
    pre-update)
        create_atomic_snapshot
        ;;
    info)
        show_snapshots_info
        ;;
    rotate)
        rotate_snapshots
        ;;
    set-max)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 set-max <number>"
            exit 1
        fi
        if ! [[ "${2}" =~ ^[1-9][0-9]*$ ]]; then
            echo "Error: Please provide a positive number"
            exit 1
        fi
        MAX_SNAPSHOTS="${2}"
        echo "MAX_SNAPSHOTS=${MAX_SNAPSHOTS}" > "${SNAPSHOT_BASE}/.config"
        log "Maximum snapshots count updated to: $MAX_SNAPSHOTS"
        rotate_snapshots
        ;;
    *)
        echo "Usage: $0 {pre-update|info|rotate|set-max <number>}"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/atomic-snapshot"
    
    # Create atomic recovery script
    cat > "$chroot_dir/usr/local/bin/atomic-recovery" <<'EOF'
#!/bin/bash
set -euo pipefail

SNAPSHOT_BASE="/persistent/snapshots"
LOG_FILE="/var/log/atomic-recovery.log"

log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

list_snapshots() {
    echo "Available snapshots:"
    echo "==================="
    if [[ -d "$SNAPSHOT_BASE" ]]; then
        local count=0
        find "$SNAPSHOT_BASE" -name "atomic-snapshot-*.tar.gz" -type f | \
            sort -r | \
            while read -r snapshot; do
                count=$((count + 1))
                local size=$(du -h "$snapshot" | cut -f1)
                local date=$(date -r "$snapshot" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || stat -f "%Sm" "$snapshot" 2>/dev/null || echo "unknown")
                echo "$count. $(basename "$snapshot")"
                echo "   Size: $size"
                echo "   Date: $date"
            done
        if [[ $count -eq 0 ]]; then
            echo "No snapshots found"
        fi
    else
        echo "No snapshots found"
    fi
}

recover_from_snapshot() {
    local snapshot_file="$1"

    if [[ -z "$snapshot_file" ]]; then
        echo "Error: Snapshot file not specified"
        echo "Usage: $0 recover <snapshot-file>"
        exit 1
    fi

    if [[ ! -f "$snapshot_file" ]]; then
        echo "Error: Snapshot file not found: $snapshot_file"
        exit 1
    fi

    log "Starting recovery from snapshot: $snapshot_file"

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    log "Extracting snapshot to: $temp_dir"

    # Extract snapshot
    tar -xzf "$snapshot_file" -C "$temp_dir"

    # Find snapshot directory
    local snapshot_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "atomic-snapshot-*" | head -1)

    if [[ -z "$snapshot_dir" ]]; then
        echo "Error: Could not find snapshot directory in archive"
        rm -rf "$temp_dir"
        exit 1
    fi

    log "Recovering system files from snapshot..."

    # Restore /etc
    if [[ -d "$snapshot_dir/etc" ]]; then
        cp -a "$snapshot_dir/etc/"* /etc/
        log "Restored /etc"
    fi

    # Restore package database
    if [[ -d "$snapshot_dir/var/lib/pacman" ]]; then
        cp -a "$snapshot_dir/var/lib/pacman/"* /var/lib/pacman/ 2>/dev/null || true
        log "Restored package database"
    fi

    # Restore boot files
    if [[ -d "$snapshot_dir/boot" ]]; then
        cp -a "$snapshot_dir/boot/"* /boot/ 2>/dev/null || true
        log "Restored boot files"
    fi

    # Cleanup
    rm -rf "$temp_dir"

    log "Recovery completed successfully"
    echo "Recovery completed. Please review changes and reboot if necessary."
}

case "${1:-}" in
    list)
        list_snapshots
        ;;
    recover)
        recover_from_snapshot "${2:-}"
        ;;
    *)
        echo "Usage: $0 {list|recover <snapshot-file>}"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/atomic-recovery"
    
    print_success "Atomic update system configured"
    return 0
}

