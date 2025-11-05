#!/bin/bash

# Detect color support
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        # Terminal supports colors
        R="\033[0;31m"     # Red
        G="\033[0;32m"     # Green 
        Y="\033[0;33m"     # Yellow
        B="\033[0;34m"     # Blue
        C="\033[0;36m"     # Cyan
        BOLD="\033[1m"     # Bold
        NC="\033[0m"       # Reset
    else
        # Terminal supports colors
        R=""
        G=""
        Y=""
        B=""
        C=""
        BOLD=""
        NC=""
    fi
else
    # Output to file or pipe
    R=""
    G=""
    Y=""
    B=""
    C=""
    BOLD=""
    NC=""
fi

# Helper functions for displaying messages
function print_msg() {
    local msg="$1"
    echo -e "${R}[${C}-${R}]${B} $msg ${NC}"
}

function print_success() {
    local msg="$1"
    echo -e "${R}[${G}✓${R}]${G} $msg ${NC}"
}

function print_failed() {
    local msg="$1"
    echo -e "${R}[${R}☓${R}]${R} $msg ${NC}"
}

function print_warn() {
    local msg="$1"
    echo -e "${R}[${Y}!${R}]${Y} $msg ${NC}"
}

# Function for safely deleting files
function check_and_delete() {
    local files_folders
    for files_folders in "$@"; do
        if [[ -e "$files_folders" ]]; then
            rm -rf "$files_folders" && print_success "Deleted: $files_folders" || print_failed "Error deleting: $files_folders"
        fi
    done
}

# Function for creating backups
function check_and_backup() {
    local files_folders
    local date_str
    date_str=$(date +"%d-%m-%Y")
    
    for files_folders in "$@"; do
        if [[ -e "$files_folders" ]]; then
            local backup="${files_folders}-${date_str}.bak"
            if mv "$files_folders" "$backup"; then
                print_success "Backup created: $backup"
            else
                print_failed "Error creating backup: $files_folders"
            fi
        fi
    done
}

# Function for user confirmation
function confirmation_y_or_n() {
    while true; do
        print_msg "$1 (y/n)"
    read -r response
    response="${response,,}"
        
        case $response in
            y|yes) 
                print_success "Continue with the answer: \"Yes\""
                # Safely assign the response to the caller's variable name without using eval
                if [ -n "${2:-}" ]; then
                    # Use printf -v (bash builtin) to assign to variable by name
                    printf -v "$2" '%s' "$response"
                fi
                return 0
                ;;
            n|no)
                print_msg "Operation cancelled"
                if [ -n "${2:-}" ]; then
                    printf -v "$2" '%s' "$response"
                fi
                return 1
                ;;
            *) 
                print_failed "Invalid input. Please enter 'y' or 'n'"
                ;;
        esac
    done
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_failed "This script must be run with root access"
    exit 1
fi

# Start installation
print_msg "Starting the process of installing Arch Linux on USB..."

# Display available disks
print_msg "Available disks:"
lsblk
echo

# Request USB drive confirmation
print_msg "Please enter the USB drive path (e.g., /dev/sdX):"
read -r USB_DRIVE

# Check drive exists
if [[ ! -b "$USB_DRIVE" ]]; then
    print_failed "Error: $USB_DRIVE is not a valid block device"
    exit 1
fi

# Display selected disk information
print_warn "Selected drive information:"
lsblk -f "$USB_DRIVE"
echo
print_warn "Current mount points:"
findmnt "$USB_DRIVE"* 2>/dev/null || echo "No mounted partitions found"
echo

# First warning - General confirmation
confirmation_y_or_n "⚠️ WARNING: Are you sure you want to format $USB_DRIVE? This operation will PERMANENTLY DELETE all data!" confirm1

if [[ "$confirm1" != "y" ]]; then
    print_failed "Operation cancelled at first confirmation"
    exit 1
fi

# Second warning - Requires specific phrase
echo
print_warn "⚠️ FINAL WARNING! This is a destructive operation and cannot be undone!"
print_warn "This will erase ALL DATA on $USB_DRIVE including:"
echo "  - All partitions and their contents"
echo "  - Any operating systems"
echo "  - All personal files and backups"
echo

# Request confirmation phrase
print_warn "To confirm, please type exactly: 'yes, format $USB_DRIVE'"
read -r confirmation_text

if [[ "$confirmation_text" != "yes, format $USB_DRIVE" ]]; then
    print_failed "Operation cancelled: Confirmation text does not match"
    exit 1
fi

print_success "Both confirmations received. Proceeding with format..."
echo

# Clean and partition
print_msg "Cleaning and partitioning the drive..."
## Perform destructive operations carefully: check return codes and abort on failure
if wipefs -a "${USB_DRIVE}"; then
    print_success "Clean successful"
else
    print_failed "Error cleaning ${USB_DRIVE} with wipefs"
    exit 1
fi

# Use sgdisk with checks after each command
run_sgdisk() {
    local args=("$@")
    local out
    if out=$(sgdisk "${args[@]}" 2>&1); then
        print_success "sgdisk ${args[*]} succeeded"
        return 0
    else
        print_failed "sgdisk ${args[*]} failed: ${out}"
        return 1
    fi
}

if ! run_sgdisk --zap-all "${USB_DRIVE}"; then exit 1; fi
if ! run_sgdisk -o "${USB_DRIVE}"; then exit 1; fi
if ! run_sgdisk -n 1:1M:+2M -t 1:ef02 "${USB_DRIVE}"; then exit 1; fi
if ! run_sgdisk -n 2:0:+512M -t 2:ef00 "${USB_DRIVE}"; then exit 1; fi
if ! run_sgdisk -n 3:0:0 -t 3:8300 "${USB_DRIVE}"; then exit 1; fi

print_msg "Final partition table:"
if ! run_sgdisk -p "${USB_DRIVE}"; then
    print_warn "Unable to print partition table with sgdisk, showing lsblk instead"
    lsblk "${USB_DRIVE}"
else
    lsblk "${USB_DRIVE}"
fi

# --- New section: Live environment preparation ---
print_msg "Preparing the live environment..."
print_warn "This step requires an active internet connection."

# Check internet connection
if ! ping -c 1 archlinux.org &>/dev/null; then
    print_failed "No internet connection detected. Please connect to the internet first."
    exit 1
fi

# Update entire live system
print_msg "Updating the live system..."
print_warn "This may take a while, please be patient..."

# Update package keys
print_msg "Refreshing package keys..."
pacman-key --init
pacman-key --populate archlinux

# Update repository list and entire system
print_msg "Updating package repositories and system packages..."
if ! pacman -Syu --noconfirm; then
    print_failed "Failed to update the live system"
    exit 1
fi
print_success "Live system successfully updated"

# Install tools and DKMS module for bcachefs
print_msg "Installing bcachefs-tools, dkms, and kernel headers..."
pacman -S --noconfirm --needed bcachefs-tools dkms linux-headers || {
    print_failed "Failed to install required packages"
    exit 1
}

# Check if bcachefs module already exists
if ! modprobe bcachefs &>/dev/null; then
    print_msg "bcachefs module not found. Building with DKMS..."
    
    # Install bcachefs module using dkms
    if pacman -S --noconfirm bcachefs-dkms; then
        print_success "bcachefs-dkms package installed"
        
        # Run dkms manually to ensure module installation
        dkms autoinstall || {
            print_failed "DKMS module installation failed"
            exit 1
        }
        
        # Load the new module
        modprobe bcachefs || {
            print_failed "Failed to load bcachefs module even after DKMS installation"
            print_warn "You might need to use a different filesystem like F2FS or ext4"
            exit 1
        }
    else
        print_failed "Failed to install bcachefs-dkms package"
        exit 1
    fi
    print_success "bcachefs module successfully loaded"
else
    print_success "bcachefs module is already available in the kernel"
fi
# --- پایان بخش جدید ---

