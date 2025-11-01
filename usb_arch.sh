#!/bin/bash

# Detect color support
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
        # Terminal supports colors - define all colors
        # Basic colors (normal intensity)
        R="\033[31m"          # RST + red (#AA0000)
        G="\033[32m"          # RST + green (#00AA00)
        B="\033[34m"          # RST + blue (#0000AA)
        Y="\033[33m"          # RST + yellow (#AA5500)
        P="\033[35m"          # RST + pink/magenta (#AA00AA)
        C="\033[36m"          # RST + cyan (#00AAAA)
        W="\033[37m"          # RST + white (#AAAAAA)
        BLACK="\033[30m"      # RST + black (#000000)
        
        # Bold colors (light/bright intensity)
        RB="\033[1m\033[31m"  # RST + bold + red (#FF5555)
        GB="\033[1m\033[32m"  # RST + bold + green (#55FF55)
        BB="\033[1m\033[34m"  # RST + bold + blue (#5555FF)
        YB="\033[1m\033[33m"  # RST + bold + yellow (#FFFF55)
        PB="\033[1m\033[35m"  # RST + bold + pink/magenta (#FF55FF)
        CB="\033[1m\033[36m"  # RST + bold + cyan (#55FFFF)
        WB="\033[1m\033[37m"  # RST + bold + white (#FFFFFF)
        BLACKB="\033[1m\033[30m" # RST + bold + black (#555555)
        
        # Special modifiers
        BOLD="\033[1m"               # bold only
        NC="\033[0m"                 # reset all attributes
    else
        # Terminal doesn't support colors
        R="" G="" B="" Y="" P="" C="" W="" BLACK=""
        RB="" GB="" BB="" YB="" PB="" CB="" WB="" BLACKB=""
        BOLD="" NC=""
    fi
else
    # Output to file or pipe, or tput not available
    R="" G="" B="" Y="" P="" C="" W="" BLACK=""
    RB="" GB="" BB="" YB="" PB="" CB="" WB="" BLACKB=""
    BOLD="" NC=""
fi
: <<'IGNORE'
#  --- IGNORE ---
Alternative color detection method (commented out)
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
        # Define common prefixes once
        RST="$(printf '\033[0m')"
        BOLD_PFX="$(printf '\033[1m')"
        
        # Basic colors (normal intensity)
        R="${RST}$(printf '\033[31m')"          # RST + red
        G="${RST}$(printf '\033[32m')"          # RST + green
        B="${RST}$(printf '\033[34m')"          # RST + blue
        Y="${RST}$(printf '\033[33m')"          # RST + yellow
        P="${RST}$(printf '\033[35m')"          # RST + pink/magenta
        C="${RST}$(printf '\033[36m')"          # RST + cyan
        W="${RST}$(printf '\033[37m')"          # RST + white
        BLACK="${RST}$(printf '\033[30m')"      # RST + black
        
        # Bold colors (light/bright intensity)
        RB="${RST}${BOLD_PFX}$(printf '\033[31m')"  # RST + bold + red
        GB="${RST}${BOLD_PFX}$(printf '\033[32m')"  # RST + bold + green
        BB="${RST}${BOLD_PFX}$(printf '\033[34m')"  # RST + bold + blue
        YB="${RST}${BOLD_PFX}$(printf '\033[33m')"  # RST + bold + yellow
        PB="${RST}${BOLD_PFX}$(printf '\033[35m')"  # RST + bold + pink/magenta
        CB="${RST}${BOLD_PFX}$(printf '\033[36m')"  # RST + bold + cyan
        WB="${RST}${BOLD_PFX}$(printf '\033[37m')"  # RST + bold + white
        BLACKB="${RST}${BOLD_PFX}$(printf '\033[30m')" # RST + bold + black
        
        # Special modifiers
        BOLD="${BOLD_PFX}"
        NC="${RST}"
    else
        # Terminal doesn't support colors - set all to empty
        R="" G="" B="" Y="" P="" C="" W="" BLACK=""
        RB="" GB="" BB="" YB="" PB="" CB="" WB="" BLACKB=""
        BOLD="" NC=""
    fi
else
    # Output to file or pipe - set all to empty
    R="" G="" B="" Y="" P="" C="" W="" BLACK=""
    RB="" GB="" BB="" YB="" PB="" CB="" WB="" BLACKB=""
    BOLD="" NC=""
fi
IGNORE

# =============================================================================
# ADVANCED LOGGING SYSTEM (Integrated with color system)
# =============================================================================

# Logging configuration
LOG_DIR="/var/log/arch_usb"
LOG_FILE="${LOG_DIR}/arch_usb.log"
LOG_MAX_BYTES=$((1024*1024*5))   # rotate at 5MB
LOG_BACKUPS=3
LOG_LEVEL="INFO"
SYSLOG_ENABLED=0

# Internal logging variables
_LOG_FD=200
_LOG_INITIALIZED=0

# Numeric levels for comparison
declare -A _LOG_LEVELS=(
    [DEBUG]=10 [INFO]=20 [NOTICE]=25 [WARN]=30 [ERROR]=40 [CRITICAL]=50
)

##########################
# Utility: level helpers #
##########################
_log_level_to_num() {
    local lvl="${1^^}"
    echo "${_LOG_LEVELS[$lvl]:-${_LOG_LEVELS[INFO]}}"
}

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

_should_log() {
    local want="$1"
    local wantn=$(_log_level_to_num "$want")
    local currn=$(_log_level_to_num "$LOG_LEVEL")
    (( wantn >= currn ))
}

#####################
# Log rotation file #
#####################
_rotate_if_needed() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -c%s -- "$LOG_FILE" 2>/dev/null || echo 0)
        if (( size >= LOG_MAX_BYTES )); then
            for ((i=LOG_BACKUPS-1;i>=1;i--)); do
                if [[ -f "${LOG_FILE}.${i}" ]]; then
                    mv -f "${LOG_FILE}.${i}" "${LOG_FILE}.$((i+1))" 2>/dev/null || true
                fi
            done
            if [[ -f "$LOG_FILE" ]]; then
                mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
            fi
        fi
    fi
}

########################
# Initialize / Cleanup #
########################
init_logger() {
    if (( _LOG_INITIALIZED )); then return 0; fi
    
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || {
        echo "Error: Cannot create log directory $(dirname "$LOG_FILE")" >&2
        return 1
    }

    _rotate_if_needed

    eval "exec ${_LOG_FD}>>\"$LOG_FILE\"" || {
        echo "Warning: cannot open log file $LOG_FILE for append; logging to stdout only" >&2
        _LOG_FD=1
    }

    _LOG_INITIALIZED=1
    trap 'close_logger' EXIT INT TERM
    
    log_info "Logging system initialized (Level: $LOG_LEVEL, File: $LOG_FILE)"
}

close_logger() {
    if (( _LOG_INITIALIZED )) && [[ $_LOG_FD -ne 1 ]]; then
        eval "exec ${_LOG_FD}>&-"
        _LOG_INITIALIZED=0
    fi
}

# -----------------------------------------------------------------------------
# Pre-installation checks and cleanup handlers
# -----------------------------------------------------------------------------

