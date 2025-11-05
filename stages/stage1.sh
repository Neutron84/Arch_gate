#!/bin/bash
# =============================================================================
# STAGE 1: Interactive Questions and Basic Installation
# =============================================================================
# This stage:
# 1. Asks all necessary questions interactively
# 2. Saves configuration to /etc/archgate/config.conf
# 3. Performs basic installation (partitioning, base system)
# 4. Creates systemd service for Stage 2

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHGATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source all required modules
source "$ARCHGATE_DIR/lib/colors.sh"
source "$ARCHGATE_DIR/lib/logging.sh"
source "$ARCHGATE_DIR/lib/utils.sh"
source "$ARCHGATE_DIR/lib/packages.sh"
source "$ARCHGATE_DIR/lib/partition.sh"
source "$ARCHGATE_DIR/lib/config.sh"

# Source feature modules (conditional loading based on system type)
source "$ARCHGATE_DIR/lib/overlay.sh"
source "$ARCHGATE_DIR/lib/atomic-update.sh"
source "$ARCHGATE_DIR/lib/safety.sh"
source "$ARCHGATE_DIR/lib/memory.sh"
source "$ARCHGATE_DIR/lib/optimizations.sh"
source "$ARCHGATE_DIR/lib/grub-advanced.sh"

# Source system-specific modules
if [[ -f "$ARCHGATE_DIR/systems/usb_memory/check-usb-health.sh" ]]; then
    source "$ARCHGATE_DIR/systems/usb_memory/check-usb-health.sh"
fi

# Initialize
init_logger
banner

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_failed "This script must be run with root access"
    exit 1
fi

# Initialize configuration array
declare -A CONFIG

# Check dependencies
print_msg "Checking dependencies..."
if ! check_dependencies; then
    print_failed "Dependency check failed. Aborting."
    exit 1
fi

# Check internet connection
print_msg "Checking internet connection..."
if ! ping -c 1 archlinux.org &>/dev/null; then
    print_failed "No internet connection detected. Please connect to the internet first."
    exit 1
fi
print_success "Internet connection detected"

# =============================================================================
# INTERACTIVE QUESTIONS
# =============================================================================

banner
print_msg "${BOLD}=== Arch Gate Installation - Stage 1 ===${NC}"
echo

# System type selection
banner
print_msg "${BOLD}=== System Type Selection ===${NC}"
echo
print_msg "What type of system are you installing to?"
echo
echo "${Y}Real Systems (Internal Storage):${NC}"
echo "  1. SSD (Solid State Drive)"
echo "  2. HDD (Hard Disk Drive)"
echo
echo "${Y}Portable Systems (External/Removable - Hybrid Boot Enabled):${NC}"
echo "  3. SSD External (USB External Solid State Drive)"
echo "  4. HDD External (USB External Hard Drive)"
echo "  5. USB Memory (USB Flash Drive - Currently optimized)"
echo "  6. SD Card (SD/MicroSD Card)"
echo
select_an_option 6 1 system_type_choice
case "$system_type_choice" in
    1) CONFIG[system_type]="ssd" ;;
    2) CONFIG[system_type]="hdd" ;;
    3) CONFIG[system_type]="ssd_external" ;;
    4) CONFIG[system_type]="hdd_external" ;;
    5) CONFIG[system_type]="usb_memory" ;;
    6) CONFIG[system_type]="sdcard" ;;
esac

print_success "System type selected: ${CONFIG[system_type]}"

# Display available disks
banner
print_msg "${BOLD}=== Disk Selection ===${NC}"
echo
print_msg "Available disks:"
lsblk
echo

