#!/bin/bash
# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

# Configuration file path
CONFIG_FILE="/etc/archgate/config.conf"
CONFIG_DIR="/etc/archgate"

# Configuration validators registry
declare -gA CONFIG_VALIDATORS=()

# Register a validator function for a config key
register_config_validator() {
    local key="$1"
    local validator_func="$2"
    CONFIG_VALIDATORS["$key"]="$validator_func"
    log_debug "Registered validator for config key: $key"
}

# Validate a config value using registered validator
validate_config_value() {
    local key="$1"
    local value="$2"
    
    if [[ -n "${CONFIG_VALIDATORS[$key]}" ]]; then
        if ${CONFIG_VALIDATORS[$key]} "$value"; then
            return 0
        else
            log_error "Validation failed for $key=$value" 2>/dev/null || echo "ERROR: Validation failed for $key" >&2
            return 1
        fi
    else
        # No validator registered, accept value
        return 0
    fi
}

# Initialize configuration
init_config() {
    if ! mkdir -p "$CONFIG_DIR" 2>/dev/null; then
        print_failed "Failed to create config directory: $CONFIG_DIR"
        return 1
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        if ! touch "$CONFIG_FILE" 2>/dev/null; then
            print_failed "Failed to create config file: $CONFIG_FILE"
            return 1
        fi
        chmod 600 "$CONFIG_FILE" 2>/dev/null || true
        log_debug "Configuration file created: $CONFIG_FILE" || true
    fi
    
    # Register default validators if validation functions are available
    if declare -F validate_block_device &>/dev/null; then
        register_config_validator "device" "validate_block_device" || true
    fi
    if declare -F validate_hostname &>/dev/null; then
        register_config_validator "hostname" "validate_hostname" || true
    fi
    if declare -F validate_username &>/dev/null; then
        register_config_validator "username" "validate_username" || true
    fi
    
    return 0
}

# Save configuration to file
save_config() {
    local temp_file
    temp_file="${CONFIG_FILE}.tmp.$$"
    
    if ! init_config; then
        print_failed "Failed to initialize configuration"
        return 1
    fi
    
    # Backup existing config (ignore errors)
    if [[ -f "$CONFIG_FILE" ]]; then
        check_and_backup "$CONFIG_FILE" 2>/dev/null || true
    fi
    
    print_msg "Saving configuration to $CONFIG_FILE..."
    
    # Write configuration to temp file first
    {
        echo "# Arch Gate Configuration"
        echo "# Generated on: $(date)"
        echo ""
        
        # Storage configuration
        [[ -n "${CONFIG[system_type]:-}" ]] && echo "SYSTEM_TYPE=${CONFIG[system_type]}"
        [[ -n "${CONFIG[device]:-}" ]] && echo "DEVICE=${CONFIG[device]}"
        [[ -n "${CONFIG[storage_type]:-}" ]] && echo "STORAGE_TYPE=${CONFIG[storage_type]}"
        [[ -n "${CONFIG[partition_scheme]:-}" ]] && echo "PARTITION_SCHEME=${CONFIG[partition_scheme]}"
        [[ -n "${CONFIG[filesystem_type]:-}" ]] && echo "FILESYSTEM_TYPE=${CONFIG[filesystem_type]}"
        
        # System configuration
        [[ -n "${CONFIG[hostname]:-}" ]] && echo "HOSTNAME=${CONFIG[hostname]}"
        [[ -n "${CONFIG[root_password]:-}" ]] && echo "ROOT_PASSWORD=${CONFIG[root_password]}"
        [[ -n "${CONFIG[root_use_password]:-}" ]] && echo "ROOT_USE_PASSWORD=${CONFIG[root_use_password]}"
        [[ -n "${CONFIG[username]:-}" ]] && echo "USERNAME=${CONFIG[username]}"
        [[ -n "${CONFIG[user_password]:-}" ]] && echo "USER_PASSWORD=${CONFIG[user_password]}"
        [[ -n "${CONFIG[user_use_password]:-}" ]] && echo "USER_USE_PASSWORD=${CONFIG[user_use_password]}"
        [[ -n "${CONFIG[create_user]:-}" ]] && echo "CREATE_USER=${CONFIG[create_user]}"
        [[ -n "${CONFIG[timezone]:-}" ]] && echo "TIMEZONE=${CONFIG[timezone]}"
        [[ -n "${CONFIG[locale]:-}" ]] && echo "LOCALE=${CONFIG[locale]}"
        
        # Package selection
        [[ -n "${CONFIG[install_desktop]:-}" ]] && echo "INSTALL_DESKTOP=${CONFIG[install_desktop]}"
        [[ -n "${CONFIG[install_dev]:-}" ]] && echo "INSTALL_DEV=${CONFIG[install_dev]}"
        [[ -n "${CONFIG[install_office]:-}" ]] && echo "INSTALL_OFFICE=${CONFIG[install_office]}"
        [[ -n "${CONFIG[install_graphics]:-}" ]] && echo "INSTALL_GRAPHICS=${CONFIG[install_graphics]}"
        [[ -n "${CONFIG[install_nvidia]:-}" ]] && echo "INSTALL_NVIDIA=${CONFIG[install_nvidia]}"
        [[ -n "${CONFIG[install_amd]:-}" ]] && echo "INSTALL_AMD=${CONFIG[install_amd]}"
        [[ -n "${CONFIG[install_intel]:-}" ]] && echo "INSTALL_INTEL=${CONFIG[install_intel]}"
        
        # Installation stage
        [[ -n "${CONFIG[stage]:-}" ]] && echo "STAGE=${CONFIG[stage]}"
        [[ -n "${CONFIG[mount_point]:-}" ]] && echo "MOUNT_POINT=${CONFIG[mount_point]}"
        
        } > "$temp_file" 2>/dev/null || {
        print_failed "Failed to write temporary configuration file"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    }
    
    # Move temp file to final location atomically
    if ! mv "$temp_file" "$CONFIG_FILE" 2>/dev/null; then
        print_failed "Failed to move configuration file to final location"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi
    
    # Set proper permissions
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    
    print_success "Configuration saved to $CONFIG_FILE"
    log_debug "Configuration saved" 2>/dev/null || true
    return 0
}

