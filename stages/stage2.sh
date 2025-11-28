#!/bin/bash
# =============================================================================
# STAGE 2: Continue Installation from Configuration
# =============================================================================
# This stage:
# 1. Loads configuration from /etc/archgate/config.conf
# 2. Completes installation (packages, configuration, bootloader)
# 3. Removes itself after completion

# Configuration file
CONFIG_FILE="/etc/archgate/config.conf"
LOG_FILE="/var/log/archgate/stage2.log"

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Arch Gate Stage 2 Installation"
echo "Started at: $(date)"
echo "=========================================="

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# Import libraries
if [[ -f /usr/local/lib/archgate/colors.sh ]]; then
    source /usr/local/lib/archgate/colors.sh
    source /usr/local/lib/archgate/logging.sh
    source /usr/local/lib/archgate/utils.sh
    # Feature modules
    [[ -f /usr/local/lib/archgate/overlay.sh ]] && source /usr/local/lib/archgate/overlay.sh
    [[ -f /usr/local/lib/archgate/atomic-update.sh ]] && source /usr/local/lib/archgate/atomic-update.sh
    [[ -f /usr/local/lib/archgate/safety.sh ]] && source /usr/local/lib/archgate/safety.sh
    [[ -f /usr/local/lib/archgate/memory.sh ]] && source /usr/local/lib/archgate/memory.sh
    [[ -f /usr/local/lib/archgate/optimizations.sh ]] && source /usr/local/lib/archgate/optimizations.sh
    [[ -f /usr/local/lib/archgate/grub-advanced.sh ]] && source /usr/local/lib/archgate/grub-advanced.sh
    # System-specific (USB memory)
    [[ -f /usr/local/lib/archgate/../systems/usb_memory/check-usb-health.sh ]] && source /usr/local/lib/archgate/../systems/usb_memory/check-usb-health.sh
else
    # Fallback minimal functions if libraries aren't available
    print_msg() { echo "[INFO] $*"; }
    print_success() { echo "[SUCCESS] $*"; }
    print_warn() { echo "[WARN] $*"; }
    print_failed() { echo "[FAILED] $*"; }
fi

# Mount points (assuming we're running from installed system)
MOUNT_POINT="${MOUNT_POINT:-/}"
CHROOT_ROOT="${CHROOT_ROOT:-/}"

print_msg "Configuration loaded from $CONFIG_FILE"
print_msg "Continuing installation..."

# =============================================================================
# COMPLETE PACKAGE INSTALLATION
# =============================================================================

print_msg "=== Installing Additional Packages ==="

# Build package list
BASE_PACKAGES="base linux linux-firmware linux-headers sudo nano git base-devel gcc make zram-generator networkmanager grub efibootmgr mtools dosfstools ntfs-3g"
SYSTEM_TOOLS="htop iotop vmtouch powertop smartmontools hdparm nvme-cli dmidecode zstd lz4 pigz pbzip2"
DESKTOP_ENV="hyprland kitty wofi waybar dunst grim slurp xdg-desktop-portal-hyprland pipewire pipewire-pulse wireplumber"
GRAPHICS_BASE="vulkan-icd-loader vulkan-tools mesa-utils libva-utils vdpauinfo"
DEVELOPMENT_TOOLS="vim neovim python python-pip nodejs npm rust"
OFFICE_SUITE="libreoffice-fresh hunspell hunspell-en_us hunspell-fa"
GRAPHICS_APPS="gimp inkscape blender vlc"
THEMES="noto-fonts ttf-dejavu ttf-liberation ttf-fira-code gnome-themes-extra papirus-icon-theme"

PACKAGES="$BASE_PACKAGES $SYSTEM_TOOLS"

if [[ "${INSTALL_DESKTOP:-n}" == "y" ]]; then
    PACKAGES="$PACKAGES $DESKTOP_ENV $GRAPHICS_BASE $THEMES"
fi

if [[ "${INSTALL_DEV:-n}" == "y" ]]; then
    PACKAGES="$PACKAGES $DEVELOPMENT_TOOLS"
fi

if [[ "${INSTALL_OFFICE:-n}" == "y" ]]; then
    PACKAGES="$PACKAGES $OFFICE_SUITE"
fi

if [[ "${INSTALL_GRAPHICS:-n}" == "y" ]]; then
    PACKAGES="$PACKAGES $GRAPHICS_APPS"
fi

if [[ "${INSTALL_NVIDIA:-n}" == "y" ]]; then
    PACKAGES="$PACKAGES nvidia-dkms nvidia-utils nvidia-settings"
fi

