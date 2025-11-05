#!/bin/bash
# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Source required modules
[[ -f "${0%/*}/colors.sh" ]] && source "${0%/*}/colors.sh"
[[ -f "${0%/*}/logging.sh" ]] && source "${0%/*}/logging.sh"

# Helper function to get partition paths safely (supports sdX and nvmeX)
get_part_path() {
    local disk="$1"
    local part_num="$2"
    local part_path=""

    # Force kernel to re-read partition table
    sync
    sleep 2
    partprobe "$disk" 2>/dev/null
    sync; sleep 2

    # Try lsblk first (most reliable)
    part_path=$(lsblk -no KNAME "$disk" | grep -E "${disk##*/}${part_num}$|${disk##*/}p${part_num}$" | head -n 1)
    if [[ -b "/dev/${part_path}" ]]; then
        echo "/dev/${part_path}"
        return 0
    fi
    
    # Fallback 1: nvme style (e.g., /dev/nvme0n1p2)
    if [[ -b "${disk}p${part_num}" ]]; then
        echo "${disk}p${part_num}"
        return 0
    fi
    
    # Fallback 2: sd style (e.g., /dev/sda2)
    if [[ -b "${disk}${part_num}" ]]; then
        echo "${disk}${part_num}"
        return 0
    fi

    print_failed "Could not determine path for partition $part_num on $disk"
    return 1
}

# Safely handle pacman lock: wait for existing pacman processes or remove stale lock
safe_handle_pacman_lock() {
    local lock_file="/var/lib/pacman/db.lck"
    local timeout=${1:-60}
    local waited=0

    # If lock doesn't exist, nothing to do
    if [[ ! -e "$lock_file" ]]; then
        return 0
    fi

    print_msg "Detected pacman lock at $lock_file — waiting up to ${timeout}s for release"

    while [[ -e "$lock_file" && $waited -lt $timeout ]]; do
        # If any pacman process is running, wait
        if command -v pgrep &>/dev/null && (pgrep -x pacman >/dev/null 2>&1 || pgrep -f pacman >/dev/null 2>&1); then
            sleep 0.5
            waited=$((waited + 1))
            continue
        fi

        # No pacman process detected. If lock is old, consider it stale and remove it.
        if command -v stat &>/dev/null; then
            local mtime
            mtime=$(stat -c %Y "$lock_file" 2>/dev/null || echo 0)
            if [[ $mtime -gt 0 ]]; then
                local age=$(( $(date +%s) - mtime ))
                # If older than 5 minutes, remove as stale
                if [[ $age -gt 300 ]]; then
                    print_warn "Removing stale pacman lock (age ${age}s): $lock_file"
                    rm -f "$lock_file" || return 1
                    return 0
                fi
            fi
        fi

        # Small sleep before re-check
        sleep 1
        waited=$((waited + 1))
    done

    if [[ -e "$lock_file" ]]; then
        print_warn "Pacman lock still present after ${timeout}s. Caller should decide whether to proceed."
        return 1
    fi

    return 0
}

function banner() {
    clear
    echo -e "${C}######################################################################${NC}"
    echo -e "${C}#                      Arch Gate Installer                          #${NC}"
    echo -e "${C}#           Universal Arch Linux Installation System                #${NC}"
    echo -e "${C}######################################################################${NC}"
    echo
}

function wait_for_keypress() {
    if ! read -n1 -s -r -p "${RB}[${C}-${RB}]${G} Press any key to continue, CTRL+c to cancel...${NC}" < /dev/tty; then
        echo
        print_failed "Could not read from terminal. Aborting."
        exit 1
    fi
    echo
}

function check_and_create_directory() {
    if [[ -n "$1" && ! -d "$1" ]]; then
        mkdir -p "$1" 2>/dev/null || {
            log_error "Failed to create directory: $1"
            return 1
        }
        log_debug "Created directory: $1"
    fi
}

function check_and_delete() {
    local files_folders
    for files_folders in "$@"; do
        if [[ -e "$files_folders" ]]; then
            rm -rf "$files_folders" >/dev/null 2>&1 || {
                log_error "Failed to delete: $files_folders"
                continue
            }
            log_debug "Deleted: $files_folders"
        fi
    done
}

function check_and_backup() {
    log_debug "Starting backup for: $*"
    local files_folders_list=("$@")
    local files_folders
    local date_str
    date_str=$(date +"%d-%m-%Y")

    for files_folders in "${files_folders_list[@]}"; do
        if [[ -e "$files_folders" ]]; then
            local backup="${files_folders}-${date_str}.bak"

            if [[ -e "$backup" ]]; then
                print_msg "Backup $backup already exists"
            else
                print_msg "Backing up $files_folders"
                mv "$files_folders" "$backup"
                log_debug "$files_folders $backup"
            fi
        else
            print_msg "Path $files_folders does not exist"
        fi
    done
}