# Device selection
while true; do
    print_msg "Please enter the target device path (e.g., /dev/sdX or /dev/nvme0n1):"
    if ! read -r DEVICE < /dev/tty; then
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
    if [[ -z "$DEVICE" ]]; then
        print_failed "Input cannot be empty. Please enter a device path."
        continue
    fi
    
    if [[ ! -b "$DEVICE" ]]; then
        print_failed "Error: $DEVICE is not a valid block device"
        continue
    fi
    
    # Display selected disk information
    print_warn "Selected drive information:"
    lsblk -f "$DEVICE"
    echo
    print_warn "Current mount points:"
    findmnt "$DEVICE"* 2>/dev/null || echo "No mounted partitions found"
    echo
    
    # Confirmation
    if confirmation_y_or_n "⚠️ WARNING: Are you sure you want to use $DEVICE? This operation will PERMANENTLY DELETE all data!" confirm_device; then
        break
    fi
done

CONFIG[device]="$DEVICE"

# Detect storage type
print_msg "Detecting storage type..."
STORAGE_TYPE=$(detect_storage_type "$DEVICE")
CONFIG[storage_type]="$STORAGE_TYPE"
print_success "Storage type detected: $STORAGE_TYPE"

# Partition scheme selection
banner
print_msg "${BOLD}Select partition scheme:${NC}"
echo
echo "${Y}1. Hybrid (GPT with BIOS support - Recommended for portable devices)${NC}"
echo "${Y}2. GPT (UEFI only)${NC}"
echo "${Y}3. MBR (Legacy BIOS)${NC}"
echo
select_an_option 3 1 part_scheme
case "$part_scheme" in
    1) CONFIG[partition_scheme]="hybrid" ;;
    2) CONFIG[partition_scheme]="gpt" ;;
    3) CONFIG[partition_scheme]="mbr" ;;
esac

# Filesystem selection
banner
print_msg "${BOLD}Select filesystem type:${NC}"
echo
echo "${Y}1. bcachefs (Modern, recommended)${NC}"
echo "${Y}2. ext4 (Stable, widely supported)${NC}"
echo "${Y}3. f2fs (Optimized for flash storage)${NC}"
echo
select_an_option 3 1 fs_type
case "$fs_type" in
    1) CONFIG[filesystem_type]="bcachefs" ;;
    2) CONFIG[filesystem_type]="ext4" ;;
    3) CONFIG[filesystem_type]="f2fs" ;;
esac

# System configuration
banner
print_msg "${BOLD}=== System Configuration ===${NC}"
echo

# Hostname
print_msg "Enter system hostname (default: arch-gate):"
if ! read -r HOSTNAME < /dev/tty; then
    print_failed "Could not read from terminal. Aborting."
    exit 1
fi
HOSTNAME="${HOSTNAME:-arch-gate}"
CONFIG[hostname]="$HOSTNAME"

# Root password
while true; do
    print_msg "Enter root password (input hidden):"
    if ! read -r -s ROOT_PW < /dev/tty; then
        echo
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
    echo
    print_msg "Confirm root password:"
    if ! read -r -s ROOT_PW_CONFIRM < /dev/tty; then
        echo
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
    echo
    if [[ "$ROOT_PW" == "$ROOT_PW_CONFIRM" && -n "$ROOT_PW" ]]; then
        #CONFIG[root_password]="$ROOT_PW"

        # Hash the password using SHA-512
        HASHED_ROOT_PW=$(openssl passwd -6 "$ROOT_PW")
        CONFIG[root_password]="$HASHED_ROOT_PW"
        break
    fi
    print_failed "Passwords do not match or empty. Please try again."
done

# Username
print_msg "Enter username for regular user (default: user):"
if ! read -r USERNAME < /dev/tty; then
    print_failed "Could not read from terminal. Aborting."
    exit 1