# Cleanup handler invoked on script exit or interrupt to unmount targets and
# remove temporary files created during the installation process.
cleanup_on_exit() {
    print_msg "Cleaning up..."
    # Attempt to unmount any mounts under /mnt/usb
    umount -R /mnt/usb 2>/dev/null || true
    # Remove temporary install artifacts
    rm -f /tmp/arch-install-* 2>/dev/null || true
}

# Ensure cleanup_on_exit runs on EXIT and on common termination signals
trap 'cleanup_on_exit' EXIT INT TERM


# Check that there's sufficient disk space on the target mount before
# starting destructive operations. This is a conservative check; some
# operations may require less, but 10GB is a reasonable minimum for a
# full Arch system with extra packages.
function check_disk_space() {
    local required_gb=10
    # Use the mountpoint we operate on; default to /mnt/usb if not set
    local target_mount="${TARGET_MOUNT:-/mnt/usb}"
    # Obtain available space in GB (rounded down)
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


# Create a small snapshot of the system state before performing destructive
# actions so that some basic diagnostics can be recovered if something goes
# wrong during installation.
function create_pre_install_snapshot() {
    local snapshot_dir="/tmp/pre-install-snapshot"
    mkdir -p "$snapshot_dir"

    # Save partition layout and disk information
    lsblk -f > "$snapshot_dir/partitions.txt" 2>/dev/null || true
    fdisk -l > "$snapshot_dir/fdisk.txt" 2>/dev/null || true

    print_success "Pre-install snapshot created at: $snapshot_dir"
}

########################
# Core logging routine #
########################
_log_write() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local pid="$$"
    local caller_info=""
    
    if [[ ${FUNCNAME[2]+_} ]]; then
        caller_info="${FUNCNAME[2]}:${BASH_LINENO[1]}"
    fi

    local line="[${ts}] ${level} [pid:${pid}] ${caller_info:+(${caller_info}) }${msg}"

    if (( _LOG_INITIALIZED )) && [[ $_LOG_FD -ne 1 ]]; then
        printf '%s
' "$line" >&"${_LOG_FD}" 2>/dev/null || true
    else
        printf '%s
' "$line"
    fi

    if (( SYSLOG_ENABLED )); then
        local pri="user.info"
        case "$level" in
            DEBUG) pri="user.debug" ;;
            INFO) pri="user.info" ;;
            NOTICE) pri="user.notice" ;;
            WARN) pri="user.warning" ;;
            ERROR) pri="user.err" ;;
            CRITICAL) pri="user.crit" ;;
        esac
        logger -p "$pri" -t "usb-arch" -- "$msg" 2>/dev/null || true
    fi
}

########################
# Public log functions #
########################
log_debug()    { _should_log DEBUG    && _log_write DEBUG    "$*" ; }
log_info()     { _should_log INFO     && _log_write INFO     "$*" ; }
log_notice()   { _should_log NOTICE   && _log_write NOTICE   "$*" ; }
log_warn()     { _should_log WARN     && _log_write WARN     "$*" ; }
log_error()    { _should_log ERROR    && _log_write ERROR    "$*" ; }
log_critical() { _should_log CRITICAL && _log_write CRITICAL "$*" ; }

########################
# Console color mapping#
########################
_level_color_prefix() {
    local level="$1"
    case "${level^^}" in
        DEBUG)  printf '%s' "${BLACKB}" ;;
        INFO)   printf '%s' "${C}" ;;
        NOTICE) printf '%s' "${G}" ;;
        WARN)   printf '%s' "${Y}${BOLD}" ;;
        ERROR)  printf '%s' "${R}${BOLD}" ;;
        CRITICAL) printf '%s' "${RB}" ;;
        *) printf '%s' "${NC}" ;;
    esac
}

########################
# print_* wrappers     #
########################
print_log_console() {
    local level="$1"; shift
    local msg="$*"
    local color_prefix
    color_prefix="$(_level_color_prefix "$level")"
    local reset="${NC}"

    if [ -t 1 ]; then
        printf '%b%s%b
' "${color_prefix}" "${msg}" "${reset}"
    else
        printf '%s
' "$msg"
    fi

    case "${level^^}" in
        DEBUG)    log_debug "$msg"    ;;
        INFO)     log_info "$msg"     ;;
        NOTICE)   log_notice "$msg"   ;;
        WARN)     log_warn "$msg"     ;;
        ERROR)    log_error "$msg"    ;;
        CRITICAL) log_critical "$msg" ;;
        *)        log_info "$msg"     ;;
    esac
}

# Enhanced print functions with logging
print_success() { print_log_console NOTICE "[✓] $*"; }
print_msg()     { print_log_console INFO "[-] $*"; }
print_warn()    { print_log_console WARN "[!] $*"; }
print_failed()  { print_log_console ERROR "[✗] $*"; }
print_debug()   { print_log_console DEBUG "[#] $*"; }
print_critical(){ print_log_console CRITICAL "[‼] $*"; }

########################
# Control helpers      #
########################
set_log_level() {
    local lvl="${1^^}"
    if [[ -n "${_LOG_LEVELS[$lvl]:-}" ]]; then
        LOG_LEVEL="$lvl"
        print_msg "Log level set to: $lvl"
    else
        print_warn "Unknown log level: $1"
    fi
}

set_log_file() {
    local f="$1"
    if [[ -z "$f" ]]; then
        print_warn "Usage: set_log_file /path/to/file"
        return 1
    fi
    LOG_FILE="$f"
    if (( _LOG_INITIALIZED )); then
        # Flush filesystem buffers to reduce chance of lost log lines
        sync
        sleep 0.1
        close_logger
        init_logger
    fi
}

# Check locale charset for UTF-8 support (warn if not UTF-8)
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

enable_syslog()  { SYSLOG_ENABLED=1; print_msg "Syslog enabled"; }
disable_syslog() { SYSLOG_ENABLED=0; print_msg "Syslog disabled"; }

# =============================================================================
# ORIGINAL SIMPLE PRINT FUNCTIONS (Backup - comment if using advanced system)
# =============================================================================
: '
# Helper functions for displaying messages (Simple version)
function print_msg() {
    local msg="$1"
    echo -e "${RB}[${C}-${RB}]${B} $msg ${NC}"
}

function print_success() {
    local msg="$1"
    echo -e "${RB}[${GB}✓${RB}]${GB} $msg ${NC}"
}

function print_failed() {
    local msg="$1"
    echo -e "${RB}[${RB}☓${RB}]${RB} $msg ${NC}"
}

function print_warn() {
    local msg="$1"
    echo -e "${RB}[${Y}!${RB}]${Y} $msg ${NC}"
}
'

# =============================================================================
# INITIALIZE LOGGING SYSTEM
# =============================================================================
init_logger
check_utf8_locale

# -----------------------------------------------------------------------------
# Cache cleaning configuration
# AUTO_CLEAN_CACHE: if false, no automatic cache cleaning will be performed
# CACHE_CLEAN_STRATEGY: one of immediate|batch|smart
# CACHE_BATCH_THRESHOLD: how many installs before batch cleaning
# -----------------------------------------------------------------------------
AUTO_CLEAN_CACHE="${AUTO_CLEAN_CACHE:-true}"
CACHE_CLEAN_STRATEGY="${CACHE_CLEAN_STRATEGY:-immediate}"   # immediate|batch|smart
CACHE_BATCH_THRESHOLD="${CACHE_BATCH_THRESHOLD:-5}"
# Counter for batch cleaning
CACHE_BATCH_COUNTER=0