# Load configuration from file
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_warn "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    print_msg "Loading configuration from $CONFIG_FILE..."
    
    # Source the config file
    source "$CONFIG_FILE"
    
    # Populate CONFIG array
    declare -gA CONFIG
    
    [[ -n "${SYSTEM_TYPE:-}" ]] && CONFIG[system_type]="$SYSTEM_TYPE"
    [[ -n "${DEVICE:-}" ]] && CONFIG[device]="$DEVICE"
    [[ -n "${STORAGE_TYPE:-}" ]] && CONFIG[storage_type]="$STORAGE_TYPE"
    [[ -n "${PARTITION_SCHEME:-}" ]] && CONFIG[partition_scheme]="$PARTITION_SCHEME"
    [[ -n "${FILESYSTEM_TYPE:-}" ]] && CONFIG[filesystem_type]="$FILESYSTEM_TYPE"
    [[ -n "${HOSTNAME:-}" ]] && CONFIG[hostname]="$HOSTNAME"
    [[ -n "${ROOT_PASSWORD:-}" ]] && CONFIG[root_password]="$ROOT_PASSWORD"
    [[ -n "${USERNAME:-}" ]] && CONFIG[username]="$USERNAME"
    [[ -n "${USER_PASSWORD:-}" ]] && CONFIG[user_password]="$USER_PASSWORD"
    [[ -n "${TIMEZONE:-}" ]] && CONFIG[timezone]="$TIMEZONE"
    [[ -n "${LOCALE:-}" ]] && CONFIG[locale]="$LOCALE"
    [[ -n "${INSTALL_DESKTOP:-}" ]] && CONFIG[install_desktop]="${INSTALL_DESKTOP}"
    [[ -n "${INSTALL_DEV:-}" ]] && CONFIG[install_dev]="${INSTALL_DEV}"
    [[ -n "${INSTALL_OFFICE:-}" ]] && CONFIG[install_office]="${INSTALL_OFFICE}"
    [[ -n "${INSTALL_GRAPHICS:-}" ]] && CONFIG[install_graphics]="${INSTALL_GRAPHICS}"
    [[ -n "${INSTALL_NVIDIA:-}" ]] && CONFIG[install_nvidia]="${INSTALL_NVIDIA}"
    [[ -n "${INSTALL_AMD:-}" ]] && CONFIG[install_amd]="${INSTALL_AMD}"
    [[ -n "${INSTALL_INTEL:-}" ]] && CONFIG[install_intel]="${INSTALL_INTEL}"
    [[ -n "${STAGE:-}" ]] && CONFIG[stage]="$STAGE"
    [[ -n "${MOUNT_POINT:-}" ]] && CONFIG[mount_point]="$MOUNT_POINT"
    
    print_success "Configuration loaded"
    log_debug "Configuration loaded from $CONFIG_FILE"
    return 0
}

# Get config value
get_config() {
    local key="$1"
    echo "${CONFIG[$key]:-}"
}

# Set config value with validation
set_config() {
    local key="$1"
    local value="$2"
    
    # Validate if validator exists
    if ! validate_config_value "$key" "$value"; then
        return 1
    fi
    
    CONFIG["$key"]="$value"
    log_debug "Config set: $key=$value"
    return 0
}

# Update config stage
update_stage() {
    local stage="$1"
    set_config "stage" "$stage"
    save_config
    log_debug "Stage updated to: $stage"
}

# Read configuration file and validate required variables
function read_conf() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_failed "Configuration file $CONFIG_FILE not found"
        exit 0
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    print_success "Configuration variables loaded"
    validate_required_vars
}

