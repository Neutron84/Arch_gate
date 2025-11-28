#!/bin/bash
# =============================================================================
# MODULE LOADER SYSTEM
# =============================================================================
# Provides safe and reliable module loading with dependency tracking

# Include guard
if [[ -n "${_ARCHGATE_LOADER_SH_LOADED:-}" ]]; then
  return 0
fi
_ARCHGATE_LOADER_SH_LOADED=true

# Track loaded modules to prevent duplicate loading
declare -gA MODULE_LOADED=()

# Get absolute path to lib directory
get_lib_dir() {
    local script_path="${BASH_SOURCE[0]}"
    local script_dir
    
    # If script_path is empty, try alternative methods
    if [[ -z "$script_path" ]]; then
        script_path="${0}"
    fi
    
    # Get absolute directory of this script
    script_dir="$(cd "$(dirname "$script_path")" && pwd)"
    
    # Return lib directory
    echo "$script_dir"
}

# Get project root directory
get_project_root() {
    local lib_dir
    lib_dir=$(get_lib_dir)
    echo "$(cd "$lib_dir/.." && pwd)"
}

# Load a module safely
load_module() {
    local module_name="$1"
    local lib_dir="${LIB_DIR:-$(get_lib_dir)}"
    local module_file="$lib_dir/$module_name"
    
    # Check if already loaded
    if [[ -n "${MODULE_LOADED[$module_name]}" ]]; then
        log_debug "Module already loaded: $module_name" 2>/dev/null || true
        return 0
    fi
    
    # Check if module file exists
    if [[ ! -f "$module_file" ]]; then
        echo "ERROR: Module not found: $module_file" >&2
        return 1
    fi
    
    # Load the module
    if source "$module_file"; then
        MODULE_LOADED[$module_name]=1
        log_debug "Module loaded: $module_name" 2>/dev/null || true
        return 0
    else
        echo "ERROR: Failed to load module: $module_file" >&2
        return 1
    fi
}

# Load all core modules
load_all_core_modules() {
    local lib_dir="${LIB_DIR:-$(get_lib_dir)}"
    
    # Set LIB_DIR for modules that need it
    export LIB_DIR="$lib_dir"
    
    # Core modules (must be loaded in order)
    local core_modules=(
        "colors.sh"
        "logging.sh"
        "utils.sh"
        "recovery.sh"
        "pacman-utils.sh"
        "config.sh"
        "packages.sh"
        "btrfs.sh"
        "partition.sh"
        "overlay.sh"
        "snapshot.sh"
        "atomic-update.sh"
        "safety.sh"
        "memory.sh"
        "optimizations.sh"
        "grub-advanced.sh"
    )
    
    for module in "${core_modules[@]}"; do
        if ! load_module "$module"; then
            echo "ERROR: Failed to load core module: $module" >&2
            return 1
        fi
    done
    
    return 0
}

# Load modules with dependency checking
load_module_with_deps() {
    local module_name="$1"
    local dependencies=("${@:2}")
    
    # Load dependencies first
    for dep in "${dependencies[@]}"; do
        if ! load_module "$dep"; then
            echo "ERROR: Failed to load dependency: $dep for module: $module_name" >&2
            return 1
        fi
    done
    
    # Load the requested module
    load_module "$module_name"
}

# Check if module is loaded
is_module_loaded() {
    local module_name="$1"
    [[ -n "${MODULE_LOADED[$module_name]}" ]]
}

# Get list of loaded modules
get_loaded_modules() {
    echo "${!MODULE_LOADED[@]}"
}

