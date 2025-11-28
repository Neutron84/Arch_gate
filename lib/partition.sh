#!/bin/bash
# =============================================================================
# PARTITION AND FILESYSTEM MANAGEMENT
# =============================================================================


# Include guard
if [[ -n "${_ARCHGATE_PARTITION_SH_LOADED:-}" ]]; then
  return 0
fi
_ARCHGATE_PARTITION_SH_LOADED=true

# Source required modules
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

# Detect storage type
detect_storage_type() {
    local device="$1"
    local type="ssd" # Default fallback
    
    if [[ ! -b "$device" ]]; then
        return 1
    fi
    
    if udevadm info --query=property --name="$device" | grep -q "ID_BUS=usb"; then
        type="usb_memory"
        elif udevadm info --query=property --name="$device" | grep -qi "mmc\|sdio"; then
        type="sdcard"
    else
        # Internal: check rotation
        local rot
        rot=$(cat "/sys/block/$(basename "$device")/queue/rotational" 2>/dev/null || echo 1)
        if [[ "$rot" == "0" ]]; then
            type="ssd"
        else
            type="hdd"
        fi
    fi
    echo "$type"
}

# Wipe disk
wipe_and_partition() {
    local device="$1"
    local partition_scheme="${2:-hybrid}"
    
    print_msg "Wiping disk $device..."
    
    # 1. Wipe signatures
    wipefs --all --force "$device"
    
    # 2. Clear partition table
    sgdisk --zap-all "$device"
    
    # 3. Make sure kernel reloads
    partprobe "$device"
    udevadm settle
    sleep 2
    
    return 0
}

# Create partitions
create_partitions() {
    local device="$1"
    local storage_type="$2"
    local partition_scheme="${3:-hybrid}"
    
    print_msg "Creating partitions on $device using scheme: $partition_scheme"
    
    case "$partition_scheme" in
        hybrid)
            # 3 Partitions: BIOS-Boot(1M) + EFI(512M) + Root(Rest)
            # Using atomic command to prevent race conditions
            print_msg "Applying Hybrid (BIOS+UEFI) layout..."
            sgdisk -n 1:2048:+1M    -t 1:ef02 -c 1:"BIOS Boot" \
            -n 2:0:+512M     -t 2:ef00 -c 2:"EFI System" \
            -n 3:0:0         -t 3:8300 -c 3:"Arch Linux" \
            "$device"
        ;;
        
        gpt)
            # 2 Partitions: EFI(512M) + Root(Rest)
            print_msg "Applying Standard GPT (UEFI) layout..."
            sgdisk -n 1:0:+512M     -t 1:ef00 -c 1:"EFI System" \
            -n 2:0:0         -t 2:8300 -c 2:"Arch Linux" \
            "$device"
        ;;
        
        mbr)
            # MBR Layout using parted
            print_msg "Applying Legacy MBR layout..."
            parted -s "$device" mklabel msdos
            parted -s "$device" mkpart primary fat32 1MiB 513MiB
            parted -s "$device" set 1 esp on
            parted -s "$device" mkpart primary ext4 513MiB 100%
        ;;
    esac
    
    if [[ $? -ne 0 ]]; then
        print_failed "Partitioning failed!"
        return 1
    fi
    
    # CRITICAL: Wait for kernel to register new partitions
    print_msg "Waiting for partitions to register..."
    partprobe "$device"
    udevadm settle
    sleep 5  # Give it ample time
    
    print_success "Partitioning completed."
    return 0
}
# btrfs subvolume creation based on layout config
apply_btrfs_layout() {
    local device="$1"
    local mount_root="$2" # Temporary mount point for subvol creation
    local config_file="/etc/archgate/btrfs_layout.conf"
    
    if [[ ! -f "$config_file" ]]; then
        print_failed "Btrfs layout config not found!"
        return 1
    fi
    
    print_msg "Creating Btrfs subvolumes..."
    
    # 1. Mount Top-Level (ID 5)
    mount "$device" "$mount_root"
    
    # 2. Create Subvolumes
    while IFS= read -r line; do
        [[ "$line" =~ ^#.* ]] && continue # Skip comments
        [[ -z "$line" ]] && continue
        
        local name=$(echo "$line" | cut -d'|' -f1)
        # Remove leading slash if user added it (e.g., /@ -> @)
        name="${name#/}"
        
        print_msg "Creating subvolume: $name"
        btrfs subvolume create "$mount_root/$name"
    done < "$config_file"
    
    # 3. Unmount Top-Level
    umount "$mount_root"
}

# Format partitions
format_partitions() {
    local device="$1"
    local storage_type="$2"
    local filesystem_type="${3:-bcachefs}"
    local partition_scheme="${4:-hybrid}" # Need this to know indices
    
    print_msg "Detecting partition paths for formatting..."
    local part_esp part_main
    
    # Determine partition numbers based on scheme
    if [[ "$partition_scheme" == "hybrid" ]]; then
        # In Hybrid: 1=BIOS, 2=ESP, 3=Root
        part_esp=$(get_part_path "$device" 2)
        part_main=$(get_part_path "$device" 3)
    else
        # In GPT/MBR: 1=ESP, 2=Root
        part_esp=$(get_part_path "$device" 1)
        part_main=$(get_part_path "$device" 2)
    fi
    
    if [[ -z "$part_esp" || -z "$part_main" ]]; then
        print_failed "Could not find partitions for formatting."
        return 1
    fi
    
    print_success "ESP: $part_esp | Main: $part_main"
    
    # 1. Format ESP
    print_msg "Formatting ESP ($part_esp)..."
    mkfs.fat -F32 -n ARCH_ESP "$part_esp" || return 1
    
    # Format main partition based on filesystem type
    print_msg "Formatting Main Partition ($part_main) with $filesystem_type..."
    
    case "$filesystem_type" in
        bcachefs)
            if command -v bcachefs &>/dev/null; then
                # Removed --encrypted=none as it caused errors in new versions
                if ! bcachefs format \
                --compression=zstd \
                --label=ARCH_PERSIST \
                --replicas=1 \
                "$part_main"; then
                    print_warn "Bcachefs format failed. Falling back to ext4."
                    mkfs.ext4 -F -L ARCH_PERSIST "$part_main"
                else
                    print_success "Formatted with bcachefs"
                fi
            else
                print_warn "bcachefs tool not found. Using ext4."
                mkfs.ext4 -F -L ARCH_PERSIST "$part_main"
            fi
        ;;
        
        btrfs)
            # -f force overwrite
            if ! mkfs.btrfs -f -L ARCH_PERSIST "$part_main"; then
                print_failed "Failed to format with btrfs"
                return 1
            fi
            print_success "Formatted with btrfs"
            
            # APPLY SUBVOLUMES NOW
            mkdir -p /mnt/btrfs_tmp
            apply_btrfs_layout "$part_main" "/mnt/btrfs_tmp"
            rmdir /mnt/btrfs_tmp
        ;;

        f2fs)
            # -f force overwrite
            if ! mkfs.f2fs -l ARCH_PERSIST -f "$part_main"; then
                print_failed "Failed to format with f2fs"
                return 1
            fi
            print_success "Formatted with f2fs"
        ;;
        
        xfs)
            # -f force overwrite
            if ! mkfs.xfs -f -L ARCH_PERSIST "$part_main"; then
                print_failed "Failed to format with xfs"
                return 1
            fi
            print_success "Formatted with xfs"
        ;;
        
        ext4|*)
            if ! mkfs.ext4 -F -L ARCH_PERSIST "$part_main"; then
                print_failed "Failed to format with ext4"
                return 1
            fi
            print_success "Formatted with ext4"
        ;;
    esac
    
    return 0
}