# Use atomic write pattern to prevent background execution issues
function print_to_config() {
    local var_name="$1"
    local var_value="${2:-${!var_name}}"
    local IFS=$' \t\n'
    local temp_file="${CONFIG_FILE}.tmp.$$"
    
    # Ensure config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        touch "$CONFIG_FILE" 2>/dev/null || {
            log_error "Cannot access $CONFIG_FILE"
            return 1
        }
    fi
    
    if grep -q "^${var_name}=" "$CONFIG_FILE" 2>/dev/null; then
        # Atomic write: write to temp file then move
        sed "s|^${var_name}=.*|${var_name}=${var_value}|" "$CONFIG_FILE" >"$temp_file" && mv "$temp_file" "$CONFIG_FILE"
    else
        echo "${var_name}=${var_value}" >>"$CONFIG_FILE"
    fi
    
    log_debug "$var_name = $var_value"
}

function validate_required_vars() {
    # Check if CONFIG array is declared
    if ! declare -p CONFIG &>/dev/null || [[ "$(declare -p CONFIG)" != declare\ -A* ]]; then
        print_failed "CONFIG array is not properly initialized"
        return 1
    fi
    
    print_msg "Validating required configuration values..."
    
    local missing_vars=()
    local warnings=()
    
    # Required core configuration variables
    local required_config_keys=(
        # Storage and partitioning
        "system_type"
        "device"
        "storage_type"
        "partition_scheme"
        "filesystem_type"
        "mount_point"
        # System configuration
        "hostname"
        "root_password"
        "username"
        "user_password"
        "timezone"
        "locale"
        # Installation stage
        "stage"
    )
    
    # Check required CONFIG keys
    for key in "${required_config_keys[@]}"; do
        if [[ -z "${CONFIG[$key]:-}" ]]; then
            missing_vars+=("CONFIG[$key]")
        fi
    done
    
    # Check required system variables
    local required_system_vars=(
        "CONFIG_FILE"
    )
    
    for var in "${required_system_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    # Optional configuration variables (warn if missing but don't fail)
    local optional_config_keys=(
        "install_desktop"
        "install_dev"
        "install_office"
        "install_graphics"
        "install_nvidia"
        "install_amd"
        "install_intel"
    )
    
    for key in "${optional_config_keys[@]}"; do
        if [[ -z "${CONFIG[$key]:-}" ]]; then
            warnings+=("CONFIG[$key] (optional, will default to 'n')")
        fi
    done
    
    # Display warnings for optional variables
    if ((${#warnings[@]} > 0)); then
        print_warn "The following optional configuration values are not set (will use defaults):"
        for var in "${warnings[@]}"; do
            echo "  - $var"
            log_debug "Optional missing: $var"
        done
    fi
    
    # Check for critical errors
    if ((${#missing_vars[@]} > 0)); then
        print_failed "The following required configuration values are not set:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
            log_error "Missing required variable: $var"
        done
        return 1
    fi
    
    # Additional validation: Check if device is a valid block device (if device is set)
    if [[ -n "${CONFIG[device]:-}" ]]; then
        if [[ ! -b "${CONFIG[device]}" ]]; then
            print_warn "Device ${CONFIG[device]} may not be a valid block device"
            log_warn "Device validation: ${CONFIG[device]} is not a block device"
        fi
    fi
    
    # Validate stage value
    if [[ -n "${CONFIG[stage]:-}" ]]; then
        case "${CONFIG[stage]}" in
            1|2|completed)
                log_debug "Stage validation: ${CONFIG[stage]} is valid"
            ;;
            *)
                print_warn "Stage value '${CONFIG[stage]}' is not a standard stage number"
                log_warn "Stage validation: ${CONFIG[stage]} is non-standard"
            ;;
        esac
    fi
    
    # Validate filesystem type
    if [[ -n "${CONFIG[filesystem_type]:-}" ]]; then
        case "${CONFIG[filesystem_type]}" in
            bcachefs|ext4|f2fs|btrfs|xfs)
                log_debug "Filesystem validation: ${CONFIG[filesystem_type]} is supported"
            ;;
            *)
                print_warn "Filesystem type '${CONFIG[filesystem_type]}' may not be supported"
                log_warn "Filesystem validation: ${CONFIG[filesystem_type]} is non-standard"
            ;;
        esac
    fi
    
    # Validate partition scheme
    if [[ -n "${CONFIG[partition_scheme]:-}" ]]; then
        case "${CONFIG[partition_scheme]}" in
            hybrid|gpt|mbr)
                log_debug "Partition scheme validation: ${CONFIG[partition_scheme]} is supported"
            ;;
            *)
                print_warn "Partition scheme '${CONFIG[partition_scheme]}' may not be supported"
                log_warn "Partition scheme validation: ${CONFIG[partition_scheme]} is non-standard"
            ;;
        esac
    fi
    
    print_success "All required configuration variables are set and validated"
    log_info "Configuration validation completed successfully"
    return 0
}

