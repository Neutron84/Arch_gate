#!/bin/bash
# =============================================================================
# COLOR DEFINITION SYSTEM
# =============================================================================

if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
        # Terminal supports colors - define all colors using printf
        # Basic colors (normal intensity)
        R="$(printf '\033[0m\033[31m')"          # RST + red
        G="$(printf '\033[0m\033[32m')"          # RST + green
        B="$(printf '\033[0m\033[34m')"          # RST + blue
        Y="$(printf '\033[0m\033[33m')"          # RST + yellow
        P="$(printf '\033[0m\033[35m')"          # RST + pink/magenta
        C="$(printf '\033[0m\033[36m')"          # RST + cyan
        W="$(printf '\033[0m\033[37m')"          # RST + white
        BLACK="$(printf '\033[0m\033[30m')"      # RST + black
        
        # Bold colors (light/bright intensity)
        RB="$(printf '\033[0m\033[1m\033[31m')"  # RST + bold + red
        GB="$(printf '\033[0m\033[1m\033[32m')"  # RST + bold + green
        BB="$(printf '\033[0m\033[1m\033[34m')"  # RST + bold + blue
        YB="$(printf '\033[0m\033[1m\033[33m')"  # RST + bold + yellow
        PB="$(printf '\033[0m\033[1m\033[35m')"  # RST + bold + pink/magenta
        CB="$(printf '\033[0m\033[1m\033[36m')"  # RST + bold + cyan
        WB="$(printf '\033[0m\033[1m\033[37m')"  # RST + bold + white
        BLACKB="$(printf '\033[0m\033[1m\033[30m')" # RST + bold + black
        
        # Special modifiers
        BOLD="$(printf '\033[1m')"               # bold only
        NC="$(printf '\033[0m')"                 # reset all attributes
        GRAY="$(printf '\033[0m\033[90m')"       # gray color
        UNDERLINE="$(printf '\033[4m')"          # underline
    else
        # Terminal doesn't support colors
        R="" G="" B="" Y="" P="" C="" W="" BLACK=""
        RB="" GB="" BB="" YB="" PB="" CB="" WB="" BLACKB=""
        BOLD="" NC="" GRAY="" UNDERLINE=""
    fi
else
    # Output to file or pipe, or tput not available
    R="" G="" B="" Y="" P="" C="" W="" BLACK=""
    RB="" GB="" BB="" YB="" PB="" CB="" WB="" BLACKB=""
    BOLD="" NC="" GRAY="" UNDERLINE=""
fi


