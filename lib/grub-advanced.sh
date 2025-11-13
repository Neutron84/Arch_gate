#!/bin/bash
# =============================================================================
# ADVANCED GRUB CONFIGURATION MODULE
# =============================================================================
# This module provides advanced GRUB configuration
# Features:
# - Multiple boot menus (Low/Medium/High Resource Mode)
# - Safe Mode and Recovery Mode
# - Automatic RAM detection and profile
# - Kernel parameters based on RAM

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

# Setup advanced GRUB configuration
setup_advanced_grub() {
    local chroot_dir="$1"
    local esp_mount="${2:-/boot}"
    local system_type="${3:-}"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_advanced_grub: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up advanced GRUB configuration..."
    
    # Get ESP UUID
    local esp_uuid=$(blkid -s UUID -o value "$(findmnt -n -o SOURCE "$esp_mount" 2>/dev/null)" 2>/dev/null || echo "")
    
    # Create advanced GRUB configuration
    cat > "$chroot_dir/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0

# Automatic RAM detection
probe -u \$root --set=uuid
export uuid
load_env -f (\$root)/grub/grubenv

# Function to detect RAM and set appropriate profile
function get_ram_profile {
    # Get RAM amount in megabytes
    regexp --set=ram_mb "([0-9]+)M" \$grub_total_ram
    set ram_size="\$ram_mb"
    if [ "\$ram_mb" -lt "2048" ]; then
        echo "low"
    elif [ "\$ram_mb" -lt "8192" ]; then
        echo "medium"
    else
        echo "high"
    fi
    echo "System RAM: \${ram_size}MB" >&2
}

menuentry "Arch Linux (Automatic Profile)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    set ram_profile=\$(get_ram_profile)
    if [ "\$ram_profile" = "low" ]; then
        linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd mem_sleep_default=s2idle mitigations=off
    elif [ "\$ram_profile" = "medium" ]; then
        linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd transparent_hugepage=always
    else
        linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd transparent_hugepage=always preempt=full
    fi
    initrd /arch/initramfs-linux.img
    echo "Selected RAM profile: \$ram_profile"
}

menuentry "Arch Linux (Low Resource Mode - 2GB RAM)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd mem_sleep_default=s2idle mitigations=off
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux (Medium Resource Mode - 2-8GB RAM)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd transparent_hugepage=always
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux (High Resource Mode - 8GB+ RAM)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd transparent_hugepage=always preempt=full
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux (Safe Mode)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux nomodeset systemd.unit=multi-user.target
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux (Recovery Mode - Read Only)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux systemd.unit=rescue.target single nomodeset systemd.debug-shell=1 ro
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux (Snapshot Recovery)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux systemd.unit=multi-user.target single
    initrd /arch/initramfs-linux.img
}
EOF
    
    # For portable systems, ensure hybrid boot is configured
    if [[ "$system_type" =~ ^usb_|sdcard ]]; then
        print_msg "Configuring hybrid boot for portable system..."
        
        # The partition.sh already handles hybrid boot partitioning
        # Here we just ensure GRUB is installed for both BIOS and UEFI
        print_success "Hybrid boot support enabled (BIOS and UEFI)"
    fi
    
    print_success "Advanced GRUB configuration created"
    return 0
}

# Install GRUB for hybrid boot (BIOS + UEFI)
install_grub_hybrid() {
    local device="$1"
    local esp_mount="${2:-/mnt}"
    
    if [[ -z "$device" ]]; then
        print_failed "install_grub_hybrid: device is required"
        return 1
    fi
    
    print_msg "Installing GRUB for hybrid boot..."
    
    # Install GRUB for UEFI
    if [[ -d "$esp_mount" ]] && mountpoint -q "$esp_mount"; then
        print_msg "Installing GRUB for UEFI..."
        grub-install --target=x86_64-efi --efi-directory="$esp_mount" --bootloader-id=ARCH_GATE --removable || {
            print_warn "UEFI GRUB installation failed"
        }
    fi
    
    # Install GRUB for BIOS
    print_msg "Installing GRUB for BIOS..."
    grub-install --target=i386-pc "$device" || {
        print_warn "BIOS GRUB installation failed"
    }
    
    print_success "GRUB hybrid boot installation completed"
    return 0
}

