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
# BOOTLOADER CONFIGURATION
# =============================================================================

print_msg "=== Configuring Bootloader ==="

# Detect ESP partition
ESP_PART=$(lsblk -no NAME,PARTTYPE | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b\|EF00" | head -n1 | awk '{print "/dev/"$1}')
if [[ -z "$ESP_PART" ]]; then
    # Fallback: try to find mounted ESP
    ESP_PART=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || findmnt -n -o SOURCE /boot 2>/dev/null)
fi

if [[ -n "$ESP_PART" ]]; then
    # Mount ESP if not mounted
    if ! mountpoint -q /boot/efi 2>/dev/null; then
        mkdir -p /boot/efi
        mount "$ESP_PART" /boot/efi || print_warn "Could not mount ESP"
    fi
    
    # Install GRUB
    if command -v grub-install &>/dev/null; then
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARCHGATE || print_warn "GRUB installation had issues"
        grub-mkconfig -o /boot/grub/grub.cfg || print_warn "GRUB configuration had issues"
        print_success "GRUB bootloader configured"
    fi
fi

# =============================================================================
# ENABLE SERVICES
# =============================================================================

print_msg "=== Enabling Services ==="

systemctl enable NetworkManager || print_warn "Failed to enable NetworkManager"
systemctl enable systemd-oomd || print_warn "Failed to enable systemd-oomd"
systemctl enable fstrim.timer || print_warn "Failed to enable fstrim.timer"

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