function banner() {
    # clear
    echo -e "${C}######################################################################${NC}"
    echo -e "${C}#                      Arch Linux USB Installer                      #${NC}"
    echo -e "${C}######################################################################${NC}"
    echo
}

function wait_for_keypress() {
    read -n1 -s -r -p "${RB}[${C}-${RB}]${G} Press any key to continue, CTRL+c to cancel...${NC}"
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

# first check then delete
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

# first check then backup
function check_and_backup() {
    log_debug "Starting backup for: $*"
    # shellcheck disable=SC2206
    local files_folders_list=($@)
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

# find a backup file which end with a number pattern and restore it
function check_and_restore() {
    log_debug "Starting restore for: $*"
    # shellcheck disable=SC2206
    local files_folders_list=($@)
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

        # Prefer the tool that can actually reach the URL. If both are present, test reachability.
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
        if ! command -v bunzip2 &>/dev/null; then
            print_failed "bunzip2 not available to extract ${C}$archive"
            return 1
        fi
        bunzip2 -v "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.gz)
        print_success "Extracting ${C}$archive${NC}"
        if ! command -v gunzip &>/dev/null; then
            print_failed "gunzip not available to extract ${C}$archive"
            return 1
        fi
        gunzip -v "$archive" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.7z)
        print_success "Extracting ${C}$archive"
        if ! command -v 7z &>/dev/null; then
            print_failed "7z (p7zip) not available to extract ${C}$archive"
            return 1
        fi
        7z x "$archive" -y 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.zip)
        print_success "Extracting ${C}$archive"
        if ! command -v unzip &>/dev/null; then
            print_failed "unzip not available to extract ${C}$archive"
            return 1
        fi
        unzip "${archive}" 2>/dev/null || {
            print_failed "Failed to extract ${C}$archive"
            return 1
        }
        ;;
    *.rar)
        print_success "Extracting ${C}$archive"
        if ! command -v unrar &>/dev/null; then
            print_failed "unrar not available to extract ${C}$archive"
            return 1
        fi
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

# download a archive file and extract it in a folder
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

# Improved confirmation: secure + strict validation + CONFIG support + proper return codes
function confirmation_y_or_n() {
    local prompt="$1"
    local varname="${2:-}"
    local response

    # loop until valid
    while true; do
        print_msg "${prompt} (y/n)"
        # read one line, trim surrounding whitespace
        if ! IFS= read -r response; then
            # EOF or pipe closed
            echo
            print_failed "Input aborted (EOF)"
            echo
            return 1
        fi
        # lowercase
        response="${response,,}"
        # trim leading/trailing spaces (bash)
        response="${response#"${response%%[![:space:]]*}"}"
        response="${response%"${response##*[![:space:]]}"}"

        # reject empty, spaces inside, or slashes
        if [[ -z "$response" || "$response" =~ [[:space:]/] ]]; then
            echo
            print_failed "Invalid input: no spaces or slashes allowed. Enter only 'y' or 'n'."
            echo
            continue
        fi

        # normalize full words
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

        # store in CONFIG if provided and exists
        if [[ -n "$varname" ]]; then
            # safe assign: printf -v
            printf -v "$varname" '%s' "$response"
            # also set CONFIG associative if defined
            if declare -p CONFIG &>/dev/null && [[ "$(declare -p CONFIG)" == declare\ -A* ]]; then
                CONFIG["$varname"]="$response"
            fi
        fi

        # logging / feedback
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

# Check if running as root
### ---------------------------------------------------------------------------
# PACKAGE MANAGEMENT SYSTEM - Supports pacman, pacstrap, and AUR
### ---------------------------------------------------------------------------

# Global variables for package management
PACKAGE_MANAGER="pacman"
AUR_HELPER="yay"
ENABLE_AUR=false

# Function to detect and set AUR helper
function detect_aur_helper() {
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        ENABLE_AUR=true
        log_debug "AUR helper detected: yay"
    elif command -v paru &>/dev/null; then
        AUR_HELPER="paru"
        ENABLE_AUR=true
        log_debug "AUR helper detected: paru"
    else
        ENABLE_AUR=false
        log_debug "No AUR helper found"
    fi
}

# Function to install AUR helper
function install_aur_helper() {
    local helper_choice="${1:-yay}"
    
    if [[ "$ENABLE_AUR" == "true" ]]; then
        print_success "AUR helper already installed: $AUR_HELPER"
        return 0
    fi

    print_msg "Installing AUR helper: $helper_choice"
    
    case "$helper_choice" in
        "yay")
            package_install_pacman "base-devel git" || return 1
            cd /tmp || return 1
            git clone https://aur.archlinux.org/yay.git || return 1
            cd yay || return 1
            # Ensure makepkg is available (base-devel). If not, install base-devel.
            if ! command -v makepkg &>/dev/null; then
                print_msg "makepkg not found; installing base-devel"
                package_install_pacman "base-devel" || return 1
            fi
            makepkg -si --noconfirm || return 1
            cd ..
            rm -rf yay
            AUR_HELPER="yay"
            ;;
        "paru")
            package_install_pacman "base-devel git" || return 1
            cd /tmp || return 1
            git clone https://aur.archlinux.org/paru.git || return 1
            cd paru || return 1
            # Ensure makepkg is available (base-devel). If not, install base-devel.
            if ! command -v makepkg &>/dev/null; then
                print_msg "makepkg not found; installing base-devel"
                package_install_pacman "base-devel" || return 1
            fi
            makepkg -si --noconfirm || return 1
            cd ..
            rm -rf paru
            AUR_HELPER="paru"
            ;;
        *)
            print_failed "Unknown AUR helper: $helper_choice"
            return 1
            ;;
    esac

    if command -v "$AUR_HELPER" &>/dev/null; then
        ENABLE_AUR=true
        print_success "AUR helper installed successfully: $AUR_HELPER"
        return 0
    else
        print_failed "Failed to install AUR helper: $helper_choice"
        return 1
    fi
}

