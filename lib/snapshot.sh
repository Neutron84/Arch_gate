#!/bin/bash
# =============================================================================
# SNAPSHOT MANAGEMENT MODULE
# =============================================================================
# Features:
# - Snapper configuration for Btrfs
# - Hook integration (snap-pac)
# - Subvolume handling for snapshots


# Include guard
if [[ -n "${_ARCHGATE_SNAPSHOT_SH_LOADED:-}" ]]; then
  return 0
fi
_ARCHGATE_SNAPSHOT_SH_LOADED=true

# Setup Snapper for Btrfs
setup_snapper() {
    local mount_point="${1:-/}"  # Default to root if not specified
    
    # Only proceed if filesystem is Btrfs
    if [[ "${FILESYSTEM_TYPE:-}" != "btrfs" ]]; then
        return 0
    fi

    print_msg "Configuring Snapper for Btrfs..."

    # 1. Install required packages
    if ! pacman -Qi snapper &>/dev/null; then
        print_msg "Installing snapper and snap-pac..."
        package_install_pacman "snapper snap-pac" || {
            print_warn "Failed to install snapper packages"
            return 1
        }
    fi

    # 2. Initialize Snapper config for root
    # We need to handle the tricky part where snapper creates a subvolume that conflicts with ours
    
    # Unmount .snapshots if it was mounted by fstab
    if mountpoint -q "/.snapshots"; then
        umount "/.snapshots"
    fi
    
    # Remove existing directory/subvolume if empty or created by previous runs
    if [[ -d "/.snapshots" ]]; then
        rm -rf "/.snapshots"
    fi

    # Create config (Snapper creates a new subvolume at /.snapshots)
    print_msg "Creating Snapper config for root..."
    snapper -c root create-config / 2>/dev/null || print_warn "Snapper config might already exist"

    # 3. Fix the layout for rollback support
    # Snapper creates a subvolume at /.snapshots, but we want to use our @snapshots subvolume
    
    # Delete the subvolume snapper just created
    if btrfs subvolume list / | grep -q ".snapshots"; then
        btrfs subvolume delete /.snapshots 2>/dev/null || true
    fi
    
    # Re-create the directory
    mkdir -p /.snapshots
    
    # Remount our dedicated subvolume (read from fstab)
    print_msg "Mounting @snapshots subvolume..."
    mount -a 2>/dev/null || mount /.snapshots 2>/dev/null
    
    # Verify mount
    if ! mountpoint -q "/.snapshots"; then
        # Fallback manual mount if fstab reload failed (unlikely but safe)
        local device_uuid
        device_uuid=$(findmnt -n -o UUID /)
        if [[ -n "$device_uuid" ]]; then
             mount -o subvol=@snapshots,compress=zstd:3,noatime "UUID=$device_uuid" /.snapshots
        fi
    fi

    # 4. Permissions & Policies
    chmod 750 /.snapshots
    
    # Configure retention policy (Optional: modify /etc/snapper/configs/root here with sed if needed)
    # Example: reducing number of kept snapshots
    sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/root
    sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root

    # 5. Enable Services
    systemctl enable snapper-timeline.timer
    systemctl enable snapper-cleanup.timer
    
    print_success "Snapper configured successfully"
}

# Future: setup_timeshift() { ... }