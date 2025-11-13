#!/bin/bash
# =============================================================================
# PARTITION AND FILESYSTEM MANAGEMENT
# =============================================================================

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

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
    
    # Check disk space before creating partitions
    if ! check_disk_space "$device" 5; then
        return 1
    fi
    
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

# Check if device has sufficient space
check_disk_space() {
    local device="$1"
    local required_space_gb="${2:-5}"  # Default 5GB
    local required_space_bytes=$((required_space_gb * 1024 * 1024 * 1024))
    
    # Check if device exists
    if [[ ! -b "$device" ]]; then
        print_failed "Device $device does not exist or is not a block device"
        return 1
    fi
    
    # Get device size
    local device_size
    if command -v blockdev &>/dev/null; then
        device_size=$(blockdev --getsize64 "$device" 2>/dev/null || echo "0")
    elif command -v lsblk &>/dev/null; then
        device_size=$(lsblk -b -d -n -o SIZE "$device" 2>/dev/null | head -n1 || echo "0")
    else
        print_warn "Cannot determine device size (blockdev/lsblk not available)"
        return 0  # Continue anyway
    fi
    
    if [[ -z "$device_size" ]] || [[ "$device_size" == "0" ]]; then
        print_warn "Could not determine device size, skipping space check"
        return 0
    fi
    
    local available_gb=$((device_size / 1024 / 1024 / 1024))
    
    if [[ $device_size -lt $required_space_bytes ]]; then
        print_failed "Insufficient disk space on $device"
        print_failed "Required: ${required_space_gb}GB, Available: ${available_gb}GB"
        return 1
    fi
    
    print_success "Disk space check passed: ${available_gb}GB available"
    return 0
}

