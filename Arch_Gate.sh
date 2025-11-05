#!/bin/bash
# =============================================================================
# Arch Gate - Universal Arch Linux Installation System
# =============================================================================
# Main script that orchestrates the installation process
#
# This script supports:
# - Real systems (SSD, HDD)
# - Portable systems (USB SSD, USB HDD, USB Memory, SD Cards)
# - Hybrid boot for all portable devices
# - All partition schemes (GPT, MBR, Hybrid)
# - Two-stage installation to handle limited live environment space
#
# Author: @Neutron84
# License: MIT
# Repository: https://github.com/Neutron84/arch_gate

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHGATE_DIR="$SCRIPT_DIR"

# Check if running from archgate directory
if [[ ! -d "$ARCHGATE_DIR/archgate" ]]; then
    print_failed "Error: archgate directory not found. Please run this script from the project root."
    exit 1
fi

# Source all required modules
source "$ARCHGATE_DIR/archgate/lib/colors.sh"
source "$ARCHGATE_DIR/archgate/lib/logging.sh"
source "$ARCHGATE_DIR/archgate/lib/utils.sh"
source "$ARCHGATE_DIR/archgate/lib/packages.sh"
source "$ARCHGATE_DIR/archgate/lib/partition.sh"
source "$ARCHGATE_DIR/archgate/lib/config.sh"

# Initialize
init_logger
banner

# Check if running as root 
if [[ $EUID -ne 0 ]]; then
    print_failed "This script must be run with root access"
    exit 1
fi

# Check if we're in a live environment
if [[ ! -f /.arch_chroot ]] && ! mountpoint -q /mnt 2>/dev/null; then
    print_warn "This appears to be a live Arch environment"
fi

# Check for existing configuration
CONFIG_FILE="/etc/archgate/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    load_config
    
    # Check stage
    STAGE=$(get_config "stage")
    
    if [[ "$STAGE" == "2" ]]; then
        print_msg "Stage 2 configuration found. Continuing installation..."
        # Run Stage 2
        if [[ -f "$ARCHGATE_DIR/archgate/stages/stage2.sh" ]]; then
            bash "$ARCHGATE_DIR/archgate/stages/stage2.sh"
        else
            print_failed "Stage 2 script not found"
            exit 1
        fi
        exit 0
    elif [[ "$STAGE" == "completed" ]]; then
        print_msg "Installation already completed"
        print_msg "Configuration file: $CONFIG_FILE"
        exit 0
    fi
fi

# Start Stage 1
print_msg "Starting Arch Gate installation..."
print_msg "This will run Stage 1: Interactive configuration and basic installation"

if [[ -f "$ARCHGATE_DIR/archgate/stages/stage1.sh" ]]; then
    bash "$ARCHGATE_DIR/archgate/stages/stage1.sh"
else
    print_failed "Stage 1 script not found"
        exit 1
    fi

exit 0
