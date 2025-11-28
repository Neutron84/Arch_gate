#!/bin/bash
# =============================================================================
# OVERLAY FILESYSTEM MODULE
# =============================================================================
# This module provides overlay filesystem support with Squashfs/EROFS
# Features:
# - Overlay hook for mkinitcpio
# - Squashfs/EROFS root filesystem creation
# - /home symlink to persistent partition
# - sync-skel.sh for synchronizing skel files


# Include guard
if [[ -n "${_ARCHGATE_OVERLAY_SH_LOADED:-}" ]]; then
  return 0
fi
_ARCHGATE_OVERLAY_SH_LOADED=true

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

# Setup overlay filesystem hook for mkinitcpio
setup_overlay_hook() {
    local chroot_dir="${1:-}"
    local mount_point="${2:-/mnt}"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_overlay_hook: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up overlay filesystem hook..."
    
    # Create initcpio hook directory
    mkdir -p "$chroot_dir/etc/initcpio/hooks"
    mkdir -p "$chroot_dir/etc/initcpio/install"
    
    # Create overlay hook
    cat > "$chroot_dir/etc/initcpio/hooks/overlay" <<'HOOK'
run_hook() {
    modprobe overlay
    mount_handler() {
        # Create necessary mount points
        mkdir -p /squashfs /os_root

        # Attempt to mount the persistent partition
        local fs_type=$(blkid -s TYPE -o value /dev/disk/by-label/ARCH_PERSIST 2>/dev/null || echo "")
        if [[ -z "$fs_type" ]]; then
            echo "Failed to detect ARCH_PERSIST filesystem type!"
            return 1
        fi

        if ! mount -t "$fs_type" -o ro /dev/disk/by-label/ARCH_PERSIST /os_root; then
            echo "Failed to mount ARCH_PERSIST partition!"
            return 1
        fi

        # Check for root filesystem
        if [ ! -f "/os_root/arch/root.squashfs" ]; then
            echo "root.squashfs not found in ARCH_PERSIST partition!"
            umount /os_root
            return 1
        fi

        # Detect file system type
        rootfs_type=$(file -b /os_root/arch/root.squashfs 2>/dev/null | grep -o 'Squashfs\|EROFS' || echo "squashfs")
        echo "Detected root filesystem type: ${rootfs_type}"

        # Mount the root filesystem with the appropriate type
        case "${rootfs_type}" in
            "EROFS")
                # Probe kernel support for erofs before attempting to modprobe.
                if ! modprobe -n -q erofs; then
                    echo "EROFS filesystem module not supported by kernel. Falling back to squashfs."
                    # Fall back to squashfs handling
                    if ! modprobe squashfs; then
                        echo "Failed to load squashfs module while falling back!"
                        umount /os_root
                        return 1
                    fi
                    if ! mount -t squashfs -o ro /os_root/arch/root.squashfs /squashfs; then
                        echo "Failed to mount root.squashfs as squashfs while falling back!"
                        umount /os_root
                        return 1
                    fi
                else
                    if ! modprobe erofs; then
                        echo "Failed to load erofs module!"
                        umount /os_root
                        return 1
                    fi
                    if ! mount -t erofs -o ro /os_root/arch/root.squashfs /squashfs; then
                        echo "Failed to mount root.squashfs as erofs!"
                        umount /os_root
                        return 1
                    fi
                fi
                ;;
            *)
                if ! modprobe squashfs; then
                    echo "Failed to load squashfs module!"
                    umount /os_root
                    return 1
                fi
                if ! mount -t squashfs -o ro /os_root/arch/root.squashfs /squashfs; then
                    echo "Failed to mount root.squashfs as squashfs!"
                    umount /os_root
                    return 1
                fi
                ;;
        esac

        # Cleanup
        umount /os_root

        # Setup overlay filesystem
        mkdir -p /overlay_work
        mount -t tmpfs tmpfs /overlay_work
        mkdir -p /overlay_work/upper /overlay_work/work
        mount -t overlay overlay -o lowerdir=/squashfs,upperdir=/overlay_work/upper,workdir=/overlay_work/work /new_root

        # Mount persistent partition
        mkdir -p /new_root/persistent
        mount -o rw,noatime /dev/disk/by-label/ARCH_PERSIST /new_root/persistent

        # Link /home to persistent partition
        rm -rf /new_root/home
        ln -sf /persistent/home /new_root/home
        mkdir -p /new_root/persistent/home

        # Create sync-skel.sh script
        mkdir -p /new_root/etc/profile.d
        cat > /new_root/etc/profile.d/sync-skel.sh <<'EOL'
#!/bin/bash
if [ -d /etc/skel ] && [ -d "$HOME" ]; then
    for file in /etc/skel/.*; do
        basename=$(basename "$file")
        [ "$basename" = "." ] || [ "$basename" = ".." ] && continue
        if [ ! -e "$HOME/$basename" ]; then
            cp -a "$file" "$HOME/"
        fi
    done
    for file in /etc/skel/*; do
        basename=$(basename "$file")
        if [ ! -e "$HOME/$basename" ]; then
            cp -a "$file" "$HOME/"
        fi
    done

    chown -R $(id -u):$(id -g) "$HOME"
fi
EOL
        chmod +x /new_root/etc/profile.d/sync-skel.sh
    }
}
HOOK
    
    # Create overlay install script
    cat > "$chroot_dir/etc/initcpio/install/overlay" <<'INST'
build() { add_module overlay; add_runscript; }
INST
    
    # Update mkinitcpio.conf
    if [[ -f "$chroot_dir/etc/mkinitcpio.conf" ]]; then
        # Add modules
        if ! grep -q "^MODULES=.*overlay" "$chroot_dir/etc/mkinitcpio.conf"; then
            sed -Ei 's/^MODULES=(.*)/MODULES=(overlay squashfs erofs \1)/' "$chroot_dir/etc/mkinitcpio.conf"
        fi
        
        # Add hook
        if ! grep -q "overlay" "$chroot_dir/etc/mkinitcpio.conf"; then
            sed -Ei 's/^HOOKS=(.*filesystems.*)/HOOKS=\1 overlay/' "$chroot_dir/etc/mkinitcpio.conf"
        fi
    fi
    
    print_success "Overlay hook configured"
    return 0
}

# Create squashfs image from installed system
create_squashfs_image() {
    local source_dir="$1"
    local output_file="$2"
    local use_erofs="${3:-false}"
    
    if [[ -z "$source_dir" || -z "$output_file" ]]; then
        print_failed "create_squashfs_image: source_dir and output_file are required"
        return 1
    fi
    
    if [[ ! -d "$source_dir" ]]; then
        print_failed "Source directory does not exist: $source_dir"
        return 1
    fi
    
    print_msg "Creating root filesystem image..."
    
    # Clean package caches before creating image
    print_msg "Cleaning package caches..."
    if command -v pacman &>/dev/null; then
        pacman --root "$source_dir" -Scc --noconfirm >/dev/null 2>&1 || true
    fi
    rm -rf "$source_dir/var/cache/pacman/pkg/*" 2>/dev/null || true
    
    # Create output directory
    mkdir -p "$(dirname "$output_file")"
    
    # Create image based on type
    if [[ "$use_erofs" == "true" ]] && command -v mkfs.erofs &>/dev/null; then
        print_msg "Creating EROFS image with LZ4HC compression..."
        if modprobe erofs &>/dev/null; then
            mkfs.erofs -zlz4hc,12 --uid-offset=0 --gid-offset=0 \
            --mount-point=/ --exclude-path="/tmp/*" \
            "$output_file" "$source_dir"
            
            if [[ $? -eq 0 ]]; then
                print_success "EROFS image created: $output_file"
                return 0
            else
                print_warn "EROFS creation failed, falling back to Squashfs"
            fi
        else
            print_warn "EROFS module not available, falling back to Squashfs"
        fi
    fi
    
    # Fallback to Squashfs
    print_msg "Creating Squashfs image with ZSTD compression..."
    if command -v mksquashfs &>/dev/null; then
        mksquashfs "$source_dir" "$output_file" \
        -comp zstd -Xcompression-level 15 -noappend -processors "$(nproc)"
        
        if [[ $? -eq 0 ]]; then
            print_success "Squashfs image created: $output_file"
            return 0
        else
            print_failed "Failed to create Squashfs image"
            return 1
        fi
    else
        print_failed "mksquashfs not found"
        return 1
    fi
}

# Verify squashfs/erofs integrity
verify_rootfs_integrity() {
    local rootfs_file="$1"
    
    if [[ -z "$rootfs_file" ]]; then
        print_failed "verify_rootfs_integrity: rootfs_file is required"
        return 1
    fi
    
    if [[ ! -f "$rootfs_file" ]]; then
        print_failed "Rootfs file does not exist: $rootfs_file"
        return 1
    fi
    
    print_msg "Verifying rootfs integrity: $rootfs_file"
    
    # Detect filesystem type
    local fs_type=$(file -b "$rootfs_file" 2>/dev/null | grep -o 'Squashfs\|EROFS' || echo "")
    
    case "$fs_type" in
        "Squashfs")
            if command -v unsquashfs &>/dev/null; then
                if unsquashfs -n "$rootfs_file" >/dev/null 2>&1; then
                    print_success "Squashfs integrity check passed"
                    return 0
                else
                    print_failed "Squashfs integrity check failed"
                    return 1
                fi
            else
                print_warn "unsquashfs not found, skipping integrity check"
                return 0
            fi
        ;;
        "EROFS")
            # EROFS verification is more complex, basic check
            if [[ -s "$rootfs_file" ]]; then
                print_success "EROFS file exists and is non-empty"
                return 0
            else
                print_failed "EROFS file is empty or invalid"
                return 1
            fi
        ;;
        *)
            print_warn "Unknown filesystem type, skipping integrity check"
            return 0
        ;;
    esac
}

# Setup /home symlink to persistent partition
setup_home_symlink() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_home_symlink: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up /home symlink to persistent partition..."
    
    # Remove existing /home if it's not a symlink
    if [[ -L "$chroot_dir/home" ]]; then
        rm -f "$chroot_dir/home"
        elif [[ -d "$chroot_dir/home" ]]; then
        # Backup existing /home if it exists
        if [[ -d "$chroot_dir/home" ]]; then
            mv "$chroot_dir/home" "$chroot_dir/home.backup"
        fi
    fi
    
    # Create symlink
    ln -sf /persistent/home "$chroot_dir/home"
    
    # Create persistent home directory
    mkdir -p "$chroot_dir/persistent/home"
    
    print_success "/home symlink configured"
    return 0
}

# Check for LZ4HC support in kernel
check_erofs_lz4hc_support() {
    local kernel_version="${1:-$(uname -r)}"
    local config_file="/boot/config-$kernel_version"
    
    if [[ -f "$config_file" ]]; then
        if grep -q "CONFIG_EROFS_FS_LZ4HC=y" "$config_file"; then
            print_success "EROFS LZ4HC compression supported"
            return 0
        else
            print_warn "EROFS LZ4HC compression not supported in kernel"
            print_warn "Consider rebuilding kernel with CONFIG_EROFS_FS_LZ4HC=y"
            return 1
        fi
    else
        print_warn "Kernel config file not found: $config_file"
        return 1
    fi
}

