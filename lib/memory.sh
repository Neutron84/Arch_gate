#!/bin/bash
# =============================================================================
# MEMORY OPTIMIZATION MODULE
# =============================================================================
# This module provides memory optimization with ZRAM and ZSWAP
# Features:
# - Auto-tuning ZRAM and ZSWAP based on RAM
# - Systemd zram-generator configuration
# - Sysctl memory optimizations
# - Modprobe ZSWAP configuration

# Source required modules (use BASH_SOURCE for reliable path when sourced)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
[[ -f "$_LIB_DIR/colors.sh" ]] && source "$_LIB_DIR/colors.sh"
[[ -f "$_LIB_DIR/logging.sh" ]] && source "$_LIB_DIR/logging.sh"
[[ -f "$_LIB_DIR/utils.sh" ]] && source "$_LIB_DIR/utils.sh"

# Setup memory optimization
setup_memory_optimization() {
    local chroot_dir="$1"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_memory_optimization: chroot_dir is required"
        return 1
    fi
    
    print_msg "Setting up memory optimization..."
    
    # Create configure-memory script
    cat > "$chroot_dir/usr/local/bin/configure-memory" <<'EOF'
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

# Configure zram-generator
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/zram.conf <<ZRAM
[zram0]
zram-size = ${final_zram}M
compression-algorithm = zstd
EOF-swapfile = false
    swap-priority = 100
    ZRAM
    
    # Set swappiness
    echo "vm.swappiness=$swappiness" > /etc/sysctl.d/99-memory.conf
    
    # Additional memory settings based on RAM
    if [ $total_mem_mb -le 2048 ]; then
        # Low RAM systems
    cat >> /etc/sysctl.d/99-memory.conf <<MEM
vm.vfs_cache_pressure=200
vm.page-cluster=0
vm.dirty_ratio=10
vm.dirty_background_ratio=5
MEM
        elif [ $total_mem_mb -le 4096 ]; then
        # Medium RAM systems
    cat >> /etc/sysctl.d/99-memory.conf <<MEM
vm.vfs_cache_pressure=150
vm.page-cluster=1
vm.dirty_ratio=15
vm.dirty_background_ratio=8
MEM
        elif [ $total_mem_mb -le 8192 ]; then
        # High RAM systems
    cat >> /etc/sysctl.d/99-memory.conf <<MEM
vm.vfs_cache_pressure=100
vm.page-cluster=2
vm.dirty_ratio=20
vm.dirty_background_ratio=10
MEM
    else
        # Very high RAM systems
    cat >> /etc/sysctl.d/99-memory.conf <<MEM
vm.min_free_kbytes=$((256 * 1024))
vm.zone_reclaim_mode=0
vm.overcommit_ratio=80
vm.vfs_cache_pressure=80
vm.page-cluster=3
vm.dirty_ratio=30
vm.dirty_background_ratio=15
MEM
    fi
    
    # Advanced zswap settings in modprobe
cat > /etc/modprobe.d/zswap.conf <<ZSWAP
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
ZSWAP
    
    # Apply settings
    sysctl -p /etc/sysctl.d/99-memory.conf
    EOF
    
    chmod +x "$chroot_dir/usr/local/bin/configure-memory"
    
    # Create configure-memory service
    cat > "$chroot_dir/etc/systemd/system/configure-memory.service" <<'EOF'
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
EOF
    
    # Configure journald to preserve space
    mkdir -p "$chroot_dir/etc/systemd/journald.conf.d"
    cat > "$chroot_dir/etc/systemd/journald.conf.d/volatile.conf" <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF
    
    print_success "Memory optimization configured"
    return 0
}

# Configure ZSWAP separately
setup_zswap() {
    local chroot_dir="$1"
    local enabled="${2:-true}"
    local compressor="${3:-zstd}"
    local max_pool="${4:-20}"
    
    if [[ -z "$chroot_dir" ]]; then
        print_failed "setup_zswap: chroot_dir is required"
        return 1
    fi
    
    print_msg "Configuring ZSWAP..."
    
    # Create configure-zswap script
    cat > "$chroot_dir/usr/local/bin/configure-zswap" <<EOF
#!/bin/bash

# Get total RAM in MB
total_mem_mb=\$(grep MemTotal /proc/meminfo | awk '{print int(\$2/1024)}')

# Set ZSWAP parameters based on RAM
if [ \$total_mem_mb -le 2048 ]; then
    zswap_enabled=0
    zswap_max_pool=10
    zswap_compressor="lz4"
elif [ \$total_mem_mb -le 4096 ]; then
    zswap_enabled=1
    zswap_max_pool=15
    zswap_compressor="zstd"
elif [ \$total_mem_mb -le 8192 ]; then
    zswap_enabled=1
    zswap_max_pool=20
    zswap_compressor="zstd"
else
    zswap_enabled=1
    zswap_max_pool=25
    zswap_compressor="zstd"
fi

# Override with provided parameters
zswap_enabled=${enabled}
zswap_compressor="${compressor}"
zswap_max_pool=${max_pool}

# Configure ZSWAP
cat > /etc/modprobe.d/zswap.conf <<ZSWAP
# Enable ZSWAP
options zswap enabled=\$zswap_enabled

# Compression algorithm
options zswap compressor=\$zswap_compressor

# Maximum memory percentage for ZSWAP
options zswap max_pool_percent=\$zswap_max_pool

# Memory management algorithm
options zswap zpool=z3fold

# Compression threshold (only pages larger than 50KB are compressed)
options zswap threshold=51200
ZSWAP

echo "ZSWAP configured: enabled=\$zswap_enabled, compressor=\$zswap_compressor, max_pool=\$zswap_max_pool%"
EOF
    
    chmod +x "$chroot_dir/usr/local/bin/configure-zswap"
    
    print_success "ZSWAP configuration script created"
    return 0
}