# Core package installation function with multiple backends
function package_install_and_check() {
    local packs_list="$*"
    local install_success=true
    
    log_debug "Starting package installation for: $packs_list"
    
    # Split package list
    IFS=' ' read -r -a packs_array <<< "$packs_list"
    
    for package_name in "${packs_array[@]}"; do
        if [[ -z "$package_name" ]]; then
            continue
        fi
        
        # Check if package contains AUR prefix
        if [[ "$package_name" == aur/* ]]; then
            local aur_package="${package_name#aur/}"
            if [[ "$ENABLE_AUR" == "true" ]]; then
                package_install_aur "$aur_package" || install_success=false
            else
                print_warn "AUR not enabled, skipping: $aur_package"
                install_success=false
            fi
        else
            # Try pacman first, then pacstrap if available
            if command -v pacman &>/dev/null; then
                package_install_pacman "$package_name" || install_success=false
            elif command -v pacstrap &>/dev/null; then
                package_install_pacstrap "$package_name" || install_success=false
            else
                print_failed "No package manager available"
                return 1
            fi
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# pacman installation function
function package_install_pacman() {
    local package_name="$1"
    local retry_count=0
    local max_retries=5
    local install_success=false
    
    # Handle wildcard patterns
    if [[ "$package_name" == *"*"* ]]; then
        log_debug "Processing wildcard pattern: $package_name"
        local packages
        packages=$(pacman -Ssq 2>/dev/null | grep -E "^${package_name//\*/.*}$")
        
        if [[ -z "$packages" ]]; then
            print_warn "No packages found matching pattern: $package_name"
            return 1
        fi
        
        log_debug "Matched packages: $packages"
        
        for package in $packages; do
            if ! package_install_pacman_single "$package"; then
                return 1
            fi
        done
        return 0
    else
        package_install_pacman_single "$package_name"
    fi
}

function package_install_pacman_single() {
    local package_name="$1"
    local retry_count=0
    local max_retries=5
    local install_success=false
    
    # Check if package is already installed
    if pacman -Qi "$package_name" &>/dev/null; then
        print_success "Package already installed: ${C}$package_name"
        return 0
    fi
    
    while [[ "$retry_count" -lt "$max_retries" && "$install_success" == false ]]; do
        retry_count=$((retry_count + 1))
        
        # Wait for pacman lock to be released or remove if stale (safer than unconditional delete)
        safe_handle_pacman_lock 60 || print_warn "pacman lock handling returned non-zero"
        
        print_msg "Installing package (pacman): ${C}$package_name"
        
                if pacman -S --noconfirm --needed "$package_name" 2>/dev/null; then
            if pacman -Qi "$package_name" &>/dev/null; then
                    print_success "Successfully installed package: ${C}$package_name"
                    install_success=true

                    # Post-install cache handling according to strategy
                    handle_post_install_cache_clean "$package_name"
            else
                print_warn "Package installed but verification failed: ${C}$package_name"
            fi
        else
            print_warn "Failed to install package: ${C}$package_name. Retrying... ($retry_count/$max_retries)"
            
            # Refresh package database on failure
            pacman -Sy --noconfirm 2>/dev/null
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        print_failed "Failed to install package after $max_retries attempts: ${C}$package_name"
        return 1
    fi
}

# pacstrap installation function (for chroot environments)
function package_install_pacstrap() {
    local package_name="$1"
    local chroot_dir="${2:-/mnt}"
    local retry_count=0
    local max_retries=5
    local install_success=false
    
    print_msg "Installing package (pacstrap): ${C}$package_name"
    
    while [[ "$retry_count" -lt "$max_retries" && "$install_success" == false ]]; do
        retry_count=$((retry_count + 1))
        
        if pacstrap -c -K "$chroot_dir" "$package_name" 2>/dev/null; then
            # Verify installation in chroot
            if arch-chroot "$chroot_dir" pacman -Qi "$package_name" &>/dev/null; then
                print_success "Successfully installed package in chroot: ${C}$package_name"
                install_success=true
            else
                print_warn "Package installed in chroot but verification failed: ${C}$package_name"
            fi
        else
            print_warn "Failed to install package in chroot: ${C}$package_name. Retrying... ($retry_count/$max_retries)"
            
            # Update package database in chroot
            arch-chroot "$chroot_dir" pacman -Sy --noconfirm 2>/dev/null
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        print_failed "Failed to install package in chroot after $max_retries attempts: ${C}$package_name"
        return 1
    fi
}

# AUR installation function
function package_install_aur() {
    local package_name="$1"
    local retry_count=0
    local max_retries=3
    local install_success=false
    
    if [[ "$ENABLE_AUR" != "true" ]]; then
        print_failed "AUR not enabled. Please install an AUR helper first."
        return 1
    fi
    
    print_msg "Installing AUR package (${AUR_HELPER}): ${C}$package_name"
    
    while [[ "$retry_count" -lt "$max_retries" && "$install_success" == false ]]; do
        retry_count=$((retry_count + 1))
        
        case "$AUR_HELPER" in
            "yay")
                if yay -S --noconfirm --needed "$package_name" 2>/dev/null; then
                    if yay -Qi "$package_name" &>/dev/null || pacman -Qi "$package_name" &>/dev/null; then
                        print_success "Successfully installed AUR package: ${C}$package_name"
                        install_success=true
                        # Post-install cache handling according to strategy
                        handle_post_install_cache_clean "$package_name"
                    fi
                fi
                ;;
            "paru")
                if paru -S --noconfirm --needed "$package_name" 2>/dev/null; then
                    if paru -Qi "$package_name" &>/dev/null || pacman -Qi "$package_name" &>/dev/null; then
                        print_success "Successfully installed AUR package: ${C}$package_name"
                        install_success=true
                        # Post-install cache handling according to strategy
                        handle_post_install_cache_clean "$package_name"
                    fi
                fi
                ;;
        esac
        
        if [[ "$install_success" != "true" ]]; then
            print_warn "Failed to install AUR package: ${C}$package_name. Retrying... ($retry_count/$max_retries)"
        fi
    done
    
    if [[ "$install_success" == "true" ]]; then
        return 0
    else
        print_failed "Failed to install AUR package after $max_retries attempts: ${C}$package_name"
        return 1
    fi
}

