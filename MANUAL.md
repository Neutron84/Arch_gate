# Arch Linux USB — User Manual (English)

This manual documents the tools, services and workflows included in the Arch Linux USB installer and runtime image. It is intended as a concise reference for operators installing and maintaining the USB-based Arch system provided by this project.

Table of contents
- Safety & Recovery
- Atomic Update System
- Advanced Optimizations
- Package Management & Cache Cleaning
- Kernel & Driver Notes

---

## Safety & Recovery

These tools provide data integrity, automatic recovery, and automatic remediation features to reduce the risk of data loss on removable media.

1) Forced sync utility

```bash
# Run an immediate enforced sync
enforced-sync

# Enable/disable periodic enforced sync
systemctl enable periodic-sync.timer
systemctl disable periodic-sync.timer
systemctl status periodic-sync.timer
```

2) I/O health monitoring

```bash
# Check the I/O health monitor service
systemctl status io-health-monitor.service

# Follow the I/O health log
tail -f /var/log/io-health.log
```

3) Snapshot and recovery

```bash
# Create a manual snapshot
create-system-snapshot

# Manage the automatic snapshot timer
systemctl enable system-snapshot.timer
systemctl disable system-snapshot.timer
systemctl status system-snapshot.timer

# List snapshots
ls -l /persistent/snapshots/
```

4) Telemetry and performance metrics

```bash
# View collected metrics
cat /persistent/telemetry/performance-metrics.csv

# Manage telemetry timer/service
systemctl status performance-telemetry.timer
systemctl enable performance-telemetry.timer
systemctl disable performance-telemetry.timer
```

5) Power-failure detection and emergency handling

```bash
# View power-failure service
systemctl status power-failure-detector.service

# Follow power event log
tail -f /var/log/power-events.log
```

---

## Atomic Update System

The image uses an atomic-update design: updates are prepared in a staging area, converted to a read-only root image (squashfs/erofs), then atomically swapped in. This reduces the chance of an unbootable system after an interrupted update.

Basic commands

```bash
# Run the update (do not interrupt)
atomic-update-manager update-system

# Roll back the last transaction (if a failure occurred)
atomic-update-manager rollback

# Show current transaction status
atomic-update-manager status
```

Snapshot management

```bash
# Create a snapshot before update
atomic-snapshot pre-update

# List snapshot information
atomic-snapshot info

# Rotate snapshots (manual)
atomic-snapshot rotate

# Set maximum snapshots to retain
atomic-snapshot set-max 5
```

Recovering from snapshots

```bash
# List available recovery archives
atomic-recovery list

# Recover from a snapshot archive
atomic-recovery recover /persistent/snapshots/atomic-snapshot-YYYYMMDD-HHMMSS.tar.gz
```

Notes
- The update process will verify squashfs integrity and back up the previous root image before switching.
- mkinitcpio is executed inside the staging environment with minimal bind mounts; if mkinitcpio fails the transaction will be aborted and rolled back.
- The rollback action restores the previous squashfs image and kernel artifacts from backup.

---

## Advanced Optimizations

This section lists optional services and helpers that are installed in the runtime image.

ZSWAP configuration

```bash
# Reconfigure zswap with current heuristics
/usr/local/bin/configure-zswap

# View zswap parameters
cat /proc/sys/vm/zswap*
cat /sys/module/zswap/parameters/*
```

Bcachefs optimizations

```bash
# Apply bcachefs optimizations
/usr/local/bin/optimize-bcachefs

# Show bcachefs status
bcachefs fs show /dev/disk/by-label/ARCH_PERSIST
```

Smart prefetch

```bash
# Run on-login prefetch
smart-prefetch on-login

# Run periodic prefetch
smart-prefetch periodic
```

Service management examples

```bash
systemctl status configure-zswap.service
systemctl status bcachefs-optimize.service
systemctl status smart-prefetch.timer
```

---

## Package Management & Cache Cleaning

To minimize used space on removable media the installer includes automatic cache management.

Configuration variables (set these in the environment or edit the top of `usb_arch.sh`):

- AUTO_CLEAN_CACHE=true|false — enable or disable automatic cleaning (default: true)
- CACHE_CLEAN_STRATEGY=immediate|batch|smart — cleaning strategy (default: immediate)
- CACHE_BATCH_THRESHOLD=N — number of installs before a batch clean (default: 5)

Strategies

- immediate: Clean caches after every successful package installation.
- batch: Clean caches every N successful installs (controlled by CACHE_BATCH_THRESHOLD).
- smart: Inspect the installed package's size and clean only for large packages (>= ~50MB).

Examples

```bash
# Disable automatic cache cleaning for troubleshooting
export AUTO_CLEAN_CACHE=false

# Use batch cleaning every 10 packages
export CACHE_CLEAN_STRATEGY=batch
export CACHE_BATCH_THRESHOLD=10

# Use smart cleaning behavior
export CACHE_CLEAN_STRATEGY=smart
```

Atomic update staging cache cleaning

- During `atomic-update-manager update-system`, the updater will proactively clean the staging root's pacman cache (inside the staging chroot) before creating the squashfs image to minimize the image size.

Manual cache cleaning

```bash
# Clean pacman cache and AUR helper caches (when running on the installed system)
clean_package_cache

# Silent mode
clean_package_cache true
```

Tradeoffs

- Cleaning caches reduces disk usage but removes the local package artifacts that enable quick local reinstalls.
- If you need offline reinstalls from the USB drive, set `AUTO_CLEAN_CACHE=false` or use the batch/smart strategies.

---

## Kernel & Driver Notes

Kernel compatibility

- The installer attempts to keep the installed kernel compatible with the running live environment.
- If you need a different kernel version, boot the live environment with your desired kernel and re-run the installer.

Rebuilding initramfs

```bash
# Rebuild initramfs for a specific kernel
mkinitcpio --kernel <kernel-version> -P

# Rebuild for all installed kernels
mkinitcpio -P
```

GRUB boot entries

The system ships with multiple boot menu entries (automatic profile selection, low/medium/high resource modes, safe mode, recovery, snapshot recovery).

---

## Logging and troubleshooting

- Installer logs: `/var/log/arch_usb/arch_usb.log`
- Atomic update logs: `/var/log/atomic-updates.log`
- I/O health: `/var/log/io-health.log`
- Snapshot operations: `/persistent/snapshots/`

Use `journalctl -xe` to inspect systemd journal messages and `tail -f` to follow specific logs.

---

If you want, I can add a short Quick Start section showing the exact sequence to create a bootable USB, partition, and run the installer in an end-to-end example.