function check_and_restore() {
    log_debug "Starting restore for: $*"
    local files_folders_list=("$@")
    local files_folders

    for files_folders in "${files_folders_list[@]}"; do
        local latest_backup
        latest_backup=$(find "$(dirname "$files_folders")" -maxdepth 1 -name "$(basename "$files_folders")-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9].bak" 2>/dev/null | sort | tail -n 1)

        if [[ -z "$latest_backup" ]]; then
            print_msg "No backup found for $files_folders"
            continue
        fi

        if [[ -e "$files_folders" ]]; then
            print_msg "File $files_folders already exists"
        else
            print_msg "Restoring $files_folders"
            mv "$latest_backup" "$files_folders"
            log_debug "$latest_backup $files_folders"
        fi
    done
}

function download_file() {
    local dest
    local url
    local max_retries=5
    local attempt=1
    local successful_attempt=0

    if [[ -z "$2" ]]; then
        url="$1"
        dest="$(basename "$url")"
    else
        dest="$1"
        url="$2"
    fi

    if [[ -z "$url" ]]; then
        print_failed "No URL provided!"
        return 1
    fi

    while [[ $attempt -le $max_retries ]]; do
        print_msg "Downloading $dest..."
        if [[ ! -s "$dest" ]]; then
            check_and_delete "$dest"
        fi

        if command -v wget &>/dev/null && command -v curl &>/dev/null; then
            if wget --spider --timeout=10 "$url" >/dev/null 2>&1; then
                wget --tries=5 --timeout=15 --retry-connrefused -O "$dest" "$url" 2>/dev/null
            elif curl -Is --max-time 10 "$url" >/dev/null 2>&1; then
                curl -# -L "$url" -o "$dest" 2>/dev/null
            else
                print_failed "Network unreachable for $url"
            fi
        elif command -v wget &>/dev/null; then
            wget --tries=5 --timeout=15 --retry-connrefused -O "$dest" "$url" 2>/dev/null
        elif command -v curl &>/dev/null; then
            curl -# -L "$url" -o "$dest" 2>/dev/null
        else
            print_failed "No download tool available (wget or curl)"
        fi

        if [[ -f "$dest" && -s "$dest" ]]; then
            successful_attempt=$attempt
            break
        else
            print_failed "Download failed. Retrying... ($attempt/$max_retries)"
        fi
        ((attempt++))
    done

    if [[ -f "$dest" ]]; then
        if [[ $successful_attempt -eq 1 ]]; then
            print_success "File downloaded successfully."
        else
            print_success "File downloaded successfully on attempt $successful_attempt."
        fi
        return 0
    fi

    print_failed "Failed to download the file after $max_retries attempts. Exiting."
    return 1
}

function confirmation_y_or_n() {
    local prompt="$1"
    local varname="${2:-}"
    local response

    while true; do
        print_msg "${prompt} (y/n)"
        if ! IFS= read -r response < /dev/tty; then
            echo
            print_failed "Input aborted (EOF)"
            echo
            return 1
        fi
        
        response="${response,,}"
        response="${response#"${response%%[![:space:]]*}"}"
        response="${response%"${response##*[![:space:]]}"}"

        if [[ -z "$response" || "$response" =~ [[:space:]/] ]]; then
            echo
            print_failed "Invalid input: no spaces or slashes allowed. Enter only 'y' or 'n'."
            echo
            continue
        fi

        case "$response" in
            y|yes) response="y" ;;
            n|no)  response="n" ;;
            *) 
                echo
                print_failed "Invalid input. Please enter 'y', 'yes', 'n', or 'no'."
                echo
                continue
                ;;
        esac

        if [[ -n "$varname" ]]; then
            printf -v "$varname" '%s' "$response"
            if declare -p CONFIG &>/dev/null && [[ "$(declare -p CONFIG)" == declare\ -A* ]]; then
                CONFIG["$varname"]="$response"
            fi
        fi

        if [[ "$response" == "y" ]]; then
            echo
            print_success "Continuing with answer: $response"
            echo
            log_debug "Confirmation: $prompt - response: $response"
            return 0
        else
            echo
            print_msg "${C}Skipping this step${NC}"
            echo
            log_debug "Confirmation: $prompt - response: $response"
            return 1
        fi
    done
}

function check_disk_space() {
    local required_gb=10
    local target_mount="${TARGET_MOUNT:-/mnt/usb}"
    local available_gb
    available_gb=$(df -BG "$target_mount" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ -z "$available_gb" ]]; then
        print_warn "Unable to determine available disk space on $target_mount"
        return 0
    fi

    if [ "$available_gb" -lt "$required_gb" ]; then
        print_failed "Insufficient disk space. Required: ${required_gb}G, Available: ${available_gb}G"
        exit 1
    fi
}

function create_pre_install_snapshot() {
    local snapshot_dir="/tmp/pre-install-snapshot"
    mkdir -p "$snapshot_dir"

    lsblk -f > "$snapshot_dir/partitions.txt" 2>/dev/null || true
    fdisk -l > "$snapshot_dir/fdisk.txt" 2>/dev/null || true

    print_success "Pre-install snapshot created at: $snapshot_dir"
}

function cleanup_on_exit() {
    print_msg "Cleaning up..."
    umount -R /mnt/usb 2>/dev/null || true
    rm -f /tmp/arch-install-* 2>/dev/null || true
}

