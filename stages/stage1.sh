#!/bin/bash
# =============================================================================
# STAGE 1: Interactive Questions and Basic Installation
# =============================================================================
# This stage:
# 1. Asks all necessary questions interactively
# 2. Saves configuration to /etc/archgate/config.conf
# 3. Performs basic installation (partitioning, base system)
# 4. Creates systemd service for Stage 2

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Function to safely load library files
# shellcheck disable=SC1090
load_library() {
    local lib_file="$LIB_DIR/$1"
    if [[ -f "$lib_file" ]]; then
        if source "$lib_file"; then
            return 0
        else
            echo "ERROR: Failed to load library: $lib_file" >&2
            exit 1
        fi
    else
        echo "ERROR: Library not found: $lib_file" >&2
        exit 1
    fi
}

# Load core libraries first (in order)
load_library "colors.sh"
load_library "logging.sh"
load_library "utils.sh"
load_library "config.sh"
load_library "packages.sh"
load_library "partition.sh"
load_library "overlay.sh"
load_library "atomic-update.sh"
load_library "safety.sh"
load_library "memory.sh"
load_library "optimizations.sh"
load_library "grub-advanced.sh"

# Handle Ctrl+C and cleanup
export CLEANUP_REQUIRED=true
trap 'echo; print_failed "Script interrupted by user. Cleaning up..."; cleanup_on_exit; exit 1' INT TERM
trap 'cleanup_on_exit' EXIT

# Source system-specific modules
if [[ -f "$PROJECT_ROOT/systems/usb_memory/check-usb-health.sh" ]]; then
    source "$PROJECT_ROOT/systems/usb_memory/check-usb-health.sh"
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
# print_msg "Checking internet connection..."
# if ! ping -c 1 archlinux.org &>/dev/null; then
#     print_failed "No internet connection detected. Please connect to the internet first."
#     exit 1
# fi
# print_success "Internet connection detected"

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
# shellcheck disable=SC2034
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

# Device selection with validation
while true; do
    # Set up trap for this specific read operation
    trap 'echo; print_failed "Operation cancelled by user"; exit 1' INT
    if ! read -p "Please enter the target device path (e.g., /dev/sdX or /dev/nvme0n1): " -r DEVICE </dev/tty; then
        echo
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
    echo
    # Restore the original trap
    trap 'echo; print_failed "Script interrupted by user. Cleaning up..."; cleanup_on_exit; exit 1' INT
    
    if [[ -z "$DEVICE" ]]; then
        print_failed "Input cannot be empty. Please enter a device path."
        continue
    fi
    
    # Validate device format
    if ! validate_input "$DEVICE" "device"; then
        print_failed "Invalid device format: $DEVICE"
        continue
    fi
    
    # Validate block device
    if ! validate_block_device "$DEVICE"; then
        continue
    fi

    # Check if device is mounted as root or contains system directories
    if mountpoint -q / && [[ "$(findmnt -n -o SOURCE /)" == "$DEVICE"* ]]; then
        print_failed "Error: $DEVICE contains the root filesystem and cannot be used"
        print_failed "Please select a different device that is not currently in use"
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
# shellcheck disable=SC2034
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
# shellcheck disable=SC2034
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

# Hostname with validation
HOSTNAME=$(safe_user_input "Enter system hostname" "hostname" "arch-gate" || echo "arch-gate")
CONFIG[hostname]="$HOSTNAME"

