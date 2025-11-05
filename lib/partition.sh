#!/bin/bash
# =============================================================================
# PARTITION AND FILESYSTEM MANAGEMENT
# =============================================================================

# Source required modules
[[ -f "${0%/*}/colors.sh" ]] && source "${0%/*}/colors.sh"
[[ -f "${0%/*}/logging.sh" ]] && source "${0%/*}/logging.sh"
[[ -f "${0%/*}/utils.sh" ]] && source "${0%/*}/utils.sh"

# Detect storage type (SSD, HDD, USB, SD card)
detect_storage_type() {
    local device="$1"
    local type="unknown"
    
    # Check if device exists
    if [[ ! -b "$device" ]]; then
        print_failed "Device $device is not a valid block device"
        return 1
    fi
    
    # Check if it's a USB device
    if udevadm info --query=property --name="$device" | grep -q "ID_BUS=usb"; then
        # Check if it's removable
        if [[ $(cat "/sys/block/$(basename "$device")/removable" 2>/dev/null) == "1" ]]; then
            # Check if it's an SSD or HDD
            if [[ -f "/sys/block/$(basename "$device")/queue/rotational" ]]; then
                local rotational=$(cat "/sys/block/$(basename "$device")/queue/rotational" 2>/dev/null)
                if [[ "$rotational" == "0" ]]; then
                    type="ssd_external"
                else
                    type="hdd_external"
                fi
            else
                type="usb_memory"
            fi
        else
            type="usb_memory"
        fi
    # Check if it's an SD card
    elif udevadm info --query=property --name="$device" | grep -qi "mmc\|sdio"; then
        type="sdcard"
    # Check if it's internal storage
    else
        # Check if it's SSD or HDD
        if [[ -f "/sys/block/$(basename "$device")/queue/rotational" ]]; then
            local rotational=$(cat "/sys/block/$(basename "$device")/queue/rotational" 2>/dev/null)
            if [[ "$rotational" == "0" ]]; then
                type="ssd"
            else
                type="hdd"
            fi
        else
            type="ssd"
        fi
    fi
    
    echo "$type"
    return 0
}

# Wipe disk and create partition table
wipe_and_partition() {
    local device="$1"
    local partition_scheme="${2:-hybrid}"  # hybrid, gpt, mbr
    
    print_msg "Wiping and partitioning $device..."
    
    # Create snapshot before destructive operations
    create_pre_install_snapshot
    
    # Wipe filesystem signatures
    if ! wipefs -a "$device"; then
        print_failed "Failed to wipe $device"
        return 1
    fi
    print_success "Disk wiped"
    
    # Create partition table
    case "$partition_scheme" in
        hybrid|gpt)
            print_msg "Creating GPT partition table..."
            if ! sgdisk --zap-all "$device"; then
                print_failed "Failed to clear partition table"
                return 1
            fi
            if ! sgdisk -o "$device"; then
                print_failed "Failed to create GPT partition table"
                return 1
            fi
            print_success "GPT partition table created"
            ;;
        mbr)
            print_msg "Creating MBR partition table..."
            if ! parted -s "$device" mklabel msdos; then
                print_failed "Failed to create MBR partition table"
                return 1
            fi
            print_success "MBR partition table created"
            ;;
    esac
    
    return 0
}

# Create partitions for different storage types
create_partitions() {
    local device="$1"
    local storage_type="$2"
    local partition_scheme="${3:-hybrid}"
    
    print_msg "Creating partitions for $storage_type..."
    
    case "$storage_type" in
        usb_memory|ssd_external|hdd_external|sdcard)
            # Hybrid boot support for portable devices
            create_hybrid_partitions "$device" "$partition_scheme"
            ;;
        ssd|hdd)
            # Standard partitions for internal storage
            create_standard_partitions "$device" "$partition_scheme"
            ;;
        *)
            print_failed "Unknown storage type: $storage_type"
            return 1
            ;;
    esac
    
    # Force kernel to re-read partition table
    sync
    sleep 2
    partprobe "$device" 2>/dev/null
    sync
    sleep 2
    
    print_success "Partitions created successfully"
    return 0
}

# Create hybrid boot partitions (for portable devices)
create_hybrid_partitions() {
    local device="$1"
    local scheme="${2:-hybrid}"
    
    if [[ "$scheme" == "hybrid" || "$scheme" == "gpt" ]]; then
        # GPT hybrid partition layout:
        # 1: BIOS boot partition (1M, ef02)
        # 2: EFI System Partition (512M, ef00)
        # 3: Main partition (rest, 8300)
        
        print_msg "Creating hybrid boot partitions..."
        
        if ! sgdisk -n 1:1M:+2M -t 1:ef02 "$device"; then
            print_failed "Failed to create BIOS boot partition"
            return 1
        fi
        
        if ! sgdisk -n 2:0:+512M -t 2:ef00 "$device"; then
            print_failed "Failed to create EFI partition"
            return 1
        fi
        
        if ! sgdisk -n 3:0:0 -t 3:8300 "$device"; then
            print_failed "Failed to create main partition"
            return 1
        fi
        
        print_success "Hybrid boot partitions created"
    else
        # MBR hybrid partition layout
        print_msg "Creating MBR hybrid boot partitions..."
        
        if ! parted -s "$device" mkpart primary 1MiB 3MiB; then
            print_failed "Failed to create BIOS boot partition"
            return 1
        fi
        parted -s "$device" set 1 bios_grub on
        
        if ! parted -s "$device" mkpart primary fat32 3MiB 515MiB; then
            print_failed "Failed to create EFI partition"
            return 1
        fi
        parted -s "$device" set 2 esp on
        
        if ! parted -s "$device" mkpart primary ext4 515MiB 100%; then
            print_failed "Failed to create main partition"
            return 1
        fi
    fi
    
    return 0
}