if [[ "${INSTALL_AMD:-n}" == "y" ]]; then
    PACKAGES="$PACKAGES xf86-video-amdgpu vulkan-radeon"
fi

if [[ "${INSTALL_INTEL:-n}" == "y" ]]; then
    PACKAGES="$PACKAGES xf86-video-intel vulkan-intel intel-media-driver intel-gpu-tools"
fi

# Install packages
print_msg "Installing packages: $PACKAGES"
pacman -S --noconfirm --needed $PACKAGES || {
    print_warn "Some packages failed to install, continuing..."
}

# =============================================================================
# SYSTEM CONFIGURATION
# =============================================================================

print_msg "=== Configuring System ==="

# Set hostname
if [[ -n "${HOSTNAME:-}" ]]; then
    echo "$HOSTNAME" > /etc/hostname
    print_success "Hostname set to: $HOSTNAME"
fi

# Configure locale
if [[ -n "${LOCALE:-}" ]]; then
    sed -i "s/#${LOCALE}/${LOCALE}/" /etc/locale.gen 2>/dev/null || echo "${LOCALE} UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=${LOCALE}" > /etc/locale.conf
    print_success "Locale configured: $LOCALE"
fi

# Set timezone
if [[ -n "${TIMEZONE:-}" ]]; then
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    hwclock --systohc
    print_success "Timezone set to: $TIMEZONE"
fi

# Set root password (using hashed password)
if [[ -n "${ROOT_PASSWORD:-}" ]]; then
    # echo "root:${ROOT_PASSWORD}" | chpasswd
    echo "root:${ROOT_PASSWORD}" | chpasswd -e
    print_success "Root password configured"
fi

# Create user
if [[ -n "${USERNAME:-}" ]]; then
    if ! id "$USERNAME" &>/dev/null; then
        useradd -m -G wheel -s /bin/bash "$USERNAME"
        print_success "User created: $USERNAME"
    fi
    
    if [[ -n "${USER_PASSWORD:-}" ]]; then
        # echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
        echo "${USERNAME}:${USER_PASSWORD}" | chpasswd -e
        print_success "User password configured"
    fi
    
    # Configure sudo
    if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
        echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
        print_success "Sudo configured for wheel group"
    fi
fi

# Generate fstab
if ! grep -q "^UUID" /etc/fstab 2>/dev/null; then
    genfstab -U / >> /etc/fstab
    print_success "fstab generated"
fi

# =============================================================================
# ADVANCED SYSTEM FEATURES (Overlay, Atomic Update, Safety, Memory, Optimizations)
# =============================================================================

print_msg "=== Configuring Advanced System Features ==="

# Snapshot System Configuration (Snapper)
# Only runs if filesystem is Btrfs (checked inside the function)
if declare -F setup_snapper >/dev/null; then
    setup_snapper "/"
fi

# Overlay hook and initramfs
if declare -F setup_overlay_hook >/dev/null; then
    setup_overlay_hook "/" "/"
    if command -v mkinitcpio &>/dev/null; then
        print_msg "Running mkinitcpio -P (overlay applied)"
        if ! mkinitcpio -P; then
            print_warn "mkinitcpio failed; retrying once with default config"
            if ! mkinitcpio -P; then
                print_failed "mkinitcpio failed after retry. System may not boot; check /etc/mkinitcpio.conf and modules."
            else
                print_success "mkinitcpio succeeded on retry"
            fi
        else
            print_success "mkinitcpio completed successfully"
        fi
    fi
fi

# Atomic update system
if declare -F setup_atomic_update >/dev/null; then
    setup_atomic_update "/"
fi

# Safety and recovery systems
if declare -F setup_safety_systems >/dev/null; then
    setup_safety_systems "/"
fi

# Memory optimization (ZRAM/ZSWAP)
if declare -F setup_memory_optimization >/dev/null; then
    setup_memory_optimization "/"
fi

# Advanced optimizations bundle
if declare -F setup_all_optimizations >/dev/null; then
    setup_all_optimizations "/"
fi

# USB health (for usb_memory specifically)
if [[ "${SYSTEM_TYPE:-}" == "usb_memory" ]] && declare -F setup_usb_health_check >/dev/null; then
    setup_usb_health_check "/"
fi

