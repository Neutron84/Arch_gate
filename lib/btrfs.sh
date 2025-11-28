#!/bin/bash
# =============================================================================
# BTRFS SUBVOLUME MANAGEMENT MODULE
# =============================================================================

# Default mount options
DEFAULT_BTRFS_OPTS="rw,noatime,compress=zstd:3,ssd,space_cache=v2"
NODATACOW_OPTS="rw,noatime,nodatacow,ssd,space_cache=v2"

# Initialize global arrays for subvolumes
# Format: Name | Mount_Point | Options
declare -a BTRFS_SUBVOLS

# Helper to add a subvolume to the list
add_subvol_entry() {
    local name="$1"
    local mount="$2"
    local opts="${3:-$DEFAULT_BTRFS_OPTS}"
    BTRFS_SUBVOLS+=("$name|$mount|$opts")
}

# 1. Simple Profile
load_profile_simple() {
    BTRFS_SUBVOLS=()
    add_subvol_entry "@" "/"
    add_subvol_entry "@home" "/home"
    add_subvol_entry "@snapshots" "/.snapshots" 
}

# 2. Advanced Profile (Based on your provided manual)
load_profile_advanced() {
    BTRFS_SUBVOLS=()
    add_subvol_entry "@" "/"
    add_subvol_entry "@home" "/home"
    add_subvol_entry "@opt" "/opt"
    add_subvol_entry "@srv" "/srv"
    
    # NoDataCOW for temp/cache heavy dirs
    add_subvol_entry "@tmp" "/tmp" "$NODATACOW_OPTS"
    
    add_subvol_entry "@usr_local" "/usr/local"
    
    # Var breakdown
    add_subvol_entry "@var" "/var"
    add_subvol_entry "@var_log" "/var/log"
    add_subvol_entry "@var_cache" "/var/cache"
    add_subvol_entry "@var_lib" "/var/lib"
    add_subvol_entry "@var_tmp" "/var/tmp" "$NODATACOW_OPTS"
    add_subvol_entry "@pkg" "/var/cache/pacman/pkg"
    
    add_subvol_entry "@snapshots" "/.snapshots"
}

# 3. Smart Profile (Optimized balanced approach)
load_profile_smart() {
    # Starts basic, but optimized for typical desktop usage + snapshots
    BTRFS_SUBVOLS=()
    add_subvol_entry "@" "/"
    add_subvol_entry "@home" "/home"
    add_subvol_entry "@snapshots" "/.snapshots"
    add_subvol_entry "@var_log" "/var/log"
    
    # Determine if we need specific optimizations
    if confirmation_y_or_n "Will you use Virtual Machines or Docker?" "setup_vm_docker" "false"; then
        print_msg "Adding @var_lib_machines (NoCoW) for VM performance..."
        add_subvol_entry "@var_lib_machines" "/var/lib/machines" "$NODATACOW_OPTS"
        add_subvol_entry "@var_lib_docker" "/var/lib/docker" "$NODATACOW_OPTS"
    fi
    
    # Separate pkg cache to avoid snapshotting binary blobs unnecessarily
    add_subvol_entry "@pkg" "/var/cache/pacman/pkg"
}

# Helper to select mount options interactively
select_mount_options() {
    local current_opts="$1"
    local new_opts=""
    
    echo "Select options (separated by comma, e.g., 1,2,4):"
    echo "1. compress=zstd:3 (Standard compression)"
    echo "2. compress=zstd:1 (Faster, less compression)"
    echo "3. noatime (Performance boost)"
    echo "4. nodatacow (For DBs/VM images - disables compression/checksums)"
    echo "5. ssd (SSD optimization)"
    echo "6. space_cache=v2 (Better caching)"
    echo "7. autodefrag (Good for HDD/Single files)"
    
    read -r -p "Selection: " sel
    
    # Simple logic to build string based on numbers
    if [[ "$sel" == *"1"* ]]; then new_opts+="compress=zstd:3,"; fi
    if [[ "$sel" == *"2"* ]]; then new_opts+="compress=zstd:1,"; fi
    if [[ "$sel" == *"3"* ]]; then new_opts+="noatime,"; fi
    if [[ "$sel" == *"4"* ]]; then new_opts+="nodatacow,"; fi
    if [[ "$sel" == *"5"* ]]; then new_opts+="ssd,"; fi
    if [[ "$sel" == *"6"* ]]; then new_opts+="space_cache=v2,"; fi
    if [[ "$sel" == *"7"* ]]; then new_opts+="autodefrag,"; fi
    
    # Default safety if empty
    if [[ -z "$new_opts" ]]; then new_opts="defaults,"; fi
    
    echo "${new_opts%,}" # remove trailing comma
}