function check_utf8_locale() {
    if command -v locale &>/dev/null; then
        local ch
        ch=$(locale charmap 2>/dev/null || echo "")
        if [[ "$ch" != "UTF-8" ]]; then
            print_warn "Non-UTF8 locale detected: '$ch' - Unicode glyphs may not render correctly"
        else
            log_debug "Locale charmap is UTF-8"
        fi
    else
        log_debug "locale command not available to check charset"
    fi
}

function select_an_option() {
    local max_option="$1"
    local default_option="${2:-1}"
    local varname="${3:-selection}"
    local selection
    
    while true; do
        if ! read -r selection < /dev/tty; then
            print_failed "Input aborted (EOF)"
            return 1
        fi
        
        # If empty, use default
        if [[ -z "$selection" ]]; then
            selection="$default_option"
        fi
        
        # Validate selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$max_option" ]]; then
            printf -v "$varname" '%s' "$selection"
            if declare -p CONFIG &>/dev/null && [[ "$(declare -p CONFIG)" == declare\ -A* ]]; then
                CONFIG["$varname"]="$selection"
            fi
            return 0
        else
            print_failed "Invalid selection. Please enter a number between 1 and $max_option:"
        fi
    done
}

function get_file_name_number() {
    local current_file
    current_file=$(basename "$0")
    local folder_name="${current_file%.sh}"
    local theme_number
    theme_number=$(echo "$folder_name" | grep -oE '[1-9][0-9]*')
    log_debug "Theme number: $theme_number"
    echo "$theme_number"
}

function extract_archive() {
    local archive="$1"
    if [[ ! -f "$archive" ]]; then
        print_failed "$archive doesn't exist"
        return 1
    fi

    case "$archive" in
    *.tar.gz | *.tgz)
        print_success "Extracting ${C}$archive"
        tar xzvf "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.tar.xz)
        print_success "Extracting ${C}$archive"
        tar xJvf "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.tar.bz2 | *.tbz2)
        print_success "Extracting ${C}$archive"
        tar xjvf "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.tar)
        print_success "Extracting ${C}$archive"
        tar xvf "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.bz2)
        print_success "Extracting ${C}$archive"
        bunzip2 -v "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.gz)
        print_success "Extracting ${C}$archive${NC}"
        gunzip -v "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.7z)
        print_success "Extracting ${C}$archive"
        7z x "$archive" -y 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.zip)
        print_success "Extracting ${C}$archive"
        unzip "${archive}" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.rar)
        print_success "Extracting ${C}$archive"
        unrar x "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *)
        print_failed "Unsupported archive format: ${C}$archive"
        return 1
        ;;
    esac
    print_success "Successfully extracted ${C}$archive"
    log_debug "Extracted: $archive"
}

function download_and_extract() {
    local url="$1"
    local target_dir="$2"
    local filename="${url##*/}"

    if [[ -n "$target_dir" ]]; then
        check_and_create_directory "$target_dir"
        cd "$target_dir" || return 1
    fi

    if download_file "$filename" "$url"; then
        if [[ -f "$filename" ]]; then
            echo
            extract_archive "$filename"
            check_and_delete "$filename"
        fi
    else
        print_failed "Failed to download ${C}${filename}"
        print_msg "${C}Please check your internet connection"
    fi
    log_debug "Downloaded and extracted: $url to $target_dir"
}

function count_subfolders() {
    local owner="$1"
    local repo="$2"
    local path="$3"
    local branch="$4"
    local response
    response=$(curl -s "https://api.github.com/repos/$owner/$repo/contents/$path?ref=$branch" 2>/dev/null)
    # Use jq to extract directories and count them; if none found then set to 0
    local subfolder_count
    subfolder_count=$(echo "$response" | jq -r '[.[] | select(.type == "dir")] | length' 2>/dev/null)
    echo "${subfolder_count:-0}"
    log_debug "Subfolder count: ${subfolder_count:-0}"
}

# get the latest version from a github releases
# ex. latest_tag=$(get_latest_release "$repo_owner" "$repo_name")
function get_latest_release() {
    local repo_owner="$1"
    local repo_name="$2"
    curl --silent \
        --location \
        --retry 5 \
        --retry-delay 1 \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${repo_owner}/${repo_name}/releases/latest" | jq -r '.tag_name'
}

function install_font_for_style() {
    local style_number="$1"
    local de_name="${de_name:-}"
    
    if [[ -z "$de_name" ]]; then
        print_warn "DE name not set, skipping font installation"
        return 1
    fi
    
    print_msg "Installing Fonts..."
    check_and_create_directory "$HOME/.fonts"
    download_and_extract "https://raw.githubusercontent.com/sabamdarif/termux-desktop/refs/heads/setup-files/setup-files/$de_name/look_${style_number}/font.tar.gz" "$HOME/.fonts"
    
    if command -v fc-cache &>/dev/null; then
        fc-cache -f 2>/dev/null
    fi
    cd "$HOME" || return 1
}

