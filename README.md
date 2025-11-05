# Arch Gate — Universal Arch Linux Installer and Runtime

This repository contains a feature-rich Arch Linux installer/runtime that supports both real systems (internal SSD/HDD) and portable media (USB/SD) with hybrid boot. It includes overlay root, atomic updates, safety & recovery, and advanced optimizations.

What this repo provides
- `gate.sh` — lightweight launcher (downloads repo and starts Stage 1).
- `archgate/stages/stage1.sh` — interactive configuration (system type, device, partitioning, minimal install).
- `archgate/stages/stage2.sh` — completes configuration inside the installed system and integrates advanced modules.
- `archgate/lib/*.sh` — feature modules (overlay, atomic-update, safety, memory, optimizations, grub advanced).
- `MANUAL.md` — user manual and reference for runtime services.

Quick start

Run from a live Arch system (one-liner setup and run):

```bash
curl -sL https://raw.githubusercontent.com/Neutron84/Arch_gate/main/gate.sh | sudo bash
```

This downloads and runs the lightweight launcher `gate.sh`, which clones the full project to `/tmp/arch-gate` and starts Stage 1.

Stage 1 highlights
- Choose system type: `ssd`, `hdd`, `ssd_external`, `hdd_external`, `usb_memory`, `sdcard`.
- Partition scheme: Hybrid (recommended for portable), GPT, or MBR.
- Filesystem: `bcachefs` (recommended), `ext4`, or `f2fs`.

Stage 2 highlights
- Configures overlay root (EROFS/Squashfs) and persistent `/home`.
- Enables atomic update system with rollback and integrity checks.
- Installs safety services (I/O health, enforced sync, snapshots, telemetry, power-failure detector).
- Tunes memory (ZRAM/ZSWAP) and applies advanced optimizations (bcachefs, prefetch, hardware profile, I/O optimizer).
- Installs GRUB hybrid for portable systems and writes advanced boot menus.

Important notes
- This script performs destructive operations (drive partitioning, filesystem creation). Ensure you target the correct device and have backups.
- Portable targets use hybrid boot and overlay root with read-only images to improve robustness.

Package cache cleaning (space-saving behavior)

To keep the USB image small the installer includes automatic package cache management. You can configure behavior by setting environment variables before running the installer or editing the top of `usb_arch.sh`:

- `AUTO_CLEAN_CACHE` (default: `true`) — enable/disable automatic cache cleaning.
- `CACHE_CLEAN_STRATEGY` (default: `immediate`) — `immediate|batch|smart`.
- `CACHE_BATCH_THRESHOLD` (default: `5`) — number of successful installs before a batch clean (only used with `batch`).

Examples

```bash
# Disable automatic cache cleaning
export AUTO_CLEAN_CACHE=false

# Use batch cleaning every 10 packages
export CACHE_CLEAN_STRATEGY=batch
export CACHE_BATCH_THRESHOLD=10

# Use smart cleaning (clean only for large packages)
export CACHE_CLEAN_STRATEGY=smart
```

Where to read more
- Full manual & reference: `MANUAL.md` (includes atomic update commands, services, overlay details, and troubleshooting).
- Logs: Stage 2 `/var/log/archgate/stage2.log`, atomic updates `/var/log/atomic-updates.log`.

Security & safety checklist
- Double-check the target device before running the installer (use `lsblk` and `blkid`).
- Create a snapshot before performing large operations when possible (`atomic-snapshot pre-update` on the installed system).

Contributing
- If you'd like to contribute, open issues or PRs against this repo. Please run `shellcheck` on any bash patches you submit.


