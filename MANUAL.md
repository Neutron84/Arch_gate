# Arch Gate — User Manual

This manual provides a comprehensive reference for the tools, services, and workflows included in the Arch Gate runtime image.

## Table of Contents
- [Arch Gate — User Manual](#arch-gate--user-manual)
  - [Table of Contents](#table-of-contents)
    - [1. System Architecture Overview](#1-system-architecture-overview)
      - [Stage 1 \& 2 Flow](#stage-1--2-flow)
      - [Overlay Root \& Persistence](#overlay-root--persistence)
    - [2. Atomic Update System](#2-atomic-update-system)
    - [3. Safety \& Recovery Services](#3-safety--recovery-services)
    - [4. Advanced Optimizations](#4-advanced-optimizations)
    - [5. Package Management](#5-package-management)
    - [6. Troubleshooting \& Logs](#6-troubleshooting--logs)

---

### 1. System Architecture Overview

#### Stage 1 & 2 Flow
Arch Gate uses a two-stage installation process. **Stage 1** runs in the live environment, gathers user configuration, partitions the disk, and installs a minimal base system. It then creates and enables a `systemd` service (`archgate-stage2.service`) to run on the first boot.

**Stage 2** takes over automatically on the new system. It reads the configuration from `/etc/archgate/config.conf` and completes the installation non-interactively, including all software packages, drivers, and advanced feature modules like the Atomic Update System. After a successful run, it removes itself.

#### Overlay Root & Persistence
For portable system types, Arch Gate configures a robust overlay filesystem:
-   **Base Layer (Read-Only):** The core operating system is stored in a compressed `EROFS` or `Squashfs` image located at `/persistent/arch/root.squashfs`. This layer is immutable.
-   **Overlay Layer (Writable):** A `tmpfs` (RAM-based filesystem) is used for all runtime changes. This means all changes are temporary and are discarded on reboot, ensuring a clean state every time.
-   **Persistent Data:** Your personal data is safe. The `/home` directory is symlinked to `/persistent/home/` on the physical partition, so your files, downloads, and user-specific application settings survive reboots.

---

### 2. Atomic Update System
This system allows you to update your OS without risking an unbootable state. Updates are built in the background and only swapped in after successful completion.

**Commands:**
```bash
# Check for updates, build, and apply a new system image
sudo atomic-update-manager update-system

# If an update causes issues, revert to the previous working state
sudo atomic-update-manager rollback

# View the status of the last transaction
atomic-update-manager status
```
For more details on managing snapshots and recovery, see the `atomic-snapshot` and `atomic-recovery` commands.

---

### 3. Safety & Recovery Services
Arch Gate includes several background services to protect your system and data.

| Service (`.service` or `.timer`) | Description                                                                                             | How to Check                                       |
| :------------------------------- | :------------------------------------------------------------------------------------------------------ | :------------------------------------------------- |
| `periodic-sync.timer`            | Periodically forces data to be written to the physical disk to prevent data loss.                       | `systemctl status periodic-sync.timer`             |
| `io-health-monitor.service`      | Monitors for excessive I/O errors and can automatically switch the system to read-only to prevent corruption. | `tail -f /var/log/io-health.log`                   |
| `system-snapshot.timer`          | Creates daily snapshots of critical configuration files in `/persistent/snapshots/`.                      | `ls -l /persistent/snapshots`                      |
| `power-failure-detector.service` | Detects a switch to battery power (on laptops) and triggers a safe sync.                                | `tail -f /var/log/power-events.log`                |

---

### 4. Advanced Optimizations
The system automatically applies performance tuning based on your hardware.

-   **Memory:** ZRAM and ZSWAP are configured based on total system RAM to reduce disk I/O. Check with `sudo zramctl` or `cat /sys/module/zswap/parameters/*`.
-   **Hardware Profiles:** On boot, a script detects your CPU/GPU/RAM and applies specific environment variables for better performance. Check the current profile in `/var/lib/hardware-profile/current`.
-   **Prefetching:** A `systemd` timer periodically analyzes application usage and pre-loads them into memory for faster startup.

---

### 5. Package Management
The system uses `pacman` and can be configured with an AUR helper.

**Cache Cleaning:**
To save space, package caches can be automatically cleaned. This behavior is configured during Stage 1 via environment variables. You can manually trigger a clean with:
```bash
# Clean pacman and AUR helper caches
sudo clean_package_cache
```

---

### 6. Troubleshooting & Logs
Key log files are located in `/var/log/`.

-   **Installation Log:** `/var/log/archgate/stage2.log`
-   **Atomic Updates:** `/var/log/atomic-updates.log`
-   **I/O Health:** `/var/log/io-health.log`

For system-wide issues, use `journalctl`:
```bash
# View all recent logs
journalctl -xe

# Follow logs from the boot process
journalctl -b -f
```