# Format partitions
print_msg "Formatting partitions..."
mkfs.fat -F32 -n ARCH_ESP ${USB_DRIVE}2 && print_success "ESP format successful" || print_failed "Error formatting ESP"

print_msg "Formatting main partition with bcachefs..."
bcachefs format --label ARCH_PERSIST \
    --compression=zstd \
    --foreground_target=ssd \
    --background_target=ssd \
    --replicas=1 \
    --data_checksum=xxhash \
    --metadata_checksum=xxhash \
    --encrypted=none \
    ${USB_DRIVE}3 && print_success "Main partition format successful" || print_failed "Error formatting main partition"

# Mount partitions
print_msg "Mounting partitions..."
mkdir -p /mnt/usb
mount -L ARCH_ESP /mnt/usb
mkdir -p /mnt/usb/persistent
mount -L ARCH_PERSIST /mnt/usb/persistent

print_msg "Mount status:"
lsblk
findmnt /mnt/usb

# Define package groups
BASE_PACKAGES="base linux linux-firmware linux-headers sudo nano git base-devel gcc make zram-generator squashfs-tools erofs-utils bcachefs-tools networkmanager grub efibootmgr mtools dosfstools ntfs-3g"
SYSTEM_TOOLS="htop iotop vmtouch powertop smartmontools hdparm nvme-cli dmidecode zstd lz4 pigz pbzip2 ostree python-gobject python-psutil"
DESKTOP_ENV="hyprland kitty wofi waybar dunst grim slurp xdg-desktop-portal-hyprland pipewire pipewire-pulse wireplumber"
GRAPHICS_BASE="vulkan-icd-loader vulkan-tools mesa-utils libva-utils vdpauinfo"
DEVELOPMENT_TOOLS="code vim neovim python python-pip nodejs npm rust"
OFFICE_SUITE="libreoffice-fresh hunspell hunspell-en_us hunspell-fa"
GRAPHICS_APPS="gimp inkscape blender vlc"
THEMES="noto-fonts ttf-dejavu ttf-liberation ttf-fira-code gnome-themes-extra papirus-icon-theme"

# Request package selection from user
print_msg "=== Software Group Selection ==="
print_msg "Enter 'y' to install or 'n' to skip each software group."
echo "-----------------------------------"

PACKAGES="$BASE_PACKAGES $SYSTEM_TOOLS"

confirmation_y_or_n "Do you want to install the Hyprland desktop environment?" install_desktop
if [[ "$install_desktop" == "y" ]]; then
    PACKAGES="$PACKAGES $DESKTOP_ENV $GRAPHICS_BASE $THEMES"
fi

confirmation_y_or_n "Do you want to install development tools?" install_dev
if [[ "$install_dev" == "y" ]]; then
    PACKAGES="$PACKAGES $DEVELOPMENT_TOOLS"
fi

confirmation_y_or_n "Do you want to install office software suite?" install_office
if [[ "$install_office" == "y" ]]; then
    PACKAGES="$PACKAGES $OFFICE_SUITE"
fi

confirmation_y_or_n "Do you want to install graphics and multimedia software?" install_graphics
if [[ "$install_graphics" == "y" ]]; then
    PACKAGES="$PACKAGES $GRAPHICS_APPS"
fi

# Detect graphics card and install drivers
if lspci | grep -i "nvidia" > /dev/null; then
    confirmation_y_or_n "NVIDIA graphics card detected. Do you want to install NVIDIA drivers?" install_nvidia
    if [[ "$install_nvidia" == "y" ]]; then
        PACKAGES="$PACKAGES nvidia-dkms nvidia-utils nvidia-settings"
    fi
fi

if lspci | grep -i "amd" > /dev/null; then
    confirmation_y_or_n "AMD graphics card detected. Do you want to install AMD drivers?" install_amd
    if [[ "$install_amd" == "y" ]]; then
        PACKAGES="$PACKAGES xf86-video-amdgpu vulkan-radeon"
    fi
fi

if lspci | grep -i "intel" > /dev/null; then
    confirmation_y_or_n "Intel graphics card detected. Do you want to install Intel drivers?" install_intel
    if [[ "$install_intel" == "y" ]]; then
        PACKAGES="$PACKAGES xf86-video-intel vulkan-intel intel-media-driver intel-gpu-tools"
    fi
fi

# Check Live environment kernel version
LIVE_KERNEL_VERSION=$(uname -r)
print_msg "Live Environment Kernel Version: $LIVE_KERNEL_VERSION"

# Install base system
print_msg "Installing base Arch Linux system..."
mkdir -p /mnt/usb/persistent/arch_root

print_msg "Installing selected packages..."
# Use -k to maintain same kernel version as Live environment
pacstrap -c -k /mnt/usb/persistent/arch_root $PACKAGES

# Check installed kernel version
INSTALLED_KERNEL_VERSION=$(chroot /mnt/usb/persistent/arch_root pacman -Q linux | awk '{print $2}' | sed 's/\.arch.*/.x86_64/')
print_msg "Installed Kernel Version: $INSTALLED_KERNEL_VERSION"

# Ensure version consistency
if [[ "$LIVE_KERNEL_VERSION" != "$INSTALLED_KERNEL_VERSION" ]]; then
    print_warn "Warning: Kernel version mismatch detected!"
    print_warn "Live: $LIVE_KERNEL_VERSION"
    print_warn "Installed: $INSTALLED_KERNEL_VERSION"
    
    # Install matching Live environment version if needed
    if confirmation_y_or_n "Do you want to install the Live environment kernel version?" install_live_kernel; then
        pacstrap -c /mnt/usb/persistent/arch_root linux-$(echo $LIVE_KERNEL_VERSION | cut -d'.' -f1-2)
        print_success "Kernel version synchronized with Live environment"
    else
        print_warn "Continuing with different kernel versions. mkinitcpio might need manual adjustment."
    fi
fi

# Function to run mkinitcpio with specific kernel version
run_mkinitcpio() {
    local kernel_version="$1"
    print_msg "Running mkinitcpio for kernel version $kernel_version"
    
    arch-chroot /mnt/usb/persistent/arch_root /bin/bash -c "mkinitcpio --kernel $kernel_version -P" || {
        print_failed "mkinitcpio failed for kernel version $kernel_version"
        if confirmation_y_or_n "Do you want to retry with default settings?" retry_default; then
            print_msg "Retrying with default settings..."
            arch-chroot /mnt/usb/persistent/arch_root /bin/bash -c "mkinitcpio -P"
        else
            return 1
        fi
    }
    return 0
}

# Run mkinitcpio with correct kernel version
if ! run_mkinitcpio "$INSTALLED_KERNEL_VERSION"; then
    print_failed "Failed to generate initramfs"
    print_warn "System might not boot properly!"
    if ! confirmation_y_or_n "Do you want to continue?" continue_anyway; then
        print_failed "Installation aborted by user"
        exit 1
    fi
fi

print_msg "Generating fstab..."
genfstab -U /mnt/usb/persistent/arch_root >> /mnt/usb/persistent/arch_root/etc/fstab


cat > /mnt/usb/persistent/arch_root/setup.sh <<'EOF'
#!/bin/bash
ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
# Get system hostname
print_msg "Enter system hostname (default: arch-usb):"
read -r HOSTNAME
HOSTNAME="\${HOSTNAME:-arch-usb}"
echo "\$HOSTNAME" > /etc/hostname

# Get and set root password
while true; do
    print_msg "Enter root password:"
    read -r -s ROOT_PASSWORD
    echo
    print_msg "Confirm root password:"
    read -r -s ROOT_PASSWORD_CONFIRM
    echo
    
    if [[ "\$ROOT_PASSWORD" == "\$ROOT_PASSWORD_CONFIRM" ]]; then
        if [[ -z "\$ROOT_PASSWORD" ]]; then
            print_warn "Password cannot be empty. Please try again."
            continue
        fi
        echo "root:\$ROOT_PASSWORD" | chpasswd
        break
    else
        print_failed "Passwords do not match. Please try again."
    fi
