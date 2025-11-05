#!/bin/bash
# =============================================================================
# ADVANCED LOGGING SYSTEM
# =============================================================================

# Source colors first
[[ -f "${0%/*}/colors.sh" ]] && source "${0%/*}/colors.sh"

# Logging configuration
LOG_DIR="/var/log/archgate"
LOG_FILE="${LOG_DIR}/archgate.log"
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
        printf '%s\n' "$line" >&"${_LOG_FD}" 2>/dev/null || true
    else
        printf '%s\n' "$line"
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
        logger -p "$pri" -t "archgate" -- "$msg" 2>/dev/null || true
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
        printf '%b%s%b\n' "${color_prefix}" "${msg}" "${reset}"
    else
        printf '%s\n' "$msg"
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
        sync
        sleep 0.1
        close_logger
        init_logger
    fi
}

enable_syslog()  { SYSLOG_ENABLED=1; print_msg "Syslog enabled"; }
disable_syslog() { SYSLOG_ENABLED=0; print_msg "Syslog disabled"; }

