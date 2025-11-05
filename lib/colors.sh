#!/bin/bash
# =============================================================================
# COLOR DEFINITION SYSTEM
# =============================================================================

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

# =============================================================================
: <<'IGNORE'
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


IGNORE