# Mount partitions
mount_partitions() {
    local device="$1"
    local mount_point="${2:-/mnt/usb}"
    local partition_scheme="${3:-hybrid}"
    local filesystem_type="${4:-ext4}"
    
    local part_esp part_main
    
    if [[ "$partition_scheme" == "hybrid" ]]; then
        part_esp=$(get_part_path "$device" 2)
        part_main=$(get_part_path "$device" 3)
    else
        part_esp=$(get_part_path "$device" 1)
        part_main=$(get_part_path "$device" 2)
    fi
    
    check_and_create_directory "$mount_point"
    check_and_create_directory "$mount_point/persistent"
    
    # Mount ESP
    mount "$part_esp" "$mount_point" || return 1
    
    # Check if we are mounting btrfs, if so, we need complex logic
    if [[ "$filesystem_type" == "btrfs" ]]; then
        local config_file="/etc/archgate/btrfs_layout.conf"
        
        if [[ ! -f "$config_file" ]]; then
            print_failed "Btrfs layout config not found!"
            return 1
        fi
        
        # 1. Mount Root (@) first
        # We need to find which subvolume is mounted at /
        local root_subvol=""
        local root_opts=""
        
        while IFS= read -r line; do
            [[ "$line" =~ ^#.* ]] && continue
            [[ -z "$line" ]] && continue
            local name=$(echo "$line" | cut -d'|' -f1)
            local mnt=$(echo "$line" | cut -d'|' -f2)
            local opt=$(echo "$line" | cut -d'|' -f3)
            
            if [[ "$mnt" == "/" ]]; then
                root_subvol="$name"
                root_opts="$opt"
                break
            fi
        done < "$config_file"
        
        if [[ -z "$root_subvol" ]]; then
            print_failed "Btrfs layout does not have a root (/) mount point!"
            return 1
        fi
        
        print_msg "Mounting Root Subvolume: $root_subvol"
        mount -o "subvol=$root_subvol,$root_opts" "$part_main" "$mount_point/persistent" || return 1
        
        # 2. Mount children
        while IFS= read -r line; do
            [[ "$line" =~ ^#.* ]] && continue
            [[ -z "$line" ]] && continue
            local name=$(echo "$line" | cut -d'|' -f1)
            local mnt=$(echo "$line" | cut -d'|' -f2)
            local opt=$(echo "$line" | cut -d'|' -f3)
            
            if [[ "$mnt" == "/" ]]; then continue; fi # Skip root
            
            # Ignore leading slash for mkdir
            local relative_mnt="${mnt#/}"
            
            mkdir -p "$mount_point/persistent/$relative_mnt"
            mount -o "subvol=$name,$opt" "$part_main" "$mount_point/persistent/$mnt" || return 1
        done < "$config_file"
        
        print_success "Btrfs subvolumes mounted."
        return 0
    fi
    
    # For standard filesystems (ext4, bcachefs, f2fs, xfs, etc.)
    mount "$part_main" "$mount_point/persistent" || return 1
    
    return 0
}