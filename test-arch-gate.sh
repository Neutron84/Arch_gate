#!/bin/bash
echo "Testing Arch Gate setup (fixed)..."
echo "========================================="

# Test basic sourcing
echo "Testing basic sourcing..."
cd "$(dirname "$0")" || exit 1

# Test lib directory
echo "Testing lib directory..."
if [ -d "lib" ]; then
    echo "✓ lib directory exists"
    source lib/colors.sh && echo "✓ Colors loaded"
    source lib/logging.sh && echo "✓ Logging loaded"
    source lib/utils.sh && echo "✓ Utils loaded"
else
    echo "✗ lib directory not found"
    exit 1
fi

# Test stages directory
echo "Testing stages directory..."
if [ -d "stages" ]; then
    echo "✓ stages directory exists"
    [ -f "stages/stage1.sh" ] && echo "✓ stage1.sh exists"
    [ -f "stages/stage2.sh" ] && echo "✓ stage2.sh exists"
else
    echo "✗ stages directory not found"
    exit 1
fi

# Test systems directory
echo "Testing systems directory..."
if [ -d "systems/usb_memory" ]; then
    echo "✓ systems/usb_memory directory exists"
    [ -f "systems/usb_memory/check-usb-health.sh" ] && echo "✓ check-usb-health.sh exists"
else
    echo "✗ systems/usb_memory directory not found"
    exit 1
fi

# Test function availability
echo "Testing function availability..."
if declare -f confirmation_y_or_n > /dev/null; then
    echo "✓ confirmation_y_or_n function is available"
else
    echo "✗ confirmation_y_or_n function is NOT available"
fi

if declare -f cleanup_on_exit > /dev/null; then
    echo "✓ cleanup_on_exit function is available"
else
    echo "✗ cleanup_on_exit function is NOT available"
fi

if declare -f select_an_option > /dev/null; then
    echo "✓ select_an_option function is available"
else
    echo "✗ select_an_option function is NOT available"
fi

if declare -f check_dependencies > /dev/null; then
    echo "✓ check_dependencies function is available"
else
    echo "✗ check_dependencies function is NOT available"
fi

echo
echo "========================================="
echo "Test complete!"
echo
echo "To test stage1.sh, run:"
echo "  cd stages && sudo ./stage1.sh"
echo
echo "Make sure to run as root (sudo) for proper testing."
trap - EXIT

echo "========================================="
echo "Test complete!"
# ...