done

# Get regular user information
while true; do
    print_msg "Enter username for regular user (default: user):"
    read -r USERNAME
    USERNAME="\${USERNAME:-user}"
    
    # Validate username
    if [[ ! "\$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        print_failed "Invalid username. Use only lowercase letters, numbers, - and _"
        continue
    fi
    
    # Check for duplicate username
    if id "\$USERNAME" &>/dev/null; then
        print_failed "Username already exists. Please choose another one."
        continue
    fi
    
    break
done

# Create user
useradd -m -G wheel -s /bin/bash "\$USERNAME"

# Get and set user password
while true; do
    print_msg "Enter password for \$USERNAME:"
    read -r -s USER_PASSWORD
    echo
    print_msg "Confirm password for \$USERNAME:"
    read -r -s USER_PASSWORD_CONFIRM
    echo
    
    if [[ "\$USER_PASSWORD" == "\$USER_PASSWORD_CONFIRM" ]]; then
        if [[ -z "\$USER_PASSWORD" ]]; then
            print_warn "Password cannot be empty. Please try again."
            continue
        fi
        echo "\$USERNAME:\$USER_PASSWORD" | chpasswd
        break
    else
        print_failed "Passwords do not match. Please try again."
    fi
done

# Configure sudo access
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Enable base services
systemctl enable NetworkManager systemd-oomd fstrim.timer

print_success "User accounts configured successfully:
- Hostname: \$HOSTNAME
- Root account configured
- Regular user '\$USERNAME' created with sudo access"

# zram and zswap auto-tuning script
cat > /usr/local/bin/configure-memory <<'MEMCONF'
#!/bin/bash

# Get total RAM in MB
total_mem_mb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')

# Set zram and zswap based on the amount of RAM
if [ $total_mem_mb -le 2048 ]; then
    # Systems with low RAM (2GB or less)
    zram_fraction=0.25
    max_zram_mb=512
    zswap_enabled=0
    swappiness=100
    zswap_max_pool=10
    zswap_compressor="lz4"
elif [ $total_mem_mb -le 4096 ]; then
    # Systems with medium RAM (2GB-4GB)
    zram_fraction=0.30
    max_zram_mb=1024
    zswap_enabled=1
    swappiness=80
    zswap_max_pool=15
    zswap_compressor="zstd"
elif [ $total_mem_mb -le 8192 ]; then
    # Systems with high RAM (4GB-8GB)
    zram_fraction=0.35
    max_zram_mb=2048
    zswap_enabled=1
    swappiness=60
    zswap_max_pool=20
    zswap_compressor="zstd"
else
    # Systems with very high RAM (>8GB)
    zram_fraction=0.40
    max_zram_mb=4096
    zswap_enabled=1
    swappiness=40
    zswap_max_pool=25
    zswap_compressor="zstd"
fi

# Calculate zram size based on percentage
calculated_zram=$((total_mem_mb * zram_fraction))
if [ $calculated_zram -gt $max_zram_mb ]; then
    final_zram=$max_zram_mb
else
    final_zram=$calculated_zram
fi

# Configure zram
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
compression-algorithm=zstd
zram-fraction=$zram_fraction
max-zram-size=$final_zram
EOF

# Configure kernel parameters for memory based on system profile
cat > /etc/sysctl.d/99-memory.conf <<EOF
# Basic memory and swap settings
vm.swappiness=$swappiness

# I/O and cache settings for USB
vm.vfs_cache_pressure=200                    # Reduce cache pressure to preserve USB life
vm.dirty_ratio=10                            # Maximum 10% of memory for dirty data
vm.dirty_background_ratio=5                  # Start writing in the background at 5%
vm.dirty_expire_centisecs=3000               # Expire dirty data after 30 seconds
vm.dirty_writeback_centisecs=500             # Check dirty data every 5 seconds

# Memory optimization settings
vm.page-cluster=0                            # Disable page clustering
vm.compaction_proactiveness=1                # Enable proactive memory compaction
vm.min_free_kbytes=$((64 * 1024))           # Minimum 64MB of free memory
vm.watermark_boost_factor=15000              # Increase threshold for OOM-killer

# USB/SSD specific settings
vm.laptop_mode=0                             # Disable laptop mode for USB
vm.mmap_min_addr=65536                       # Increase security
vm.oom_kill_allocating_task=1                # Kill allocating task on OOM
vm.overcommit_ratio=50                       # Allow balanced overcommit
vm.overcommit_memory=0                       # Smart overcommit algorithm

# Performance settings
kernel.nmi_watchdog=0                        # Disable watchdog to reduce overhead
kernel.panic=10                              # Automatic reboot after 10 seconds on kernel panic
kernel.panic_on_oops=1                       # Reboot on serious kernel errors

# Network settings for better performance
net.core.rmem_max=16777216                   # Increase receive buffer
net.core.wmem_max=16777216                   # Increase send buffer
net.ipv4.tcp_fastopen=3                      # Enable TCP Fast Open
net.ipv4.tcp_low_latency=1                   # Reduce network latency
EOF

# Additional settings for low RAM systems
if [ $total_mem_mb -le 2048 ]; then
    cat >> /etc/sysctl.d/99-memory.conf <<EOF

# Additional settings for low RAM systems
vm.extfrag_threshold=750                     # Lower threshold for defrag
vm.min_free_kbytes=$((32 * 1024))           # Reduce reserved memory
vm.overcommit_ratio=30                       # More conservative overcommit
EOF
fi

# Additional settings for high RAM systems
if [ $total_mem_mb -gt 8192 ]; then
    cat >> /etc/sysctl.d/99-memory.conf <<EOF

# Additional settings for high RAM systems
vm.min_free_kbytes=$((256 * 1024))          # Increase reserved memory
vm.zone_reclaim_mode=0                       # Disable zone reclaim
vm.overcommit_ratio=80                       # Allow more overcommit
EOF
fi

# Advanced zswap settings in modprobe
cat > /etc/modprobe.d/zswap.conf <<EOF
# Enable ZSWAP
options zswap enabled=$zswap_enabled

# Compression algorithm
options zswap compressor=$zswap_compressor

# Maximum memory percentage for ZSWAP
options zswap max_pool_percent=$zswap_max_pool

# Memory management algorithm
options zswap zpool=z3fold

# Compression threshold (only pages larger than 50KB are compressed)
options zswap threshold=51200
EOF

# Apply settings
sysctl -p /etc/sysctl.d/99-memory.conf
MEMCONF

chmod +x /usr/local/bin/configure-memory

# Create a service to run the script at boot
if [ -e "/etc/systemd/system/configure-memory.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/configure-memory.service"
else
cat > /etc/systemd/system/configure-memory.service <<'MEMSVC'
[Unit]
Description=Configure Memory Management Parameters
After=local-fs.target
Before=zram-generator.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-memory
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
MEMSVC
fi

# Enable services
systemctl enable configure-memory.service
systemctl enable zram-generator

# Configure journald to preserve USB space
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/volatile.conf <<JCONF
[Journal]
Storage=volatile
RuntimeMaxUse=64M
JCONF

# USB health check script
cat > /usr/local/bin/check-usb-health <<'CHK'
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
CHK
chmod +x /usr/local/bin/check-usb-health

# Service and timer for USB health check
if [ -e "/etc/systemd/system/usb-health.timer" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/usb-health.timer"
else
cat > /etc/systemd/system/usb-health.timer <<TIMER
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
TIMER
fi

if [ -e "/etc/systemd/system/usb-health.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/usb-health.service"
else
cat > /etc/systemd/system/usb-health.service <<SVC
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
SVC
fi

systemctl enable usb-health.timer
cat > /etc/initcpio/hooks/overlay <<HOOK
run_hook() {
    modprobe overlay
    mount_handler() {
        # Create necessary mount points
        mkdir -p /squashfs /os_root

        # Attempt to mount the bcachefs partition
        if ! mount -t bcachefs -o ro /dev/disk/by-label/ARCH_PERSIST /os_root; then
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
mkdir -p /overlay_work
mount -t tmpfs tmpfs /overlay_work
mkdir -p /overlay_work/upper /overlay_work/work
mount -t overlay overlay -o lowerdir=/squashfs,upperdir=/overlay_work/upper,workdir=/overlay_work/work /new_root
mkdir -p /new_root/persistent
mount -o rw,noatime /dev/disk/by-label/ARCH_PERSIST /new_root/persistent
rm -rf /new_root/home
ln -sf /persistent/home /new_root/home
mkdir -p /new_root/persistent/home/user

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

cp -a /etc/skel/. /new_root/persistent/home/user 2>/dev/null || true
    chown -R user:user /new_root/persistent/home/user

    # Cleanup pacman cache to reduce final size
    rm -rf /new_root/var/cache/pacman/pkg/*
    }
}
HOOK
cat > /etc/initcpio/install/overlay <<INST
build() { add_module overlay; add_runscript; }
INST
 sed -i 's/^MODULES=(.*)/MODULES=(overlay squashfs erofs bcachefs \1)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.filesystems.)/HOOKS=\1 overlay/' /etc/mkinitcpio.conf

# Check and enable LZ4HC support in erofs
if ! grep -q "CONFIG_EROFS_FS_LZ4HC=y" /boot/config-$(uname -r); then
    echo "Warning: This kernel might not support LZ4HC compression in erofs."
    echo "Consider rebuilding kernel with CONFIG_EROFS_FS_LZ4HC=y"
fi


mkinitcpio -P
EOF

chmod +x /tmp/arch_root/setup.sh
arch-chroot /tmp/arch_root /setup.sh

# =======================================================
#  (Safety and Recovery)
# =======================================================
print_msg "Injecting Advanced Safety scripts (003)..."

# Execute commands in the chroot environment
arch-chroot /tmp/arch_root /bin/bash <<'CHROOT_003'

# 1. Implement mandatory fsync system for critical writes
cat > /usr/local/bin/enforced-sync <<'EOF'
#!/bin/bash
# For critical operations, enforce fsync
sync
[ -w "/sys/block/*/queue/rotational" ] && echo 0 > /sys/block/*/queue/rotational 2>/dev/null || true
EOF
chmod +x /usr/local/bin/enforced-sync

# Periodic sync service
if [ -e "/etc/systemd/system/periodic-sync.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/periodic-sync.service"
else
cat > /etc/systemd/system/periodic-sync.service <<EOF
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
fi

if [ -e "/etc/systemd/system/periodic-sync.timer" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/periodic-sync.timer"
else
cat > /etc/systemd/system/periodic-sync.timer <<EOF
[Unit]
Description=Periodic filesystem sync every 5 minutes
Requires=periodic-sync.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi

systemctl enable periodic-sync.timer

# 2. Error detection system and automatic switch to Read-Only mode
cat > /usr/local/bin/io-health-monitor <<'EOF'
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
    for dev in $(findmnt -n -o SOURCE /persistent); do
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

chmod +x /usr/local/bin/io-health-monitor

# I/O health monitoring service
if [ -e "/etc/systemd/system/io-health-monitor.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/io-health-monitor.service"
else
cat > /etc/systemd/system/io-health-monitor.service <<EOF
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
fi

systemctl enable io-health-monitor.service

# 3. Implementing Fallback (Busybox) Mode for Troubleshooting
pacman -S --noconfirm busybox

# Creating custom initramfs fallback
cat > /etc/mkinitcpio.conf.fallback <<'EOF'
MODULES=(overlay squashfs)
BINARIES=(busybox)
FILES=()
HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)
COMPRESSION="zstd"
EOF

# ساخت initramfs fallback
mkinitcpio -c /etc/mkinitcpio.conf.fallback -g /boot/initramfs-linux-fallback.img

# 4. Automatic recovery and snapshot system
cat > /usr/local/bin/create-system-snapshot <<'EOF'
#!/bin/bash
SNAPSHOT_DIR="/persistent/snapshots"
DATE=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="system-snapshot-$DATE"

echo "Creating system snapshot: $SNAPSHOT_NAME"

mkdir -p $SNAPSHOT_DIR/$SNAPSHOT_NAME

# Copy important configuration files
cp -a /etc $SNAPSHOT_DIR/$SNAPSHOT_NAME/
cp -a /var/lib $SNAPSHOT_DIR/$SNAPSHOT_NAME/ 2>/dev/null || true

# Create archive of package status
pacman -Q > $SNAPSHOT_DIR/$SNAPSHOT_NAME/installed-packages.list

# Compress snapshot
tar -czf $SNAPSHOT_DIR/$SNAPSHOT_NAME.tar.gz -C $SNAPSHOT_DIR $SNAPSHOT_NAME
rm -rf $SNAPSHOT_DIR/$SNAPSHOT_NAME

echo "Snapshot created: $SNAPSHOT_DIR/$SNAPSHOT_NAME.tar.gz"
EOF

chmod +x /usr/local/bin/create-system-snapshot

# Periodic snapshot service
if [ -e "/etc/systemd/system/system-snapshot.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/system-snapshot.service"
else
cat > /etc/systemd/system/system-snapshot.service <<EOF
[Unit]
Description=Create system snapshot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/create-system-snapshot
User=root
EOF
fi

if [ -e "/etc/systemd/system/system-snapshot.timer" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/system-snapshot.timer"
else
cat > /etc/systemd/system/system-snapshot.timer <<EOF
[Unit]
Description=Daily system snapshot
Requires=system-snapshot.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi

systemctl enable system-snapshot.timer

# 5. Advanced monitoring and local telemetry system
cat > /usr/local/bin/performance-telemetry <<'EOF'
#!/bin/bash
TELEMETRY_DIR="/persistent/telemetry"
METRICS_FILE="$TELEMETRY_DIR/performance-metrics.csv"

mkdir -p $TELEMETRY_DIR

# Create header if file does not exist
if [ ! -f "$METRICS_FILE" ]; then
    echo "timestamp,io_operations,rollback_count,ram_usage,swap_usage,boot_time" > $METRICS_FILE
fi

collect_metrics() {
    local timestamp=$(date +%s)
    local io_ops=$(cat /sys/block/*/stat | awk '{sum+=$1} END {print sum}')
    local rollback_count=$(journalctl -u system-update --since="1 hour ago" | grep -c "rollback")
    local ram_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}')
    local swap_usage=$(free -m | awk 'NR==3{printf "%.2f", $3*100/$2}')
    local boot_time=$(systemd-analyze | awk '/Startup/ {print $3}' | tr -d 's')
    
    echo "$timestamp,$io_ops,$rollback_count,$ram_usage,$swap_usage,$boot_time" >> $METRICS_FILE
}

collect_metrics
EOF

chmod +x /usr/local/bin/performance-telemetry

# Telemetry service
if [ -e "/etc/systemd/system/performance-telemetry.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/performance-telemetry.service"
else
cat > /etc/systemd/system/performance-telemetry.service <<EOF
[Unit]
Description=Performance telemetry collection
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/performance-telemetry
User=root
EOF
fi

if [ -e "/etc/systemd/system/performance-telemetry.timer" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/performance-telemetry.timer"
else
cat > /etc/systemd/system/performance-telemetry.timer <<EOF
[Unit]
Description=Collect performance metrics every hour
Requires=performance-telemetry.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi

systemctl enable performance-telemetry.timer

# 6. سیستم تشخیص قطع برق و بازیابی
cat > /usr/local/bin/power-failure-detector <<'EOF'
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
    echo "$(date): Power failure detected! Initiating safe shutdown..." >> $LOG_FILE
    logger -t power-manager "Power failure detected - emergency procedures activated"
    
    /usr/local/bin/enforced-sync
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

chmod +x /usr/local/bin/power-failure-detector

# Power failure detection service
if [ -e "/etc/systemd/system/power-failure-detector.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/power-failure-detector.service"
else
cat > /etc/systemd/system/power-failure-detector.service <<EOF
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
fi

systemctl enable power-failure-detector.service

# Restart mkinitcpio to ensure changes are applied
mkinitcpio -P

CHROOT_003
print_success "Advanced Safety scripts (003) injected successfully"

# =======================================================
# (atomic update system)
# =======================================================
print_msg "Injecting Atomic Update System (004)..."

arch-chroot /tmp/arch_root /bin/bash <<'CHROOT_004'

# Create directory structure for system updates
mkdir -p /var/lib/system-update/{staging,backup,transactions}
mkdir -p /etc/system-update/profile

# Main script for atomic updates
cat > /usr/local/bin/atomic-update-manager <<'EOF'
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
    echo "$(date): $1" >> $LOG_FILE
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
    /usr/local/bin/enforced-sync

    # Mark transaction as committed
    echo "committed" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
    echo "$(date)" > "$TRANSACTION_DIR/$TRANSACTION_ID/commit_time"
    
    log "Transaction $TRANSACTION_ID successfully committed"
}

# Rollback transaction function
rollback_transaction() {
    log "Rolling back transaction $TRANSACTION_ID"

    # Restore previous files from backup
    if [ -f "${ESP_MOUNT}/arch/vmlinuz-linux.old" ] && [ -f "${ESP_MOUNT}/arch/initramfs-linux.img.old" ]; then
        # Remove problematic versions
        rm -f "${ESP_MOUNT}/arch/vmlinuz-linux"
        rm -f "${ESP_MOUNT}/arch/initramfs-linux.img"
        
        # بازگرداندن نسخه‌های قبلی
        mv "${ESP_MOUNT}/arch/vmlinuz-linux.old" "${ESP_MOUNT}/arch/vmlinuz-linux"
        mv "${ESP_MOUNT}/arch/initramfs-linux.img.old" "${ESP_MOUNT}/arch/initramfs-linux.img"
        
        # کپی به پارتیشن پایدار برای نگهداری
        cp "${ESP_MOUNT}/arch/vmlinuz-linux" "/persistent/arch/"
        cp "${ESP_MOUNT}/arch/initramfs-linux.img" "/persistent/arch/"
        
        # اجرای sync برای اطمینان از نوشته شدن تغییرات
        sync
        /usr/local/bin/enforced-sync
    else
        log "Error: Backup kernel files not found in ESP"
        return 1
    fi
    
    # حذف فایل‌های staging
    rm -rf "$STAGING_ROOT"
    
    echo "rolledback" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
    log "Transaction $TRANSACTION_ID rolled back"
    
    # sync اجباری بعد از rollback
    sync
    /usr/local/bin/enforced-sync
}

# تابع به‌روزرسانی پکیج‌ها در محیط chroot
update_packages() {
    local CHROOT_DIR="$1"
    local LOG_FILE="$2"
    
    log "Updating packages in chroot environment"
    arch-chroot "$CHROOT_DIR" /bin/bash -c "
        # بروزرسانی پکیج‌ها
        pacman -Syu --noconfirm 2>&1 || exit 1
        # اجرای مجدد mkinitcpio برای هسته جدید
        mkinitcpio -P 2>&1 || exit 1
    " >> "$LOG_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        error_exit "Package update failed in chroot"
    fi
}

# تابع به‌روزرسانی سیستم‌عامل با پشتیبانی از squashfs
update_system() {
    # مسیرهای اصلی برای فایل‌های سیستمی
    mkdir -p "/persistent/arch"
    local NEW_SQUASHFS="/persistent/arch/root.squashfs.new"
    local OLD_SQUASHFS="/persistent/arch/root.squashfs"
    local OLD_SQUASHFS_BACKUP="${BACKUP_DIR}/root.squashfs.$(date +%Y%m%d-%H%M%S)"
    ESP_MOUNT="/boot"
    mkdir -p "${ESP_MOUNT}/arch"

    begin_transaction
    
    log "Starting system update process"
    
    # ایجاد محیط staging
    rm -rf "$STAGING_ROOT"
    mkdir -p "$STAGING_ROOT"
    
    # کپی سیستم فعلی به محیط staging
    log "Copying current system to staging environment"
    cp -a /squashfs/. "$STAGING_ROOT/"
    
    # به‌روزرسانی در محیط staging
    update_packages "$STAGING_ROOT" "$LOG_FILE"
    
    # ایجاد فایل squashfs جدید
    log "Creating new squashfs image"
    mkdir -p "$(dirname "$NEW_SQUASHFS")"
    if modprobe erofs &>/dev/null; then
        log "Using erofs with LZ4HC compression"
        mkfs.erofs -zlz4hc,12 --uid-offset=0 --gid-offset=0 \
            --mount-point=/ --exclude-path="/tmp/*" \
            "$NEW_SQUASHFS" "$STAGING_ROOT"
    else
        log "Using squashfs with ZSTD compression"
        mksquashfs "$STAGING_ROOT" "$NEW_SQUASHFS" \
            -comp zstd -Xcompression-level 15 -noappend -processors "$(nproc)"
    fi
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to create new squashfs image"
    fi
    
    # بررسی یکپارچگی فایل squashfs جدید
    verify_squashfs_integrity "$NEW_SQUASHFS"
    
    # پشتیبان‌گیری از فایل قدیمی
    mkdir -p "$BACKUP_DIR"
    cp "$OLD_SQUASHFS" "$OLD_SQUASHFS_BACKUP"
    
    # بررسی یکپارچگی فایل پشتیبان
    verify_squashfs_integrity "$OLD_SQUASHFS_BACKUP"
    
    # جایگزینی فایل‌ها با حفظ نسخه‌های قدیمی
    mv "$OLD_SQUASHFS" "${OLD_SQUASHFS}.old"
    mv "$NEW_SQUASHFS" "$OLD_SQUASHFS"
    
    # پاکسازی فایل‌های قدیمی از ESP
    rm -f "${ESP_MOUNT}/arch/"*.old
    
    # پشتیبان‌گیری از کرنل و initramfs فعلی در ESP
    for file in vmlinuz-linux initramfs-linux.img; do
        if [ -f "${ESP_MOUNT}/arch/$file" ]; then
            mv "${ESP_MOUNT}/arch/$file" "${ESP_MOUNT}/arch/$file.old"
        fi
    done

    # کپی کرنل و initramfs جدید به ESP
    cp "${STAGING_ROOT}/boot/vmlinuz-linux" "${ESP_MOUNT}/arch/"
    cp "${STAGING_ROOT}/boot/initramfs-linux.img" "${ESP_MOUNT}/arch/"
    
    # کپی کرنل و initramfs به پارتیشن پایدار
    cp "${STAGING_ROOT}/boot/vmlinuz-linux" "/persistent/arch/"
    cp "${STAGING_ROOT}/boot/initramfs-linux.img" "/persistent/arch/"
    
    # اجرای sync برای اطمینان از نوشته شدن تغییرات
    sync
    /usr/local/bin/enforced-sync
    
    # پاکسازی
    rm -rf "$STAGING_ROOT"
    sync
    
    commit_transaction
    log "System update completed successfully. Reboot recommended."
}

# مدیریت آرگومان‌ها
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

chmod +x /usr/local/bin/atomic-update-manager

# سرویس مدیریت به‌روزرسانی
if [ -e "/etc/systemd/system/atomic-update.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/atomic-update.service"
else
cat > /etc/systemd/system/atomic-update.service <<EOF
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
fi

# تایمر به‌روزرسانی خودکار هفتگی
if [ -e "/etc/systemd/system/atomic-update.timer" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/atomic-update.timer"
else
cat > /etc/systemd/system/atomic-update.timer <<EOF
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
fi

systemctl enable atomic-update.timer

# اسکریپت ایجاد snapshot اتمی
cat > /usr/local/bin/atomic-snapshot <<'EOF'
#!/bin/bash
set -euo pipefail

SNAPSHOT_BASE="/persistent/snapshots"
DATE=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="atomic-snapshot-$DATE"
SNAPSHOT_DIR="$SNAPSHOT_BASE/$SNAPSHOT_NAME"
MAX_SNAPSHOTS=5  # تعداد اسنپ‌شات‌هایی که باید نگهداری شوند
LOG_FILE="/var/log/atomic-snapshots.log"

log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# تابع چرخش (rotation) اسنپ‌شات‌ها
rotate_snapshots() {
    local count=$(find "$SNAPSHOT_BASE" -name "atomic-snapshot-*.tar.gz" | wc -l)
    log "Current snapshot count: $count"
    
    if [ "$count" -gt "$MAX_SNAPSHOTS" ]; then
        log "Rotating snapshots (keeping last $MAX_SNAPSHOTS)"
        local excess=$((count - MAX_SNAPSHOTS))
        
        # حذف قدیمی‌ترین اسنپ‌شات‌ها
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
    
    # توقف سرویس‌های حیاتی برای یکنواختی snapshot
    systemctl stop io-health-monitor.service 2>/dev/null || true
    systemctl stop power-failure-detector.service 2>/dev/null || true
    
    # sync اجباری
    sync
    /usr/local/bin/enforced-sync
    
    # ایجاد دایرکتوری snapshot
    mkdir -p "$SNAPSHOT_DIR"
    
    # کپی فایل‌های سیستم حیاتی
    cp -a /etc "$SNAPSHOT_DIR/"
    cp -a /var/lib/pacman "$SNAPSHOT_DIR/" 2>/dev/null || true
    cp -a /boot "$SNAPSHOT_DIR/" 2>/dev/null || true
    
    # وضعیت پکیج‌ها
    pacman -Q > "$SNAPSHOT_DIR/installed-packages.list"
    
    # اطلاعات تراکنش‌ها
    cp -a /var/lib/system-update/transactions "$SNAPSHOT_DIR/" 2>/dev/null || true
    
    # راه‌اندازی مجدد سرویس‌ها
    systemctl start io-health-monitor.service 2>/dev/null || true
    systemctl start power-failure-detector.service 2>/dev/null || true
    
    # فشرده‌سازی snapshot
    tar -czf "$SNAPSHOT_DIR.tar.gz" -C "$SNAPSHOT_BASE" "$SNAPSHOT_NAME"
    rm -rf "$SNAPSHOT_DIR"
    
    log "Atomic snapshot created: $SNAPSHOT_DIR.tar.gz"
    
    # اجرای چرخش اسنپ‌شات‌ها بعد از ایجاد اسنپ‌شات جدید
    rotate_snapshots
}

# تابع نمایش اطلاعات اسنپ‌شات‌ها
show_snapshots_info() {
    echo "Snapshot Information:"
    echo "===================="
    echo "Maximum snapshots kept: $MAX_SNAPSHOTS"
    echo "Snapshot location: $SNAPSHOT_BASE"
    echo
    echo "Current snapshots:"
    if [ -d "$SNAPSHOT_BASE" ]; then
        find "$SNAPSHOT_BASE" -name "atomic-snapshot-*.tar.gz" -type f -printf "%T@ %p\n" | \
            sort -rn | \
            cut -d' ' -f2- | \
            while read -r snapshot; do
                local size=$(du -h "$snapshot" | cut -f1)
                local date=$(date -r "$snapshot" "+%Y-%m-%d %H:%M:%S")
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
        if [ -z "${2:-}" ]; then
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

chmod +x /usr/local/bin/atomic-snapshot

# اسکریپت بازیابی اتمی
cat > /usr/local/bin/atomic-recovery <<'EOF'
#!/bin/bash
set -euo pipefail

SNAPSHOT_BASE="/persistent/snapshots"

list_snapshots() {
    find "$SNAPSHOT_BASE" -name "*.tar.gz" -type f | sort -r
}

recover_from_snapshot() {
    local snapshot_file="$1"
    local temp_dir="/tmp/snapshot-recovery"
    
    echo "Starting recovery from snapshot: $snapshot_file"
    
    # استخراج snapshot
    mkdir -p "$temp_dir"
    tar -xzf "$snapshot_file" -C "$temp_dir"
    
    local snapshot_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "atomic-snapshot-*" | head -1)
    
    if [ -z "$snapshot_dir" ]; then
        echo "Error: Invalid snapshot format"
        return 1
    fi
    
    # بازیابی فایل‌های پیکربندی
    cp -a "$snapshot_dir/etc"/* /etc/ 2>/dev/null || true
    
    # بازیابی وضعیت پکیج‌ها (در صورت نیاز)
    if [ -f "$snapshot_dir/installed-packages.list" ]; then
        echo "Snapshot contains package state. Manual package reconciliation may be needed."
    fi
    
    # پاکسازی
    rm -rf "$temp_dir"
    
    echo "Recovery completed. Reboot recommended."
}

case "${1:-}" in
    list)
        list_snapshots
        ;;
    recover)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 recover <snapshot-file>"
            exit 1
        fi
        recover_from_snapshot "$2"
        ;;
    *)
        echo "Usage: $0 {list|recover <snapshot-file>}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/atomic-recovery

# اضافه کردن منوی بازیابی به GRUB
ESP_UUID=$(blkid -s UUID -o value "/dev/disk/by-label/ARCH_ESP")

cat >> /boot/grub/grub.cfg <<EOF

menuentry "Arch Linux USB (Recovery Mode - Read Only)" {
    search --no-floppy --fs-uuid --set=root $ESP_UUID
    linux /arch/vmlinuz-linux systemd.unit=rescue.target single nomodeset systemd.debug-shell=1
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux USB (Snapshot Recovery)" {
    search --no-floppy --fs-uuid --set=root $ESP_UUID
    linux /arch/vmlinuz-linux systemd.unit=multi-user.target single
    initrd /arch/initramfs-linux.img
}
EOF

# اجرای مجدد mkinitcpio برای اطمینان از اعمال تغییرات
mkinitcpio -P

CHROOT_004
print_success "Atomic Update System (004) injected successfully"

# =======================================================
# شروع ادغام فایل 005 (بهینه‌سازی‌های پیشرفته)
# =======================================================
print_msg "Injecting Advanced Optimizations (005)..."

arch-chroot /tmp/arch_root /bin/bash <<'CHROOT_005'

# 1. پیاده‌سازی ZSWAP
cat > /usr/local/bin/configure-zswap <<'EOF'
#!/bin/bash

# دریافت مقدار کل RAM به مگابایت
total_mem_mb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')

# تنظیم پارامترهای ZSWAP بر اساس RAM
if [ $total_mem_mb -le 2048 ]; then
    # سیستم‌های با RAM کم (2GB یا کمتر)
    zswap_enabled=0
    zswap_compressor="lz4"
    zswap_max_pool=10
elif [ $total_mem_mb -le 4096 ]; then
    # سیستم‌های با RAM متوسط (2GB-4GB)
    zswap_enabled=1
    zswap_compressor="zstd"
    zswap_max_pool=15
elif [ $total_mem_mb -le 8192 ]; then
    # سیستم‌های با RAM بالا (4GB-8GB)
    zswap_enabled=1
    zswap_compressor="zstd"
    zswap_max_pool=20
else
    # سیستم‌های با RAM خیلی بالا (>8GB)
    zswap_enabled=1
    zswap_compressor="zstd"
    zswap_max_pool=25
fi

# پیکربندی پارامترهای کرنل برای ZSWAP
cat > /etc/modprobe.d/zswap.conf <<CONF
# فعال‌سازی ZSWAP
options zswap enabled=$zswap_enabled

# الگوریتم فشرده‌سازی
options zswap compressor=$zswap_compressor

# حداکثر درصد حافظه برای ZSWAP
options zswap max_pool_percent=$zswap_max_pool

# الگوریتم مدیریت حافظه
options zswap zpool=z3fold

# آستانه فشرده‌سازی (فقط صفحات بالای 50KB فشرده شوند)
options zswap threshold=51200
CONF

# پیکربندی پارامترهای GRUB
if [ $zswap_enabled -eq 1 ]; then
    # حذف تنظیمات قبلی zswap و اضافه کردن تنظیمات جدید
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=.*zswap/d' /etc/default/grub
    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/& zswap.enabled=$zswap_enabled zswap.compressor=$zswap_compressor zswap.max_pool_percent=$zswap_max_pool zswap.zpool=z3fold /" /etc/default/grub
fi
EOF

chmod +x /usr/local/bin/configure-zswap

# سرویس پیکربندی ZSWAP
if [ -e "/etc/systemd/system/configure-zswap.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/configure-zswap.service"
else
cat > /etc/systemd/system/configure-zswap.service <<EOF
[Unit]
Description=Configure ZSWAP Parameters
After=local-fs.target
Before=swap.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-zswap
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl enable configure-zswap.service

# 2. تنظیمات پیشرفته Bcachefs
cat > /usr/local/bin/optimize-bcachefs <<'EOF'
#!/bin/bash

# تنظیم پارامترهای بهینه‌سازی برای پارتیشن پایدار
bcachefs set-option /dev/disk/by-label/ARCH_PERSIST \
    background_target=ssd \
    background_compression=zstd \
    inodes_32bit=1 \
    gc_after_writeback=1 \
    write_buffer_size=512M \
    journal_flush_delay=1000 \
    fsck_fix_errors=yes

# فعال‌سازی ویژگی‌های پیشرفته کش
bcachefs set-option /dev/disk/by-label/ARCH_PERSIST \
    reflink=1 \
    promote_target=4096 \
    writeback_percentage=20

echo "Bcachefs optimizations applied"
EOF

chmod +x /usr/local/bin/optimize-bcachefs

# سرویس بهینه‌سازی Bcachefs
if [ -e "/etc/systemd/system/bcachefs-optimize.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/bcachefs-optimize.service"
else
cat > /etc/systemd/system/bcachefs-optimize.service <<EOF
[Unit]
Description=Bcachefs Optimizations
DefaultDependencies=no
After=local-fs.target
Before=network.target atomic-update.service
Conflicts=atomic-update.service
ConditionPathExists=/usr/local/bin/optimize-bcachefs
ConditionVirtualization=!container

[Service]
Type=oneshot
ExecStart=/usr/local/bin/optimize-bcachefs
RemainAfterExit=yes
Nice=19
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
TimeoutStartSec=5min
Restart=on-failure
RestartSec=30s

[Install]
WantedBy=sysinit.target
EOF
fi

systemctl enable bcachefs-optimize.service

#3. Smart Prefetch System
cat > /usr/local/bin/smart-prefetch <<'EOF'
#!/bin/bash
PREFETCH_LOG="/var/log/prefetch.log"
PREFETCH_CACHE="/var/cache/prefetch"
APPLICATION_PROFILES="/etc/prefetch/profiles"

# Create directory structure
mkdir -p "$PREFETCH_CACHE" "$APPLICATION_PROFILES"

# Function to analyze application usage
analyze_application_usage() {
    # Collect application usage statistics
    ps aux --sort=-%cpu | head -10 | awk '{print $11}' | sort | uniq > "/tmp/top_processes"

    # Check logs of started services
    journalctl --since="1 hour ago" -t systemd | grep "Started.*service" | \
        awk '{print $8}' | sed 's/\.service//' > "/tmp/recent_services"
}

# Function to prefetch application files
prefetch_application() {
    local app_name="$1"
    local app_profile="$APPLICATION_PROFILES/${app_name}.profile"
    
    if [ -f "$app_profile" ]; then
        echo "Prefetching $app_name using profile..." >> "$PREFETCH_LOG"
        while IFS= read -r file_pattern; do
            [ -z "$file_pattern" ] && continue
            find /usr -type f -path "*$file_pattern*" 2>/dev/null | head -20 | \
                xargs -I {} cat "{}" > /dev/null 2>&1 &
        done < "$app_profile"
    else
        echo "General prefetch for $app_name..." >> "$PREFETCH_LOG"
        local app_files=$(ldd $(which "$app_name" 2>/dev/null) 2>/dev/null | awk '{print $3}' | grep -v null)
        for lib in $app_files; do
            [ -f "$lib" ] && cat "$lib" > /dev/null 2>&1 &
        done
    fi
    wait
}

# Main prefetch function
run_smart_prefetch() {
    echo "$(date): Starting smart prefetch analysis" >> "$PREFETCH_LOG"
    
    analyze_application_usage
    
    while read -r process; do
        [ -z "$process" ] && continue
        local app_name=$(basename "$process")
        prefetch_application "$app_name" &
    done < "/tmp/top_processes"
    
    while read -r service; do
        [ -z "$service" ] && continue
        prefetch_application "$service" &
    done < "/tmp/recent_services"
    
    wait
    echo "$(date): Smart prefetch completed" >> "$PREFETCH_LOG"
}

case "${1:-}" in
    on-login)
        run_smart_prefetch
        ;;
    periodic)
        run_smart_prefetch
        ;;
    *)
        echo "Usage: $0 {on-login|periodic}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/smart-prefetch

# Prefetch profiles for main applications
mkdir -p /etc/prefetch/profiles

cat > /etc/prefetch/profiles/firefox.profile <<'EOF'
libxul.so
libmozjs.so
omni.ja
browser/features
EOF

cat > /etc/prefetch/profiles/hyprland.profile <<'EOF'
libwlroots.so
libhyprland.so
libGL.so
libvulkan.so
EOF

cat > /etc/prefetch/profiles/code.profile <<'EOF'
libnode.so
libffmpeg.so
resources/app
EOF

# Prefetch services
if [ -e "/etc/systemd/system/smart-prefetch.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/smart-prefetch.service"
else
cat > /etc/systemd/system/smart-prefetch.service <<EOF
[Unit]
Description=Smart Application Prefetching
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/smart-prefetch periodic
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

if [ -e "/etc/systemd/system/periodic-sync.timer" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/periodic-sync.timer"
else
cat > /etc/systemd/system/periodic-sync.timer <<EOF
[Unit]
Description=Periodic filesystem sync timer
Requires=periodic-sync.service

[Timer]
OnCalendar=*:0/5
RandomizedDelaySec=30
AccuracySec=1s
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi

systemctl enable smart-prefetch.timer

# 4. Hardware Profiles
cat > /usr/local/bin/hardware-profile-manager <<'EOF'
#!/bin/bash
PROFILE_DIR="/etc/hardware-profiles"
CURRENT_PROFILE="$PROFILE_DIR/current"

detect_cpu_architecture() {
    local cpu_vendor=$(grep vendor_id /proc/cpuinfo | head -1 | awk '{print $3}')
    if [ "$cpu_vendor" = "GenuineIntel" ]; then
        echo "intel"
    elif [ "$cpu_vendor" = "AuthenticAMD" ]; then
        echo "amd"
    else
        echo "generic"
    fi
}

detect_gpu_vendor() {
    if lspci | grep -i "nvidia" > /dev/null; then
        echo "nvidia"
    elif lspci | grep -i "amd" > /dev/null; then
        echo "amd"
    elif lspci | grep -i "intel" > /dev/null; then
        echo "intel"
    else
        echo "generic"
    fi
}

detect_ram_amount() {
    local ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_gb=$((ram_kb / 1024 / 1024))
    
    if [ $ram_gb -lt 4 ]; then
        echo "low"
    elif [ $ram_gb -lt 16 ]; then
        echo "medium"
    else
        echo "high"
    fi
}

apply_cpu_profile() {
    local cpu_type="$1"
    case $cpu_type in
        intel|amd)
            echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
            ;;
        generic)
            echo "ondemand" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
            ;;
    esac
}

apply_gpu_profile() {
    local gpu_type="$1"
    case $gpu_type in
        nvidia)
            if command -v nvidia-smi &> /dev/null; then
                nvidia-smi -pm 1
                nvidia-smi --auto-boost-default=0
                nvidia-smi -ac 2100,800
            fi
            cat > /etc/environment.d/10-nvidia.conf <<CONF
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
__GL_SYNC_TO_VBLANK=0
VDPAU_DRIVER=nvidia
MOZ_X11_EGL=1
NVD_BACKEND=direct
CONF
            ;;
        amd)
            if [ -d "/sys/class/drm/card*/device/power_dpm_force_performance_level" ]; then
                echo "high" > /sys/class/drm/card*/device/power_dpm_force_performance_level
            fi
            cat > /etc/environment.d/10-amd.conf <<CONF
LIBVA_DRIVER_NAME=radeonsi
VDPAU_DRIVER=radeonsi
AMD_VULKAN_ICD=RADV
MOZ_X11_EGL=1
RADV_PERFTEST=aco
CONF
            ;;
        intel)
            if command -v intel_gpu_frequency &> /dev/null; then
                intel_gpu_frequency --max
            fi
            cat > /etc/environment.d/10-intel.conf <<CONF
LIBVA_DRIVER_NAME=iHD
MOZ_WEBRENDER=1
MOZ_X11_EGL=1
INTEL_PERFORMANCE_MODE=1
CONF
            ;;
    esac
    
    mkdir -p /etc/vulkan/implicit_layer.d
    cat > /etc/vulkan/implicit_layer.d/cache.json <<EOF
{
    "file_format_version": "1.0.0",
    "layer": {
        "name": "VK_LAYER_MESA_cache",
        "type": "GLOBAL",
        "api_version": "1.2.0",
        "implementation_version": "1",
        "description": "Mesa Vulkan cache layer"
    }
}
EOF
}

apply_ram_profile() {
    local ram_level="$1"
    case $ram_level in
        low)
            sysctl -w vm.swappiness=100
            sysctl -w vm.vfs_cache_pressure=100
            ;;
        medium)
            sysctl -w vm.swappiness=60
            sysctl -w vm.vfs_cache_pressure=50
            ;;
        high)
            sysctl -w vm.swappiness=30
            sysctl -w vm.vfs_cache_pressure=25
            ;;
    esac
}

# Detect and apply profile
apply_hardware_profile() {
    local cpu_type=$(detect_cpu_architecture)
    local gpu_type=$(detect_gpu_vendor)
    local ram_level=$(detect_ram_amount)
    
    echo "Detected hardware: CPU=$cpu_type, GPU=$gpu_type, RAM=$ram_level"
    
    apply_cpu_profile "$cpu_type"
    apply_gpu_profile "$gpu_type"
    apply_ram_profile "$ram_level"
    
    mkdir -p "$PROFILE_DIR"
    echo "CPU=$cpu_type" > "$CURRENT_PROFILE"
    echo "GPU=$gpu_type" >> "$CURRENT_PROFILE"
    echo "RAM=$ram_level" >> "$CURRENT_PROFILE"
    
    echo "Hardware profile applied successfully"
}

apply_hardware_profile
EOF

chmod +x /usr/local/bin/hardware-profile-manager

# Hardware profile application service
if [ -e "/etc/systemd/system/hardware-profile.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/hardware-profile.service"
else
cat > /etc/systemd/system/hardware-profile.service <<EOF
[Unit]
Description=Hardware Profile Manager
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hardware-profile-manager
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl enable hardware-profile.service

# 5. I/O Optimizations
cat > /usr/local/bin/advanced-write-optimizer <<'EOF'
#!/bin/bash

optimize_io_scheduler() {
    for block in /sys/block/sd*; do
        if [ -f "$block/queue/scheduler" ]; then
            echo "mq-deadline" > "$block/queue/scheduler"
            echo "256" > "$block/queue/nr_requests"
            echo "0" > "$block/queue/rotational"
            echo "1" > "$block/queue/add_random"
        fi
    done
}

enable_write_coalescing() {
    echo "150" > /proc/sys/vm/dirty_writeback_centisecs
    echo "2000" > /proc/sys/vm/dirty_expire_centisecs
    echo "10" > /proc/sys/vm/dirty_ratio
    echo "5" > /proc/sys/vm/dirty_background_ratio
}

optimize_vm_parameters() {
    echo "0" > /proc/sys/vm/zone_reclaim_mode
    echo "3" > /proc/sys/vm/drop_caches
    echo "1" > /proc/sys/vm/compact_memory
}

apply_optimizations() {
    echo "Applying advanced I/O optimizations..."
    optimize_io_scheduler
    enable_write_coalescing
    optimize_vm_parameters
    echo "I/O optimizations applied successfully"
}

apply_optimizations
EOF

chmod +x /usr/local/bin/advanced-write-optimizer

# I/O optimization service
if [ -e "/etc/systemd/system/io-optimizer.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/io-optimizer.service"
else
cat > /etc/systemd/system/io-optimizer.service <<EOF
[Unit]
Description=Advanced I/O Optimizer
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/advanced-write-optimizer
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl enable io-optimizer.service

# 6. Final Integration
if [ -e "/etc/systemd/system/final-optimizations.service" ]; then
    print_warn "Skipping existing unit /etc/systemd/system/final-optimizations.service"
else
cat > /etc/systemd/system/final-optimizations.service <<EOF
[Unit]
Description=Final System Optimizations Integration
After=hardware-profile.service io-optimizer.service bcachefs-optimize.service
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/echo "All optimizations integrated successfully"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl enable final-optimizations.service

# Re-run mkinitcpio to ensure changes are applied
mkinitcpio -P

CHROOT_005
print_success "Advanced Optimizations (005) injected successfully"

mkdir -p /mnt/usb/persistent/arch
if modprobe erofs &>/dev/null; then
    mkfs.erofs -zlz4hc,12 --uid-offset=0 --gid-offset=0 --mount-point=/ --exclude-path="/tmp/*" /mnt/usb/persistent/arch/root.squashfs /tmp/arch_root
else
    mksquashfs /tmp/arch_root /mnt/usb/persistent/arch/root.squashfs -comp zstd -Xcompression-level 15 -noappend -processors "$(nproc)"
fi

cp /tmp/arch_root/boot/vmlinuz-linux /mnt/usb/persistent/arch/
cp /tmp/arch_root/boot/initramfs-linux.img /mnt/usb/persistent/arch/

grub-install --target=x86_64-efi --efi-directory=/mnt/usb --bootloader-id=ARCH_USB --removable
grub-install --target=i386-pc ${USB_DRIVE}

cat > /mnt/usb/boot/grub/grub.cfg <<GRUB
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

menuentry "Arch Linux USB (Automatic Profile)" {
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

menuentry "Arch Linux USB (Low Resource Mode - 2GB RAM)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd mem_sleep_default=s2idle mitigations=off
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux USB (Medium Resource Mode - 2-8GB RAM)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd transparent_hugepage=always
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux USB (High Resource Mode - 8GB+ RAM)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux quiet loglevel=3 zswap.enabled=1 zswap.compressor=zstd transparent_hugepage=always preempt=full
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux USB (Safe Mode)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux nomodeset systemd.unit=multi-user.target
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux USB (Recovery Mode - Read Only)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux systemd.unit=rescue.target single nomodeset systemd.debug-shell=1 ro
    initrd /arch/initramfs-linux.img
}

menuentry "Arch Linux USB (Snapshot Recovery)" {
    search --no-floppy --label --set=root ARCH_PERSIST
    linux /arch/vmlinuz-linux systemd.unit=multi-user.target single
    initrd /arch/initramfs-linux.img
}
GRUB

umount -R /mnt/usb
sync

# END install
print_success "✅ Arch Linux installation on USB successful!"
print_msg "You can now remove the USB drive and boot the system from it."