# Clean package caches for pacman and AUR helpers
function clean_package_cache() {
    local silent="${1:-false}"
    if [[ "$silent" != "true" ]]; then
        print_msg "Cleaning package caches..."
    fi

    # pacman: remove uninstalled package files and clear old cache
    pacman -Sc --noconfirm >/dev/null 2>&1 || true

    # AUR helpers caches
    if [[ "${ENABLE_AUR:-false}" == "true" ]]; then
        case "${AUR_HELPER:-}" in
            yay) yay -Sc --noconfirm >/dev/null 2>&1 || true ;; 
            paru) paru -Sc --noconfirm >/dev/null 2>&1 || true ;; 
        esac
    fi

    # Remove any leftover package files
    find /var/cache/pacman/pkg/ -maxdepth 1 -type f -delete 2>/dev/null || true
    rm -rf ~/.cache/yay/* ~/.cache/paru/* 2>/dev/null || true

    if [[ "$silent" != "true" ]]; then
        print_success "Package caches cleaned"
    fi
}

# Smart cache cleaning logic for large packages or batching
function smart_cache_clean() {
    local package_name="$1"
    # Try to detect installed size; fall back to cleaning always if unknown
    local pkg_info
    pkg_info=$(pacman -Si "$package_name" 2>/dev/null || true)
    if [[ -z "$pkg_info" ]]; then
        # Unknown package info; do not bail - just return
        return 0
    fi

    local size_line
    size_line=$(printf "%s" "$pkg_info" | awk -F": " '/Installed Size/ {print $2}')
    if [[ -z "$size_line" ]]; then
        return 0
    fi

    # Parse size (e.g., 12.34 MiB or 1.2 GiB)
    if [[ "$size_line" =~ ([0-9.]+)\s*([MG]i?B) ]]; then
        local size_val=${BASH_REMATCH[1]}
        local size_unit=${BASH_REMATCH[2]}

        # Convert to MB for comparison
        local size_mb=0
        if [[ "$size_unit" == "GiB" || "$size_unit" == "GB" ]]; then
            size_mb=$(printf "%d" "$(echo "$size_val * 1024" | bc)")
        else
            size_mb=$(printf "%d" "$(echo "$size_val" | bc)")
        fi

        if [[ $size_mb -ge 50 ]]; then
            clean_package_cache true
        fi
    fi
}

# Handle post-install cache cleaning according to configured strategy
function handle_post_install_cache_clean() {
    local pkg="$1"
    # Respect global toggle
    if [[ "${AUTO_CLEAN_CACHE,,}" == "false" ]]; then
        return 0
    fi

    case "${CACHE_CLEAN_STRATEGY}" in
        immediate)
            clean_package_cache true
            ;;
        smart)
            smart_cache_clean "$pkg"
            ;;
        batch)
            CACHE_BATCH_COUNTER=$((CACHE_BATCH_COUNTER + 1))
            if (( CACHE_BATCH_COUNTER % CACHE_BATCH_THRESHOLD == 0 )); then
                clean_package_cache true
            fi
            ;;
        *)
            # Unknown strategy: default to immediate
            clean_package_cache true
            ;;
    esac
}

# Package removal function with multiple backends
function package_check_and_remove() {
    local packs_list="$*"
    
    log_debug "Starting package removal for: $packs_list"
    
    IFS=' ' read -r -a packs_array <<< "$packs_list"
    
    for package_name in "${packs_array[@]}"; do
        if [[ -z "$package_name" ]]; then
            continue
        fi
        
        # Check AUR packages
        if [[ "$package_name" == aur/* ]]; then
            local aur_package="${package_name#aur/}"
            package_remove_aur "$aur_package"
        else
            package_remove_pacman "$package_name"
        fi
    done
}

function package_remove_pacman() {
    local package_name="$1"
    local retry_count=0
    local max_retries=3
    local remove_success=false
    
    # Handle wildcard patterns
    if [[ "$package_name" == *"*"* ]]; then
        log_debug "Processing wildcard pattern for removal: $package_name"
        local packages
        packages=$(pacman -Qsq 2>/dev/null | grep -E "^${package_name//\*/.*}$")
        
        if [[ -z "$packages" ]]; then
            print_success "No installed packages found matching pattern: ${C}$package_name"
            return 0
        fi
        
        log_debug "Matched packages for removal: $packages"
        
        for package in $packages; do
            if ! package_remove_pacman_single "$package"; then
                return 1
            fi
        done
        return 0
    else
        package_remove_pacman_single "$package_name"
    fi
}

function package_remove_pacman_single() {
    local package_name="$1"
    local retry_count=0
    local max_retries=3
    local remove_success=false
    
    if ! pacman -Qi "$package_name" &>/dev/null; then
        print_success "Package not installed: ${C}$package_name"
        return 0
    fi
    
    while [[ "$retry_count" -lt "$max_retries" && "$remove_success" == false ]]; do
        retry_count=$((retry_count + 1))
        
        # Wait for pacman lock to be released or remove if stale (safer than unconditional delete)
        safe_handle_pacman_lock 60 || print_warn "pacman lock handling returned non-zero"
        print_msg "Removing package: ${C}$package_name"
        
        if pacman -Rns --noconfirm "$package_name" 2>/dev/null; then
            if ! pacman -Qi "$package_name" &>/dev/null; then
                print_success "Successfully removed package: ${C}$package_name"
                remove_success=true
            fi
        else
            print_warn "Failed to remove package: ${C}$package_name. Retrying... ($retry_count/$max_retries)"
        fi
    done
    
    if [[ "$remove_success" == "true" ]]; then
        return 0
    else
        print_failed "Failed to remove package after $max_retries attempts: ${C}$package_name"
        return 1
    fi
}

function package_remove_aur() {
    local package_name="$1"
    
    if [[ "$ENABLE_AUR" != "true" ]]; then
        print_failed "AUR not enabled"
        return 1
    fi
    
    print_msg "Removing AUR package: ${C}$package_name"
    
    case "$AUR_HELPER" in
        "yay")
            yay -Rns --noconfirm "$package_name" 2>/dev/null
            ;;
        "paru")
            paru -Rns --noconfirm "$package_name" 2>/dev/null
            ;;
    esac
    
    if ! pacman -Qi "$package_name" &>/dev/null; then
        print_success "Successfully removed AUR package: ${C}$package_name"
        return 0
    else
        print_failed "Failed to remove AUR package: ${C}$package_name"
        return 1
    fi
}

# Function to update all packages (official + AUR)
function package_update_all() {
    print_msg "Updating system packages..."
    
    # Update official repositories
    if ! pacman -Syu --noconfirm; then
        print_failed "Failed to update official packages"
        return 1
    fi
    
    # Update AUR packages if enabled
    if [[ "$ENABLE_AUR" == "true" ]]; then
        print_msg "Updating AUR packages..."
        case "$AUR_HELPER" in
            "yay")
                yay -Syu --noconfirm --devel
                ;;
            "paru")
                paru -Syu --noconfirm
                ;;
        esac
    fi
    
    print_success "System update completed"
}

# Function to clean package caches
function package_clean_cache() {
    print_msg "Cleaning package caches..."
    
    # Clean pacman cache
    pacman -Sc --noconfirm
    
    # Clean AUR cache if enabled
    if [[ "$ENABLE_AUR" == "true" ]]; then
        case "$AUR_HELPER" in
            "yay")
                yay -Sc --noconfirm
                ;;
            "paru")
                paru -Sc --noconfirm
                ;;
        esac
    fi
    
    print_success "Package caches cleaned"
}