# Detect partitions using lsblk (more reliable method)
detect_partitions() {
    local device="$1"
    local -A partitions
    
    if [[ ! -b "$device" ]]; then
        print_failed "Device $device is not a valid block device"
        return 1
    fi
    
    # Use lsblk to detect all partitions under the device
    local device_base="${device##*/}"
    local part_name part_path part_num
    
    # Get all block devices and filter for partitions of this device
    # lsblk -r gives raw output, -o NAME gives just names
    while IFS= read -r line; do
        # Skip empty lines and the device itself
        [[ -z "$line" ]] && continue
        [[ "$line" == "$device_base" ]] && continue
        
        # Check if this is a partition (child of the device)
        # Format: device_base + optional 'p' + number (e.g., sda1, nvme0n1p2)
        if [[ "$line" =~ ^${device_base}(p)?([0-9]+)$ ]]; then
            part_name="$line"
            part_num="${BASH_REMATCH[2]}"
            part_path="/dev/$part_name"
            
            # Verify partition exists as block device
            if [[ -b "$part_path" ]]; then
                partitions[$part_num]="$part_path"
            fi
        fi
    done < <(lsblk -r -n -o NAME 2>/dev/null | grep -E "^${device_base}(p)?[0-9]+$" || true)
    
    # If no partitions found with lsblk, try alternative method
    if [[ ${#partitions[@]} -eq 0 ]]; then
        # Try to find partitions by checking common patterns
        local i
        for i in {1..9}; do
            # Try nvme style first
            if [[ -b "${device}p${i}" ]]; then
                partitions[$i]="${device}p${i}"
            # Try sd style
            elif [[ -b "${device}${i}" ]]; then
                partitions[$i]="${device}${i}"
            fi
        done
    fi
    
    # Output partitions as sorted array
    local result=()
    local sorted_keys
    sorted_keys=$(printf '%s\n' "${!partitions[@]}" | sort -n 2>/dev/null || echo "")
    
    if [[ -n "$sorted_keys" ]]; then
        while IFS= read -r key; do
            [[ -n "$key" ]] && [[ -n "${partitions[$key]:-}" ]] && result+=("${partitions[$key]}")
        done <<< "$sorted_keys"
    fi
    
    printf '%s\n' "${result[@]}"
    return 0
}

# Mount with retry capability
mount_with_retry() {
    local device="$1"
    local mount_point="$2"
    local max_attempts="${3:-3}"
    local attempt=1
    local mount_output
    
    if [[ ! -b "$device" ]]; then
        print_failed "Device $device is not a valid block device"
        return 1
    fi
    
    if [[ ! -d "$mount_point" ]]; then
        print_failed "Mount point $mount_point is not a directory"
        return 1
    fi
    
    while [[ $attempt -le $max_attempts ]]; do
        # Try to mount
        mount_output=$(mount "$device" "$mount_point" 2>&1)
        local mount_exit_code=$?
        
        if [[ $mount_exit_code -eq 0 ]]; then
            # Verify mount was successful
            if mountpoint -q "$mount_point" 2>/dev/null; then
                if [[ $attempt -gt 1 ]]; then
                    print_success "Successfully mounted $device to $mount_point (attempt $attempt)"
                fi
                return 0
            else
                print_warn "Mount command succeeded but mountpoint verification failed (attempt $attempt/$max_attempts)"
            fi
        else
            if [[ $attempt -lt $max_attempts ]]; then
                print_warn "Mount attempt $attempt/$max_attempts failed: $mount_output"
                print_msg "Retrying in 2 seconds..."
                sleep 2
                sync
            else
                print_failed "Failed to mount $device to $mount_point after $max_attempts attempts"
                print_failed "Last error: $mount_output"
            fi
        fi
        
        ((attempt++))
    done
    
    return 1
}

# Mount partitions
mount_partitions() {
    local device="$1"
    local mount_point="${2:-/mnt/usb}"
    
    # Check if device exists
    if [[ ! -b "$device" ]]; then
        print_failed "Device $device does not exist or is not a block device"
        return 1
    fi
    
    # Check disk space before proceeding
    if ! check_disk_space "$device" 5; then
        return 1
    fi
    
    print_msg "Detecting partition paths..."
    local part_esp part_main
    local detected_parts
    
    # Use improved detection method
    detected_parts=($(detect_partitions "$device" 2>/dev/null))
    
    if [[ ${#detected_parts[@]} -eq 0 ]]; then
        # Fallback to get_part_path
        part_esp=$(get_part_path "$device" 2 2>/dev/null || get_part_path "$device" 1 2>/dev/null)
        part_main=$(get_part_path "$device" 3 2>/dev/null || get_part_path "$device" 2 2>/dev/null)
    else
        # Use detected partitions
        # For hybrid: ESP is usually partition 2, main is partition 3
        # For standard: ESP is usually partition 1, main is partition 2
        if [[ ${#detected_parts[@]} -ge 3 ]]; then
            # Hybrid layout (3+ partitions)
            part_esp="${detected_parts[1]}"  # Index 1 = partition 2
            part_main="${detected_parts[2]}" # Index 2 = partition 3
        elif [[ ${#detected_parts[@]} -ge 2 ]]; then
            # Standard layout (2 partitions)
            part_esp="${detected_parts[0]}"  # Index 0 = partition 1
            part_main="${detected_parts[1]}" # Index 1 = partition 2
        else
            print_failed "Not enough partitions detected (found ${#detected_parts[@]}, need at least 2)"
            return 1
        fi
    fi
    
    if [[ -z "$part_esp" ]] || [[ -z "$part_main" ]]; then
        print_failed "Failed to detect partition paths"
        print_msg "Detected partitions: ${detected_parts[*]}"
        return 1
    fi
    
    # Verify partitions exist
    if [[ ! -b "$part_esp" ]]; then
        print_failed "ESP partition $part_esp does not exist"
        return 1
    fi
    
    if [[ ! -b "$part_main" ]]; then
        print_failed "Main partition $part_main does not exist"
        return 1
    fi
    
    print_success "ESP Partition: $part_esp"
    print_success "Main Partition: $part_main"
    
    print_msg "Mounting partitions..."

    # Basic privilege hint
    if [[ $(id -u) -ne 0 ]]; then
        print_warn "Not running as root. Mounts and mkdir may fail without root privileges."
    fi

    # Ensure mount point parent exists
    local mp_parent
    mp_parent=$(dirname "$mount_point")
    if [[ ! -d "$mp_parent" ]]; then
        if ! mkdir -p "$mp_parent" 2>/dev/null; then
            print_failed "Failed to create parent directory for mount point: $mp_parent"
            return 1
        fi
    fi

    # If mount_point exists but is not a directory, move it aside and create a directory
    if [[ -e "$mount_point" && ! -d "$mount_point" ]]; then
        local backup_path="/tmp/archgate-moved-$(basename "$mount_point")-$(date +%s)"
        print_warn "Mount point '$mount_point' exists and is not a directory. Moving to: $backup_path"
        if ! mv -f "$mount_point" "$backup_path" 2>/dev/null; then
            print_failed "Failed to move existing file at $mount_point to $backup_path. Please remove or rename it and retry."
            return 1
        fi
    fi

    # Create mount point 
    if ! mkdir -p "$mount_point" 2>/dev/null; then
        print_failed "Failed to create mount point: $mount_point (permission or filesystem error)"
        return 1
    fi

    # Sync and wait a bit for filesystem to be ready
    sync
    sleep 1

    # Mount ESP partition with retry
    if ! mount_with_retry "$part_esp" "$mount_point" 3; then
        print_failed "Failed to mount ESP partition: $part_esp to $mount_point"
        return 1
    fi
    print_success "ESP partition mounted"

    # Create persistent directory AFTER mounting ESP (so it's not shadowed by the mount)
    local persistent_dir="$mount_point/persistent"
    if ! mkdir -p "$persistent_dir" 2>/dev/null; then
        # If creation failed, check for common causes
        if [[ ! -w "$mount_point" ]]; then
            print_failed "Mount point '$mount_point' is not writable. Check permissions or run as root."
            umount "$mount_point" 2>/dev/null || true
        else
            print_failed "Failed to create persistent directory: $persistent_dir"
            umount "$mount_point" 2>/dev/null || true
        fi
        return 1
    fi

    # Mount main partition with retry
    if ! mount_with_retry "$part_main" "$persistent_dir" 3; then
        print_failed "Failed to mount main partition: $part_main to $persistent_dir"
        print_msg "Unmounting ESP partition..."
        umount "$mount_point" 2>/dev/null || true
        return 1
    fi
    print_success "Main partition mounted"

    print_success "Partitions mounted successfully"
    print_msg "ESP: $mount_point"
    print_msg "Main: $mount_point/persistent"

    return 0
}