# Build root filesystem image and copy kernel/initramfs
if declare -F create_squashfs_image >/dev/null; then
    mkdir -p /persistent/arch
    target_rootfs="/persistent/arch/root.squashfs"
    print_msg "Creating root filesystem image at $target_rootfs"
    if ! create_squashfs_image "/" "$target_rootfs" true; then
        print_warn "EROFS image creation failed, falling back to Squashfs"
        if ! create_squashfs_image "/" "$target_rootfs" false; then
            print_failed "Failed to create root filesystem image"
        fi
    fi
    if [[ -f "$target_rootfs" && -s "$target_rootfs" ]]; then
        print_success "Root filesystem image created: $target_rootfs"
    else
        print_warn "Root filesystem image missing or empty: $target_rootfs"
    fi
    # Copy kernel/initramfs
    if [ -f /boot/vmlinuz-linux ]; then
        cp -f /boot/vmlinuz-linux /persistent/arch/ 2>/dev/null && print_success "Copied vmlinuz-linux to /persistent/arch" || print_warn "Failed to copy vmlinuz-linux"
    else
        print_warn "Kernel not found at /boot/vmlinuz-linux"
    fi
    if [ -f /boot/initramfs-linux.img ]; then
        cp -f /boot/initramfs-linux.img /persistent/arch/ 2>/dev/null && print_success "Copied initramfs-linux.img to /persistent/arch" || print_warn "Failed to copy initramfs-linux.img"
    else
        print_warn "Initramfs not found at /boot/initramfs-linux.img"
    fi
fi

# =============================================================================
# BOOTLOADER CONFIGURATION
# =============================================================================

print_msg "=== Configuring Bootloader ==="

# Use advanced GRUB module when available
if declare -F setup_advanced_grub >/dev/null; then
    # Ensure ESP mounted at /boot or /boot/efi
    ESP_MNT="/boot"
    mountpoint -q /boot 2>/dev/null || mountpoint -q /boot/efi 2>/dev/null || {
        ESP_PART=$(lsblk -no NAME,PARTTYPE | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b\|EF00" | head -n1 | awk '{print "/dev/"$1}')
        if [[ -n "$ESP_PART" ]]; then
            mkdir -p /boot
            mount "$ESP_PART" /boot 2>/dev/null || {
                mkdir -p /boot/efi
                mount "$ESP_PART" /boot/efi || print_warn "Could not mount ESP"
                ESP_MNT="/boot/efi"
            }
        fi
    }
    setup_advanced_grub "/" "$ESP_MNT" "${SYSTEM_TYPE:-}"
    # Install hybrid GRUB for portable targets
    case "${SYSTEM_TYPE:-}" in
        usb_memory|ssd_external|hdd_external|sdcard)
            if declare -F install_grub_hybrid >/dev/null && [[ -n "${DEVICE:-}" ]]; then
                install_grub_hybrid "$DEVICE" "$ESP_MNT"
            fi
            ;;
        *) ;;
    esac
else
    print_warn "Advanced GRUB module not available; skipping"
fi

# =============================================================================
# ENABLE SERVICES
# =============================================================================

print_msg "=== Enabling Services ==="

systemctl enable NetworkManager || print_warn "Failed to enable NetworkManager"
systemctl enable systemd-oomd || print_warn "Failed to enable systemd-oomd"
systemctl enable fstrim.timer || print_warn "Failed to enable fstrim.timer"

# Enable feature services/timers when present
for unit in \
    atomic-update.timer \
    periodic-sync.timer \
    system-snapshot.timer \
    performance-telemetry.timer \
    smart-prefetch.timer \
    configure-memory.service \
    zram-generator \
    hardware-profile.service \
    io-optimizer.service \
    final-optimizations.service \
    io-health-monitor.service \
    power-failure-detector.service \
    usb-health.timer
do
    systemctl enable "$unit" 2>/dev/null || true
done

if [[ "${INSTALL_DESKTOP:-n}" == "y" ]]; then
    systemctl enable pipewire pipewire-pulse wireplumber || print_warn "Failed to enable audio services"
fi

print_success "Services enabled"

# =============================================================================
# CLEANUP AND FINALIZATION
# =============================================================================

print_msg "=== Finalizing Installation ==="

# Clean package cache
print_msg "Cleaning package cache..."
pacman -Sc --noconfirm || true

# Update stage
echo "STAGE=completed" >> "$CONFIG_FILE"

# Disable and remove Stage 2 service
print_msg "Removing Stage 2 service..."
systemctl disable archgate-stage2.service || true
rm -f /etc/systemd/system/archgate-stage2.service
systemctl daemon-reload

# Remove Stage 2 script
rm -f /usr/local/bin/archgate-stage2.sh

print_success "Stage 2 service removed"

print_msg "=========================================="
print_success "Arch Gate Installation Completed!"
print_msg "Configuration saved to: $CONFIG_FILE"
print_msg "You can now reboot the system"
print_msg "Completed at: $(date)"
echo "=========================================="

exit 0