# Create standard partitions (for internal storage)
create_standard_partitions() {
    local device="$1"
    local scheme="${2:-gpt}"
    
    if [[ "$scheme" == "gpt" ]]; then
        print_msg "Creating standard GPT partitions..."
        
        if ! sgdisk -n 1:0:+512M -t 1:ef00 "$device"; then
            print_failed "Failed to create EFI partition"
            return 1
        fi
        
        if ! sgdisk -n 2:0:0 -t 2:8300 "$device"; then
            print_failed "Failed to create root partition"
            return 1
        fi
        
        print_success "Standard GPT partitions created"
    else
        print_msg "Creating standard MBR partitions..."
        
        if ! parted -s "$device" mkpart primary fat32 1MiB 513MiB; then
            print_failed "Failed to create EFI partition"
            return 1
        fi
        parted -s "$device" set 1 esp on
        
        if ! parted -s "$device" mkpart primary ext4 513MiB 100%; then
            print_failed "Failed to create root partition"
            return 1
        fi
    fi
    
    return 0
}

# Format partitions
format_partitions() {
    local device="$1"
    local storage_type="$2"
    local filesystem_type="${3:-bcachefs}"
    
    print_msg "Detecting partition paths..."
    local part_esp part_main
    
    # Detect ESP partition (usually partition 2 for hybrid, 1 for standard)
    part_esp=$(get_part_path "$device" 2 2>/dev/null || get_part_path "$device" 1 2>/dev/null)
    part_main=$(get_part_path "$device" 3 2>/dev/null || get_part_path "$device" 2 2>/dev/null)
    
    if [[ -z "$part_esp" || -z "$part_main" ]]; then
        print_failed "Failed to detect partition paths"
        return 1
    fi
    
    print_success "ESP Partition: $part_esp"
    print_success "Main Partition: $part_main"
    
    # Format ESP partition
    print_msg "Formatting ESP partition..."
    if ! mkfs.fat -F32 -n ARCH_ESP "$part_esp"; then
        print_failed "Failed to format ESP partition"
        return 1
    fi
    print_success "ESP partition formatted"
    
    # Format main partition based on filesystem type
    print_msg "Formatting main partition with $filesystem_type..."
    case "$filesystem_type" in
        bcachefs)
            if ! command -v bcachefs &>/dev/null; then
                print_warn "bcachefs-tools not available, falling back to ext4"
                filesystem_type="ext4"
            else
                if ! bcachefs format --label ARCH_PERSIST \
                    --compression=zstd \
                    --foreground_target=ssd \
                    --background_target=ssd \
                    --replicas=1 \
                    --data_checksum=xxhash \
                    --metadata_checksum=xxhash \
                    --encrypted=none \
                    "$part_main"; then
                    print_warn "bcachefs format failed, falling back to ext4"
                    filesystem_type="ext4"
                else
                    print_success "Main partition formatted with bcachefs"
                    return 0
                fi
            fi
            ;;
        ext4)
            if ! mkfs.ext4 -F -L ARCH_PERSIST "$part_main"; then
                print_failed "Failed to format main partition with ext4"
                return 1
            fi
            print_success "Main partition formatted with ext4"
            ;;
        f2fs)
            if ! command -v mkfs.f2fs &>/dev/null; then
                print_warn "f2fs-tools not available, falling back to ext4"
                if ! mkfs.ext4 -F -L ARCH_PERSIST "$part_main"; then
                    print_failed "Failed to format main partition"
                    return 1
                fi
            else
                if ! mkfs.f2fs -l ARCH_PERSIST "$part_main"; then
                    print_failed "Failed to format main partition with f2fs"
                    return 1
                fi
            fi
            print_success "Main partition formatted with f2fs"
            ;;
        *)
            print_failed "Unsupported filesystem: $filesystem_type"
            return 1
            ;;
    esac
    
    return 0
}

# Mount partitions
mount_partitions() {
    local device="$1"
    local mount_point="${2:-/mnt/usb}"
    
    print_msg "Detecting partition paths..."
    local part_esp part_main
    
    part_esp=$(get_part_path "$device" 2 2>/dev/null || get_part_path "$device" 1 2>/dev/null)
    part_main=$(get_part_path "$device" 3 2>/dev/null || get_part_path "$device" 2 2>/dev/null)
    
    if [[ -z "$part_esp" || -z "$part_main" ]]; then
        print_failed "Failed to detect partition paths"
        return 1
    fi
    
    print_msg "Mounting partitions..."
    
    # Create mount points
    check_and_create_directory "$mount_point"
    check_and_create_directory "$mount_point/persistent"
    
    # Mount ESP
    if ! mount "$part_esp" "$mount_point"; then
        print_msg "Retrying mount in 3 seconds..."
        sleep 3
        if ! mount "$part_esp" "$mount_point"; then
            print_failed "Failed to mount ESP partition"
            return 1
        fi
    fi
    
    # Mount main partition
    if ! mount "$part_main" "$mount_point/persistent"; then
        print_failed "Failed to mount main partition"
        return 1
    fi
    
    print_success "Partitions mounted successfully"
    print_msg "ESP: $mount_point"
    print_msg "Main: $mount_point/persistent"
    
    return 0
}