# Root password with secure hashing (optional)
setup_password() {
    local config_key="$1"
    local prompt_message="$2"
    local password
    local password_confirm
    
    # Ask if user wants to set a password
    if confirmation_y_or_n "Do you want to set a password for root?" "root_use_password" "false"; then
        CONFIG["root_use_password"]="y"
    else
        CONFIG["$config_key"]=""
        CONFIG["root_use_password"]="n"
        print_msg "Root password will not be set (passwordless login)"
        return 0
    fi
    
    while true; do
        echo -n "$prompt_message: "
        if ! read -r -s password </dev/tty; then
            return 1
        fi
        echo
        
        if [[ ${#password} -lt 8 ]]; then
            print_failed "Password must be at least 8 characters"
            continue
        fi
        
        echo -n "Confirm password: "
        if ! read -r -s password_confirm </dev/tty; then
            return 1
        fi
        echo
        
        if [[ "$password" != "$password_confirm" ]]; then
            print_failed "Passwords do not match"
            continue
        fi
        
        # Use secure password hashing with random salt
        local salt
        salt=$(openssl rand -base64 12 2>/dev/null || echo "")
        local hashed_password
        if [[ -n "$salt" ]]; then
            hashed_password=$(openssl passwd -6 -salt "$salt" "$password" 2>/dev/null || openssl passwd -6 "$password")
        else
            hashed_password=$(openssl passwd -6 "$password")
        fi
        
        CONFIG["$config_key"]="$hashed_password"
        return 0
    done
}

setup_password "root_password" "Enter root password (input hidden, min 8 chars)"

# Username with validation (optional)
if confirmation_y_or_n "Do you want to create a regular user?" "create_user" "false"; then
    CONFIG[create_user]="y"
    USERNAME=$(safe_user_input "Enter username for regular user" "username" "user" || echo "user")
    CONFIG[username]="$USERNAME"
    
    # User password with secure hashing (optional)
    setup_user_password() {
        local config_key="$1"
        local prompt_message="$2"
        local password
        local password_confirm
        
        # Ask if user wants to set a password
        if confirmation_y_or_n "Do you want to set a password for $USERNAME?" "user_use_password" "false"; then
            CONFIG["user_use_password"]="y"
        else
            CONFIG["$config_key"]=""
            CONFIG["user_use_password"]="n"
            print_msg "User password will not be set (passwordless login)"
            return 0
        fi
        
        while true; do
            echo -n "$prompt_message: "
            if ! read -r -s password </dev/tty; then
                return 1
            fi
            echo
            
            if [[ ${#password} -lt 8 ]]; then
                print_failed "Password must be at least 8 characters"
                continue
            fi
            
            echo -n "Confirm password: "
            if ! read -r -s password_confirm </dev/tty; then
                return 1
            fi
            echo
            
            if [[ "$password" != "$password_confirm" ]]; then
                print_failed "Passwords do not match"
                continue
            fi
            
            # Use secure password hashing with random salt
            local salt
            salt=$(openssl rand -base64 12 2>/dev/null || echo "")
            local hashed_password
            if [[ -n "$salt" ]]; then
                hashed_password=$(openssl passwd -6 -salt "$salt" "$password" 2>/dev/null || openssl passwd -6 "$password")
            else
                hashed_password=$(openssl passwd -6 "$password")
            fi
            
            CONFIG["$config_key"]="$hashed_password"
            return 0
        done
    }
    
    setup_user_password "user_password" "Enter password for $USERNAME (input hidden, min 8 chars)"
else
    CONFIG[create_user]="n"
    CONFIG[username]=""
    CONFIG[user_password]=""
fi

# Timezone with validation
TIMEZONE=$(safe_user_input "Enter timezone (e.g., Asia/Tehran)" "timezone" "Asia/Tehran" || echo "Asia/Tehran")
CONFIG[timezone]="$TIMEZONE"

# Locale with validation
LOCALE=$(safe_user_input "Enter locale" "locale" "en_US.UTF-8" || echo "en_US.UTF-8")
CONFIG[locale]="$LOCALE"

# Package selection
banner
print_msg "${BOLD}=== Software Selection ===${NC}"
echo

# Desktop environment (no double confirmation for package installation)
if confirmation_y_or_n "Do you want to install Hyprland desktop environment?" install_desktop "false"; then
    CONFIG[install_desktop]="y"
else
    CONFIG[install_desktop]="n"
fi

# Development tools
if confirmation_y_or_n "Do you want to install development tools?" install_dev "false"; then
    CONFIG[install_dev]="y"
else
    CONFIG[install_dev]="n"
fi

# Office suite
if confirmation_y_or_n "Do you want to install office software suite?" install_office "false"; then
    CONFIG[install_office]="y"
else
    CONFIG[install_office]="n"
fi

# Graphics and multimedia
if confirmation_y_or_n "Do you want to install graphics and multimedia software?" install_graphics "false"; then
    CONFIG[install_graphics]="y"
else
    CONFIG[install_graphics]="n"
fi

# Graphics drivers
if lspci | grep -i "nvidia" > /dev/null; then
    if confirmation_y_or_n "NVIDIA graphics card detected. Do you want to install NVIDIA drivers?" install_nvidia "false"; then
        CONFIG[install_nvidia]="y"
    else
        CONFIG[install_nvidia]="n"
    fi
else
    CONFIG[install_nvidia]="n"
fi

if lspci | grep -i "amd" > /dev/null; then
    if confirmation_y_or_n "AMD graphics card detected. Do you want to install AMD drivers?" install_amd "false"; then
        CONFIG[install_amd]="y"
    else
        CONFIG[install_amd]="n"
    fi
else
    CONFIG[install_amd]="n"
fi

if lspci | grep -i "intel" > /dev/null; then
    if confirmation_y_or_n "Intel graphics card detected. Do you want to install Intel drivers?" install_intel "false"; then
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
if ! save_config; then
    print_failed "Failed to save configuration. Aborting."
    exit 1
fi
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

if ! read -p "To confirm, please type exactly: 'yes, format $DEVICE': " -r confirmation_text </dev/tty; then
    echo
    print_failed "Could not read from terminal. Aborting."
    exit 1
fi
echo

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
            dkms_output=$(dkms autoinstall 2>&1) || dkms_status=$?
            dkms_status=${dkms_status:-0}
            if [[ $dkms_status -ne 0 ]]; then
                print_warn "DKMS build failed (exit code: $dkms_status). bcachefs may not be available in this environment."
                print_warn "Note: bcachefs kernel module requires kernel source matching live environment."
            fi
        fi
        
        # Attempt to load bcachefs module with diagnostic info
        if ! modprobe bcachefs 2>/dev/null; then
            modprobe_err=$(modprobe bcachefs 2>&1 || true)
            print_warn "Could not load bcachefs module"
            print_warn "Reason: $modprobe_err"
            print_warn "Falling back to ext4 filesystem"
            CONFIG[filesystem_type]="ext4"
            save_config
        else
            print_success "bcachefs module loaded successfully"
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
cp "../stages/stage2.sh" "$STAGE2_SCRIPT"
chmod +x "$STAGE2_SCRIPT"

# Copy library files
LIB_TARGET="${CONFIG[mount_point]}/persistent/arch_root/usr/local/lib/archgate"
mkdir -p "$LIB_TARGET"
cp "$LIB_DIR"/*.sh "$LIB_TARGET/" 2>/dev/null || {
    print_warn "Some library files may not have been copied"
}
chmod 644 "$LIB_TARGET"/*.sh 2>/dev/null || true

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

