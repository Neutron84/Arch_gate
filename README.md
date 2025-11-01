# Arch_USB — Bootable Arch Linux USB installer and runtime

This repository contains a feature-rich Arch Linux USB installer/runtime image builder and a set of helper tools that run on the installed USB system.

What this repo provides
- `usb_arch.sh` — the main installer script (download and run on a live Arch environment).
- `MANUAL.md` — user manual and reference for runtime services (now available in English).
- Atomic update tools, snapshotting, and safety helpers installed on the target system.

Quick start

Run the installer from a live Arch system (this will download the latest `usb_arch.sh` from the repository and run it):

```bash
curl -Lf https://raw.githubusercontent.com/Neutron84/Arch_USB/main/usb_arch.sh -o usb_arch.sh && chmod +x usb_arch.sh && ./usb_arch.sh
```

Important notes
- This script performs destructive operations (drive partitioning, filesystem creation). Make sure you run it on the intended device and have backups of any important data.
- The installer and runtime are designed for removable media (USB) and employ atomic updates (read-only root images) to reduce the chance of leaving the system in an unbootable state after interrupted updates.

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
- Full manual & reference: `MANUAL.md` (includes atomic update commands, services, and troubleshooting).
- The installer writes logs to `/var/log/arch_usb/arch_usb.log` on the live environment and the installed system.

Security & safety checklist
- Double-check the target device before running the installer (use `lsblk` and `blkid`).
- Create a snapshot before performing large operations when possible (`atomic-snapshot pre-update` on the installed system).

Contributing
- If you'd like to contribute, open issues or PRs against this repo. Please run `shellcheck` on any bash patches you submit.

License
- See the `LICENSE` file in this repository.

Questions or improvements
- If you want a short Quick Start section that demonstrates an end-to-end example (partition, format, install), tell me and I will add it to this README.