# 4. Manual Mode Editor Loop
edit_btrfs_layout() {
    local action
    
    while true; do
        banner
        print_msg "${BOLD}Current Btrfs Layout:${NC}"
        echo
        printf "%-4s | %-20s | %-25s | %s\n" "No" "Subvolume" "Mount Point" "Options"
        echo "--------------------------------------------------------------------------------"
        
        local i=0
        for entry in "${BTRFS_SUBVOLS[@]}"; do
            local name=$(echo "$entry" | cut -d'|' -f1)
            local mnt=$(echo "$entry" | cut -d'|' -f2)
            local opt=$(echo "$entry" | cut -d'|' -f3)
            printf "%-4d | %-20s | %-25s | %s\n" "$((i+1))" "$name" "$mnt" "$opt"
            ((i++))
        done
        echo
        echo "${C}A) Add new subvolume"
        echo "E) Edit a subvolume"
        echo "D) Delete a subvolume"
        echo "S) Save & Continue"
        echo "C) Cancel & Go Back${NC}"
        echo
        
        read -r -p "Choose an action: " action
        case "${action,,}" in
            a)
                read -r -p "Subvolume Name (e.g., @data): " new_name
                read -r -p "Mount Point (e.g., /data): " new_mnt
                local new_opts=$(select_mount_options "")
                add_subvol_entry "$new_name" "$new_mnt" "$new_opts"
                ;;
            e)
                read -r -p "Enter number to edit: " num
                if [[ "$num" -ge 1 && "$num" -le "${#BTRFS_SUBVOLS[@]}" ]]; then
                    local idx=$((num-1))
                    local old_entry="${BTRFS_SUBVOLS[$idx]}"
                    local old_name=$(echo "$old_entry" | cut -d'|' -f1)
                    local old_mnt=$(echo "$old_entry" | cut -d'|' -f2)
                    
                    read -r -p "Name [$old_name]: " new_name
                    new_name="${new_name:-$old_name}"
                    
                    read -r -p "Mount Point [$old_mnt]: " new_mnt
                    new_mnt="${new_mnt:-$old_mnt}"
                    
                    echo "Re-selecting options..."
                    local new_opts=$(select_mount_options "")
                    
                    BTRFS_SUBVOLS[$idx]="$new_name|$new_mnt|$new_opts"
                fi
                ;;
            d)
                read -r -p "Enter number to delete: " num
                if [[ "$num" -ge 1 && "$num" -le "${#BTRFS_SUBVOLS[@]}" ]]; then
                    # Remove from array (complex using generic logic)
                    local idx=$((num-1))
                    BTRFS_SUBVOLS=("${BTRFS_SUBVOLS[@]:0:$idx}" "${BTRFS_SUBVOLS[@]:$((idx+1))}")
                fi
                ;;
            s)
                return 0
                ;;
            c)
                return 1
                ;;
        esac
    done
}

# Main Btrfs Configuration Menu
configure_btrfs() {
    while true; do
        banner
        print_msg "${BOLD}Btrfs Subvolume Strategy:${NC}"
        echo
        echo "1. Manual (Build from scratch)"
        echo "2. Simple (@, @home)"
        echo "3. Advanced (Based on your strict layout)"
        echo "4. Smart (Optimized for your needs)"
        echo "b. Back to Filesystem Selection"
        echo
        
        read -r -p "Select configuration: " choice
        case "$choice" in
            1)
                BTRFS_SUBVOLS=()
                # Pre-populate minimal
                add_subvol_entry "@" "/"
                edit_btrfs_layout && return 0
                ;;
            2)
                load_profile_simple
                # Ask to customize
                if confirmation_y_or_n "Do you want to customize this layout?" "cust_btrfs" "false"; then
                    edit_btrfs_layout && return 0
                else
                    return 0
                fi
                ;;
            3)
                load_profile_advanced
                if confirmation_y_or_n "Do you want to customize this layout?" "cust_btrfs" "false"; then
                    edit_btrfs_layout && return 0
                else
                    return 0
                fi
                ;;
            4)
                load_profile_smart
                if confirmation_y_or_n "Do you want to customize this layout?" "cust_btrfs" "false"; then
                    edit_btrfs_layout && return 0
                else
                    return 0
                fi
                ;;
            b|B)
                return 1 # Signal caller to go back
                ;;
            *)
                print_failed "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Serialize config to file (So Stage 2 or Partition script knows what to do)
save_btrfs_config() {
    # We save the array as a file to be sourced later or read line by line
    local config_out="/etc/archgate/btrfs_layout.conf"
    mkdir -p $(dirname "$config_out")
    
    echo "# Btrfs Subvolume Layout" > "$config_out"
    for entry in "${BTRFS_SUBVOLS[@]}"; do
        echo "$entry" >> "$config_out"
    done
    log_debug "Btrfs layout saved to $config_out"
}