fi
USERNAME="${USERNAME:-user}"
while [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; do
    print_failed "Invalid username. Use only lowercase letters, numbers, - and _. Try again:"
    if ! read -r USERNAME < /dev/tty; then
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
done
CONFIG[username]="$USERNAME"

# User password
while true; do
    print_msg "Enter password for $USERNAME (input hidden):"
    if ! read -r -s USER_PW < /dev/tty; then
        echo
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
    echo
    print_msg "Confirm password for $USERNAME:"
    if ! read -r -s USER_PW_CONFIRM < /dev/tty; then
        echo
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
    echo
    if [[ "$USER_PW" == "$USER_PW_CONFIRM" && -n "$USER_PW" ]]; then
        # CONFIG[user_password]="$USER_PW"

        # Hash the password using SHA-512
        HASHED_USER_PW=$(openssl passwd -6 "$USER_PW")
        CONFIG[user_password]="$HASHED_USER_PW"
        break
    fi
    print_failed "Passwords do not match or empty. Please try again."
done

# Timezone
print_msg "Enter timezone (e.g., Asia/Tehran) (default: Asia/Tehran):"
if ! read -r TIMEZONE < /dev/tty; then
    print_failed "Could not read from terminal. Aborting."
    exit 1
fi
TIMEZONE="${TIMEZONE:-Asia/Tehran}"
CONFIG[timezone]="$TIMEZONE"

# Locale
print_msg "Enter locale (default: en_US.UTF-8):"
if ! read -r LOCALE < /dev/tty; then
    print_failed "Could not read from terminal. Aborting."
    exit 1
fi
LOCALE="${LOCALE:-en_US.UTF-8}"
CONFIG[locale]="$LOCALE"

# Package selection
banner
print_msg "${BOLD}=== Software Selection ===${NC}"
echo

# Desktop environment
if confirmation_y_or_n "Do you want to install Hyprland desktop environment?" install_desktop; then
    CONFIG[install_desktop]="y"
else
    CONFIG[install_desktop]="n"
fi

# Development tools
if confirmation_y_or_n "Do you want to install development tools?" install_dev; then
    CONFIG[install_dev]="y"
else
    CONFIG[install_dev]="n"
fi

# Office suite
if confirmation_y_or_n "Do you want to install office software suite?" install_office; then
    CONFIG[install_office]="y"
else
    CONFIG[install_office]="n"
fi

# Graphics and multimedia
if confirmation_y_or_n "Do you want to install graphics and multimedia software?" install_graphics; then
    CONFIG[install_graphics]="y"
else
    CONFIG[install_graphics]="n"
fi

# Graphics drivers
if lspci | grep -i "nvidia" > /dev/null; then
    if confirmation_y_or_n "NVIDIA graphics card detected. Do you want to install NVIDIA drivers?" install_nvidia; then
        CONFIG[install_nvidia]="y"
    else
        CONFIG[install_nvidia]="n"
    fi
else
    CONFIG[install_nvidia]="n"
fi

if lspci | grep -i "amd" > /dev/null; then
    if confirmation_y_or_n "AMD graphics card detected. Do you want to install AMD drivers?" install_amd; then
        CONFIG[install_amd]="y"
    else
        CONFIG[install_amd]="n"
    fi
else
    CONFIG[install_amd]="n"
fi

if lspci | grep -i "intel" > /dev/null; then
    if confirmation_y_or_n "Intel graphics card detected. Do you want to install Intel drivers?" install_intel; then
        CONFIG[install_intel]="y"
    else
        CONFIG[install_intel]="n"
    fi
else
    CONFIG[install_intel]="n"
fi

# Set mount point
CONFIG[mount_point]="/mnt/usb"
CONFIG[stage]="1"

# Save configuration
print_msg "Saving configuration..."
save_config
print_success "Configuration saved to $CONFIG_FILE"

# =============================================================================
# BASIC INSTALLATION
# =============================================================================

banner
print_msg "${BOLD}=== Starting Basic Installation ===${NC}"
echo

# Final confirmation
print_warn "⚠️ FINAL WARNING! This is a destructive operation and cannot be undone!"
print_warn "This will erase ALL DATA on $DEVICE including:"
echo "  - All partitions and their contents"
echo "  - Any operating systems"
echo "  - All personal files and backups"
echo

print_warn "To confirm, please type exactly: 'yes, format $DEVICE'"
if ! read -r confirmation_text < /dev/tty; then
    print_failed "Could not read from terminal. Aborting."
    exit 1
fi

if [[ "$confirmation_text" != "yes, format $DEVICE" ]]; then
    print_failed "Operation cancelled: Confirmation text does not match"
    exit 1
fi

# Wipe and partition
print_msg "Wiping and partitioning $DEVICE..."
if ! wipe_and_partition "$DEVICE" "${CONFIG[partition_scheme]}"; then
    print_failed "Failed to wipe and partition device"
    exit 1
fi

# Create partitions
print_msg "Creating partitions..."
if ! create_partitions "$DEVICE" "${CONFIG[storage_type]}" "${CONFIG[partition_scheme]}"; then
    print_failed "Failed to create partitions"
    exit 1
fi

# Update live environment (minimal to save space)
print_msg "Updating live environment (minimal update)..."
pacman-key --init 2>/dev/null
pacman-key --populate archlinux 2>/dev/null
pacman -Sy --noconfirm 2>/dev/null || print_warn "Repository update had issues"

# Install filesystem tools if needed
if [[ "${CONFIG[filesystem_type]}" == "bcachefs" ]]; then
    print_msg "Installing bcachefs-tools..."
    if ! package_install_and_check "bcachefs-tools dkms linux-headers"; then
        print_warn "bcachefs-tools installation failed, falling back to ext4"
        CONFIG[filesystem_type]="ext4"
        save_config
    else
        # Try to load bcachefs module
        if ! modinfo bcachefs &>/dev/null; then
            print_msg "Building bcachefs module with DKMS..."
            dkms autoinstall 2>/dev/null || print_warn "DKMS build had issues"
            modprobe bcachefs 2>/dev/null || {
                print_warn "Could not load bcachefs module, falling back to ext4"
                CONFIG[filesystem_type]="ext4"
                save_config
            }
        fi
    fi
fi

# Format partitions
print_msg "Formatting partitions..."
if ! format_partitions "$DEVICE" "${CONFIG[storage_type]}" "${CONFIG[filesystem_type]}"; then
    print_failed "Failed to format partitions"
    exit 1
fi

# Mount partitions
print_msg "Mounting partitions..."
if ! mount_partitions "$DEVICE" "${CONFIG[mount_point]}"; then
    print_failed "Failed to mount partitions"
    exit 1
fi

# Install base system (minimal to save space)
print_msg "Installing base system (minimal installation)..."
BASE_PACKAGES="base linux linux-firmware sudo nano git networkmanager grub efibootmgr"

mkdir -p "${CONFIG[mount_point]}/persistent/arch_root"

if ! package_install_pacstrap "$BASE_PACKAGES" "${CONFIG[mount_point]}/persistent/arch_root"; then
    print_failed "Failed to install base system"
    exit 1
fi

print_success "Base system installed"

# Update stage
update_stage "2"

# Create Stage 2 systemd service
print_msg "Creating Stage 2 systemd service..."
STAGE2_SERVICE="/etc/systemd/system/archgate-stage2.service"
STAGE2_SCRIPT="${CONFIG[mount_point]}/persistent/arch_root/usr/local/bin/archgate-stage2.sh"

# Copy Stage 2 script and libraries to installed system
mkdir -p "$(dirname "$STAGE2_SCRIPT")"
cp "$ARCHGATE_DIR/archgate/stages/stage2.sh" "$STAGE2_SCRIPT"
chmod +x "$STAGE2_SCRIPT"

# Copy library files
LIB_TARGET="${CONFIG[mount_point]}/persistent/arch_root/usr/local/lib/archgate"
mkdir -p "$LIB_TARGET"
cp "$ARCHGATE_DIR/archgate/lib"/*.sh "$LIB_TARGET/"
chmod 644 "$LIB_TARGET"/*.sh

# Create systemd service
cat > "$STAGE2_SERVICE" <<EOF
[Unit]
Description=Arch Gate Stage 2 Installation
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$STAGE2_SCRIPT
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Enable service in chroot
arch-chroot "${CONFIG[mount_point]}/persistent/arch_root" systemctl enable archgate-stage2.service

print_success "Stage 2 service created and enabled"

banner
print_success "${BOLD}Stage 1 completed successfully!${NC}"
print_msg "Configuration saved to: $CONFIG_FILE"
print_msg "The system will continue installation on next boot via Stage 2 service"
print_msg "You can now reboot the system"
echo