# Function to query package information
function package_query_info() {
    local package_name="$1"
    
    if [[ "$package_name" == aur/* ]]; then
        local aur_package="${package_name#aur/}"
        if [[ "$ENABLE_AUR" == "true" ]]; then
            case "$AUR_HELPER" in
                "yay")
                    yay -Qi "$aur_package"
                    ;;
                "paru")
                    paru -Qi "$aur_package"
                    ;;
            esac
        else
            print_failed "AUR not enabled"
        fi
    else
        pacman -Qi "$package_name"
    fi
}

# Function to search for packages
function package_search() {
    local search_term="$1"
    
    print_msg "Searching for packages: $search_term"
    
    # Search official repositories
    echo -e "${C}Official repositories:${NC}"
    pacman -Ss "$search_term" || echo "No results in official repositories"
    
    # Search AUR if enabled
    if [[ "$ENABLE_AUR" == "true" ]]; then
        echo -e "\n${C}AUR packages:${NC}"
        case "$AUR_HELPER" in
            "yay")
                yay -Ss "$search_term" || echo "No results in AUR"
                ;;
            "paru")
                paru -Ss "$search_term" || echo "No results in AUR"
                ;;
        esac
    fi
}

# Initialize package management system
function init_package_manager() {
    detect_aur_helper
    log_debug "Package manager initialized: $PACKAGE_MANAGER, AUR: $ENABLE_AUR ($AUR_HELPER)"
}

# Auto-initialize on script load
init_package_manager

# -----------------------------------------------------------------------------
# Dependency check and auto-install
# -----------------------------------------------------------------------------
function check_dependencies() {
    local deps=(
        pacman git makepkg wget curl parted lsblk blkid mkfs.ext4 mkfs.fat
        dkms modprobe systemctl udevadm tput
    )

    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            print_warn "Dependency missing: $cmd"
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_debug "All dependencies present"
        return 0
    fi

    # Try to auto-install missing deps if pacman is available
    if command -v pacman &>/dev/null; then
        print_msg "Attempting to install missing dependencies via pacman: ${missing[*]}"
        for pkg in "${missing[@]}"; do
            # Use wrapper where possible for retries
            if ! package_install_and_check "$pkg"; then
                print_warn "Auto-install failed for $pkg; attempting direct pacman"
                # Use sudo if available (some live ISOs may not have sudo)
                if command -v sudo &>/dev/null; then
                    sudo_cmd="sudo"
                else
                    sudo_cmd=""
                    print_warn "sudo not found; using direct root pacman invocation"
                fi

                if ! $sudo_cmd pacman -S --noconfirm --needed "$pkg" &>/dev/null; then
                    print_failed "Failed to install dependency: $pkg"
                else
                    print_success "Installed dependency: $pkg"
                fi
            else
                print_success "Installed dependency: $pkg"
            fi
        done
    else
        print_failed "pacman not available; cannot auto-install missing dependencies: ${missing[*]}"
        return 1
    fi

    # Re-check after attempted installs
    local still_missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            still_missing+=("$cmd")
        fi
    done

    if [[ ${#still_missing[@]} -ne 0 ]]; then
        print_failed "Still missing required commands: ${still_missing[*]}"
        return 1
    fi

    return 0
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_failed "This script must be run with root access"
    exit 1
fi

# Start installation
banner
print_msg "Checking dependencies..."
if ! check_dependencies; then
    print_failed "Dependency check failed. Aborting."
    exit 1
fi

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
# Create a quick snapshot of the current system state so we can inspect
# partitioning information if something goes wrong.
create_pre_install_snapshot

# Verify we have enough space on the target mount before continuing.
# TARGET_MOUNT defaults to /mnt/usb; set it earlier if you use a different path.
TARGET_MOUNT="/mnt/usb"
check_disk_space
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

# Update repository list and entire system (use wrapper)
print_msg "Updating package repositories and system packages..."
if ! package_update_all; then
    print_failed "Failed to update the live system"
    exit 1
fi
print_success "Live system successfully updated"

# Install tools and DKMS module for bcachefs
print_msg "Installing bcachefs-tools, dkms, and kernel headers..."
if ! package_install_and_check "bcachefs-tools dkms linux-headers"; then
    print_failed "Failed to install required packages"
    exit 1
fi

# Check if bcachefs module already exists
if ! modinfo bcachefs &>/dev/null; then
    print_msg "bcachefs module not available in kernel. Attempting DKMS build..."
    
    # Install bcachefs module using dkms. Prefer official repo, fallback to AUR.
    if pacman -Si bcachefs-dkms &>/dev/null; then
        if ! package_install_and_check "bcachefs-dkms"; then
            print_failed "Failed to install bcachefs-dkms package from official repos"
            exit 1
        fi
    else
        print_warn "bcachefs-dkms not in official repos, attempting AUR..."
        if ! package_install_and_check "aur/bcachefs-dkms"; then
            print_failed "Cannot install bcachefs support from AUR or official repos"
            exit 1
        fi
    fi

    print_success "bcachefs-dkms package installed"

    # Run dkms manually to ensure module installation
    dkms autoinstall || {
        print_failed "DKMS module installation failed"
        exit 1
    }

    # Load the new module
    if ! modprobe bcachefs &>/dev/null; then
        print_failed "Failed to load bcachefs module even after DKMS installation"
        print_warn "You might need to use a different filesystem like F2FS or ext4"
        exit 1
    fi
    print_success "bcachefs module successfully loaded"
else
    print_success "bcachefs module is already available in the kernel"
fi


# Detect and format/mount partitions (supports sdX and nvmeX)
print_msg "Detecting partition paths..."
PART_ESP=$(get_part_path "$USB_DRIVE" 2)
PART_MAIN=$(get_part_path "$USB_DRIVE" 3)

if [[ -z "$PART_ESP" || -z "$PART_MAIN" ]]; then
    print_failed "Failed to detect partition paths. Aborting."
    exit 1
fi
print_success "ESP Partition: $PART_ESP"
print_success "Main Partition: $PART_MAIN"

# Format partitions
print_msg "Formatting partitions..."
mkfs.fat -F32 -n ARCH_ESP "$PART_ESP" && print_success "ESP format successful" || print_failed "Error formatting ESP"

print_msg "Formatting main partition with bcachefs..."
bcachefs format --label ARCH_PERSIST \
    --compression=zstd \
    --foreground_target=ssd \
    --background_target=ssd \
    --replicas=1 \
    --data_checksum=xxhash \
    --metadata_checksum=xxhash \
    --encrypted=none \
    "$PART_MAIN" && print_success "Main partition format successful" || print_failed "Error formatting main partition"

# Mount partitions
print_msg "Mounting partitions..."
mkdir -p /mnt/usb
# Use device nodes (safer than label lookup)
mount "$PART_ESP" /mnt/usb || {
    # نیاز به retry mechanism
    print_msg "Retrying mount in 3 seconds..."
    sleep 3
    mount "$PART_ESP" /mnt/usb || {
        print_failed "Failed to mount ESP partition after retry"
        exit 1
    }
}

mkdir -p /mnt/usb/persistent
mount "$PART_MAIN" /mnt/usb/persistent || {
    print_failed "Failed to mount main partition"
    exit 1
}

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
# Use package_install_pacstrap wrapper (adds retries and verification)
package_install_pacstrap "$PACKAGES" "/mnt/usb/persistent/arch_root" || {
    print_failed "Failed to install selected packages via package_install_pacstrap"
    exit 1
}

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
        package_install_pacstrap "linux-$(echo $LIVE_KERNEL_VERSION | cut -d'.' -f1-2)" "/mnt/usb/persistent/arch_root" || {
            print_warn "Failed to install live kernel via package_install_pacstrap"
        }
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

# Collect non-interactive inputs for the chrooted setup script. These values
# will be exported into /setup_env.sh inside the chroot so that the chrooted
# /setup.sh can run without interactive prompts.
print_msg "Now collecting configuration for the chrooted setup (hostname and passwords)."

# Hostname
print_msg "Enter system hostname for the installed system (default: arch-usb):"
read -r CHROOT_HOSTNAME
CHROOT_HOSTNAME="${CHROOT_HOSTNAME:-arch-usb}"

# Root password (hidden, with confirmation)
while true; do
    print_msg "Enter root password for installed system (input hidden):"
    read -r -s CHROOT_ROOT_PW
    echo
    print_msg "Confirm root password:"
    read -r -s CHROOT_ROOT_PW_CONFIRM
    echo
    if [[ "${CHROOT_ROOT_PW}" == "${CHROOT_ROOT_PW_CONFIRM}" && -n "${CHROOT_ROOT_PW}" ]]; then
        break
    fi
    print_failed "Root passwords do not match or empty. Please try again."
done

# Username
print_msg "Enter username for regular user inside installed system (default: user):"
read -r CHROOT_USER
CHROOT_USER="${CHROOT_USER:-user}"
while [[ ! "${CHROOT_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; do
    print_failed "Invalid username. Use only lowercase letters, numbers, - and _. Try again:"
    read -r CHROOT_USER
    CHROOT_USER="${CHROOT_USER:-user}"
done

# User password (hidden, with confirmation)
while true; do
    print_msg "Enter password for ${CHROOT_USER} (input hidden):"
    read -r -s CHROOT_USER_PW
    echo
    print_msg "Confirm password for ${CHROOT_USER}:"
    read -r -s CHROOT_USER_PW_CONFIRM
    echo
    if [[ "${CHROOT_USER_PW}" == "${CHROOT_USER_PW_CONFIRM}" && -n "${CHROOT_USER_PW}" ]]; then
        break
    fi
    print_failed "User passwords do not match or empty. Please try again."
done

# Timezone
print_msg "Enter timezone for the installed system (e.g., 'Asia/Tehran') (default: Asia/Tehran):"
read -r CHROOT_TZ
CHROOT_TZ="${CHROOT_TZ:-Asia/Tehran}"

# Escape single quotes in values so they can be safely embedded in single-quoted
# here-doc content inside the chroot file.
CH_HOST_ESC=$(printf '%s' "${CHROOT_HOSTNAME}" | sed "s/'/'\"'\"'/g")
CH_ROOT_ESC=$(printf '%s' "${CHROOT_ROOT_PW}" | sed "s/'/'\"'\"'/g")
CH_USER_ESC=$(printf '%s' "${CHROOT_USER}" | sed "s/'/'\"'\"'/g")
CH_USER_PW_ESC=$(printf '%s' "${CHROOT_USER_PW}" | sed "s/'/'\"'\"'/g")
CH_TZ_ESC=$(printf '%s' "${CHROOT_TZ}" | sed "s/'/'\"'\"'/g")

# Write environment file that will be sourced inside chroot
cat > /mnt/usb/persistent/arch_root/setup_env.sh <<EOF
#!/bin/bash
export HOSTNAME='${CH_HOST_ESC}'
export ROOT_PASSWORD='${CH_ROOT_ESC}'
export USERNAME='${CH_USER_ESC}'
export USER_PASSWORD='${CH_USER_PW_ESC}'
export TIMEZONE='${CH_TZ_ESC}'
EOF
chmod 600 /mnt/usb/persistent/arch_root/setup_env.sh


cat > /mnt/usb/persistent/arch_root/setup.sh <<'EOF'
#!/bin/bash
# Timezone: prefer injected value, otherwise prompt (fallback default Asia/Tehran)
if [ -f /setup_env.sh ]; then
    . /setup_env.sh || true
fi
if [ -n "${TIMEZONE:-}" ]; then
    TZVAL="${TIMEZONE}"
else
    print_msg "Enter system timezone (e.g., Region/City) (default: Asia/Tehran):"
    read -r TZVAL
    TZVAL="${TZVAL:-Asia/Tehran}"
fi
ln -sf "/usr/share/zoneinfo/$TZVAL" /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
# Provide minimal print_* functions in chroot (the full logging helpers are defined
# in the outer script and are not available inside the chroot). These simple
# fallbacks avoid "command not found" errors and print plain messages.
print_msg() { echo "$*"; }
print_warn() { echo "$*"; }
print_failed() { echo "$*"; }
print_success() { echo "$*"; }
# If the installer injected an environment file, source it to obtain non-interactive
# inputs (HOSTNAME, ROOT_PASSWORD, USERNAME, USER_PASSWORD).
if [ -f /setup_env.sh ]; then
    . /setup_env.sh
fi
# Non-interactive path: if the outer installer injected HOSTNAME, ROOT_PASSWORD,
# USERNAME and USER_PASSWORD into /setup_env.sh we prefer that and do not attempt
# to read from a tty (arch-chroot call is non-interactive). Otherwise fall back
# to the original interactive prompts.
if [ -n "\${HOSTNAME:-}" ] && [ -n "\${ROOT_PASSWORD:-}" ] && [ -n "\${USERNAME:-}" ] && [ -n "\${USER_PASSWORD:-}" ]; then
    HOSTNAME="\${HOSTNAME:-arch-usb}"
    echo "\$HOSTNAME" > /etc/hostname

    if [[ -n "\${ROOT_PASSWORD:-}" ]]; then
        echo "root:\${ROOT_PASSWORD}" | chpasswd
    fi

    USERNAME="\${USERNAME:-user}"
    if ! id "\$USERNAME" &>/dev/null; then
        useradd -m -G wheel -s /bin/bash "\$USERNAME"
    fi

    if [[ -n "\${USER_PASSWORD:-}" ]]; then
        echo "\${USERNAME}:\${USER_PASSWORD}" | chpasswd
    fi

    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

    systemctl enable NetworkManager systemd-oomd fstrim.timer

    echo "User accounts configured successfully:
- Hostname: \${HOSTNAME}
- Root account configured
- Regular user '\${USERNAME}' created with sudo access"
else
    # --- BEGIN original interactive prompts (kept for fallback) ---
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
    # --- END original interactive prompts ---
fi

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
                # Probe kernel support for erofs before attempting to modprobe.
                if ! modprobe -n -q erofs; then
                    echo "EROFS filesystem module not supported by kernel. Falling back to squashfs."
                    # Fall back to squashfs handling
                    if ! modprobe squashfs; then
                        echo "Failed to load squashfs module while falling back!"
                        umount /os_root
                        return 1
                    fi
                    if ! mount -t squashfs -o ro /os_root/arch/root.squashfs /squashfs; then
                        echo "Failed to mount root.squashfs as squashfs while falling back!"
                        umount /os_root
                        return 1
                    fi
                else
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
sed -Ei 's/^MODULES=(.*)/MODULES=(overlay squashfs erofs bcachefs \1)/' /etc/mkinitcpio.conf
sed -Ei 's/^HOOKS=(.filesystems.)/HOOKS=\1 overlay/' /etc/mkinitcpio.conf

# Check and enable LZ4HC support in erofs
if ! grep -q "CONFIG_EROFS_FS_LZ4HC=y" /boot/config-$(uname -r); then
    echo "Warning: This kernel might not support LZ4HC compression in erofs."
    echo "Consider rebuilding kernel with CONFIG_EROFS_FS_LZ4HC=y"
fi


mkinitcpio -P
EOF

chmod +x /mnt/usb/persistent/arch_root/setup.sh
arch-chroot /mnt/usb/persistent/arch_root /setup.sh

# =======================================================
#  (Safety and Recovery)
# =======================================================
print_msg "Injecting Advanced Safety scripts (003)..."

# Execute commands in the chroot environment
arch-chroot /mnt/usb/persistent/arch_root /bin/bash <<'CHROOT_003'

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
if ! package_install_and_check "busybox"; then
    print_warn "Failed to install busybox via package_install_and_check; attempting direct pacman as fallback"
    pacman -S --noconfirm busybox || print_failed "Failed to install busybox"
fi

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

arch-chroot /mnt/usb/persistent/arch_root /bin/bash <<'CHROOT_004'

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
    local rollback_success=true
    local OLD_SQUASHFS="/persistent/arch/root.squashfs"
    local OLD_SQUASHFS_BACKUP="${OLD_SQUASHFS}.old"

    # --- اصلاحیه ۱: بازگردانی root.squashfs ---
    log "Rolling back root filesystem..."
    if [ -f "$OLD_SQUASHFS_BACKUP" ]; then
        # حذف فایل squashfs جدید/خراب
        rm -f "$OLD_SQUASHFS"
        # بازگردانی فایل قدیمی
        mv "$OLD_SQUASHFS_BACKUP" "$OLD_SQUASHFS"
        log "Successfully rolled back $OLD_SQUASHFS"
    else
        log "ERROR: Cannot rollback rootfs. Backup $OLD_SQUASHFS_BACKUP not found!"
        rollback_success=false
    fi
    # --- پایان اصلاحیه ۱ ---

    # Restore previous files from backup (Kernel)
    log "Rolling back kernel files..."
    if [ -f "${ESP_MOUNT}/arch/vmlinuz-linux.old" ] && [ -f "${ESP_MOUNT}/arch/initramfs-linux.img.old" ]; then
        # حذف نسخه‌های مشکل‌دار از ESP
        rm -f "${ESP_MOUNT}/arch/vmlinuz-linux"
        rm -f "${ESP_MOUNT}/arch/initramfs-linux.img"
        
        # بازگرداندن به ESP
        mv "${ESP_MOUNT}/arch/vmlinuz-linux.old" "${ESP_MOUNT}/arch/vmlinuz-linux"
        mv "${ESP_MOUNT}/arch/initramfs-linux.img.old" "${ESP_MOUNT}/arch/initramfs-linux.img"
        
        # کپی به پارتیشن پایدار (جایی که GRUB بوت می‌شود)
        cp "${ESP_MOUNT}/arch/vmlinuz-linux" "/persistent/arch/"
        cp "${ESP_MOUNT}/arch/initramfs-linux.img" "/persistent/arch/"
        
        log "Successfully rolled back kernel files"
    else
        log "ERROR: Backup kernel files not found in ESP. Kernel rollback failed."
        rollback_success=false
    fi
    
    # حذف فایل‌های staging
    rm -rf "$STAGING_ROOT"
    
    if [ "$rollback_success" = true ]; then
        echo "rolledback" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
        log "Transaction $TRANSACTION_ID rolled back successfully"
    else
        echo "rollback_failed" > "$TRANSACTION_DIR/$TRANSACTION_ID/status"
        log "CRITICAL: Transaction $TRANSACTION_ID rollback FAILED. System may be unstable."
    fi
    
    # sync اجباری بعد از rollback
    sync
    /usr/local/bin/enforced-sync
}

# تابع به‌روزرسانی پکیج‌ها در محیط chroot
update_packages() {
    local CHROOT_DIR="$1"
    local LOG_FILE="$2"

    log "Updating packages in target root: $CHROOT_DIR"

    # Use pacman with --root to operate directly on the target root.
    # This avoids requiring a full interactive chroot environment for pacman.
    if ! pacman --root "$CHROOT_DIR" -Syu --noconfirm >> "$LOG_FILE" 2>&1; then
        error_exit "pacman update failed for root: $CHROOT_DIR"
    fi

    # Some post-install hooks (like mkinitcpio) require kernel modules and
    # virtual filesystems. We'll bind-mount minimal pseudo-filesystems only for
    # the duration of running mkinitcpio inside the target root.
    local MOUNTS_MADE=()
    for m in dev proc sys run; do
        if ! mountpoint -q "$CHROOT_DIR/$m"; then
            mkdir -p "$CHROOT_DIR/$m"
            mount --bind "/$m" "$CHROOT_DIR/$m" || {
                log "Warning: failed to bind mount /$m into $CHROOT_DIR (continuing)"
                continue
            }
            MOUNTS_MADE+=("$CHROOT_DIR/$m")
        fi
    done

    # Run mkinitcpio inside the target root to regenerate initramfs images.
    # Use arch-chroot for this small operation because mkinitcpio expects a
    # proper /proc and /dev; we've bind-mounted them above.
    if ! arch-chroot "$CHROOT_DIR" /usr/bin/mkinitcpio -P >> "$LOG_FILE" 2>&1; then
        # Attempt best-effort cleanup mounts before failing
        for mp in "${MOUNTS_MADE[@]}"; do
            umount -l "$mp" 2>/dev/null || true
        done
        error_exit "mkinitcpio failed in target root: $CHROOT_DIR"
    fi

    # Cleanup bind mounts we created
    for mp in "${MOUNTS_MADE[@]}"; do
        umount -l "$mp" 2>/dev/null || true
    done

    log "Package update and initramfs generation completed for $CHROOT_DIR"
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

    # Clean package caches inside the staging root to reduce final squashfs size
    log "Cleaning package caches inside staging root: $STAGING_ROOT"
    pacman --root "$STAGING_ROOT" -Scc --noconfirm >/dev/null 2>&1 || true
    rm -rf "$STAGING_ROOT/var/cache/pacman/pkg/*" 2>/dev/null || true
    log "Staging cache cleaned before creating squashfs"
    
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
# Check for the existence of essential files before copying; if not, rollback is performed
    if [[ ! -f "${STAGING_ROOT}/boot/vmlinuz-linux" ]]; then
        error_exit "Kernel file not found in staging area: ${STAGING_ROOT}/boot/vmlinuz-linux"
    fi
    if [[ ! -f "${STAGING_ROOT}/boot/initramfs-linux.img" ]]; then
        error_exit "Initramfs file not found in staging area: ${STAGING_ROOT}/boot/initramfs-linux.img"
    fi

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

arch-chroot /mnt/usb/persistent/arch_root /bin/bash <<'CHROOT_005'

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
                # Do NOT apply aggressive clock/power settings by default.
                # These can be unstable on some hardware and should be opt-in.
                if [[ -f "/etc/hardware-profiles/enable-nvidia-aggressive" ]]; then
                    nvidia-smi -pm 1
                    nvidia-smi --auto-boost-default=0
                    nvidia-smi -ac 2100,800
                else
                    echo "NVIDIA aggressive settings are disabled by default. To enable, create /etc/hardware-profiles/enable-nvidia-aggressive"
                fi
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
    mkfs.erofs -zlz4hc,12 --uid-offset=0 --gid-offset=0 --mount-point=/ --exclude-path="/tmp/*" /mnt/usb/persistent/arch/root.squashfs /mnt/usb/persistent/arch_root
else
    mksquashfs /mnt/usb/persistent/arch_root /mnt/usb/persistent/arch/root.squashfs -comp zstd -Xcompression-level 15 -noappend -processors "$(nproc)"
fi

cp /mnt/usb/persistent/arch_root/boot/vmlinuz-linux /mnt/usb/persistent/arch/
cp /mnt/usb/persistent/arch_root/boot/initramfs-linux.img /mnt/usb/persistent/arch/

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