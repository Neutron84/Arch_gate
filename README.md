# Arch Gate 🚀

**A Universal, Modular, and Hardware-Aware Framework for Deploying Optimized Arch Linux Systems.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![ShellCheck](https://github.com/Neutron84/Arch_gate/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Neutron84/Arch_gate/actions/workflows/shellcheck.yml)
[![Version: 0.5.0 (Alpha)](https://img.shields.io/badge/Version-0.5.0-orange.svg)]()

<!-- ![Arch Gate Banner](URL_BANNER_IMAGE_HERE)  -->

Arch Gate is not just an installer; it's a complete deployment solution. It transforms a minimal Arch Linux live environment into a fully configured, optimized, and reliable system, tailored to your specific hardware—whether it's an internal SSD, a portable USB drive, or an SD card.

---

## ✨ Key Features

-   **🖥️ Hardware-Aware Installation:** Automatically detects your storage type (`SSD`, `HDD`, `USB`, `SD Card`) and applies specific optimizations.
-   **⚙️ Two-Stage Architecture:** A lightweight **Stage 1** runs in the live environment, while a robust **Stage 2** completes the installation on the first boot, overcoming memory limitations.
-   **🛡️ Atomic Updates & Rollback:** Inspired by modern cloud systems, Arch Gate uses a read-only root filesystem (`EROFS`/`Squashfs`) with an overlay, ensuring that system updates are atomic and can be safely rolled back.
-   **🔌 Hybrid Boot for Portables:** Automatically configures `GRUB` for both **UEFI** and **Legacy BIOS**, making your portable systems universally bootable.
-   **🧠 Advanced Safety & Recovery:** Includes a suite of `systemd` services to protect your data, such as an I/O health monitor, power failure detector, and automatic snapshotting.
-   **🚀 Performance Tuned:** Comes with dynamic memory optimization (ZRAM/ZSWAP), smart application prefetching, and hardware-specific profiles out of the box.

---

## 🚀 Auto clone and install

>[!CAUTION] 
>This script will partition and format your target disk. All data will be permanently lost. Please double-check your device path.

1.  **Boot into a fresh Arch Linux live environment.**
    -   *Need help? Follow the [Guide to Creating an Arch Linux Live USB](./guides/create_live_boot.md).*

2.  **Establish an internet connection.** The installer needs to download packages.
    -   *For detailed steps, see the [Guide to Connecting to the Internet in Arch Live](./guides/connect_internet.md).*

3.  **Run the Arch Gate launcher.**
    Copy and paste the following command into your terminal:
    ```bash
    curl -sL https://raw.githubusercontent.com/Neutron84/Arch_gate/main/gate.sh |  bash
    ```
    This will download the launcher, which clones the full project and starts the interactive installer.

4.  **(Optional but Highly Recommended) Connect via SSH.**
    -   After connecting to the internet, you can control the installation from another computer for a much better experience (copy-paste, etc.).
    -   *Learn how: [Guide to Using SSH with Arch Live](./guides/using_ssh.md).*


---

## 🔧 The Installation Process

### Stage 1: The Interactive Bootstrap

The initial script will guide you through a series of questions to build a configuration tailored to your needs:

1.  **System Type Selection:** Choose between internal storage (`SSD`/`HDD`) or portable media.
2.  **Disk Selection:** Select the target device (e.g., `/dev/sda`).
3.  **Partition Scheme:** Choose between `Hybrid` (recommended for portables), `GPT` (UEFI-only), or `MBR`.
4.  **Filesystem:** Select `bcachefs` (recommended), `ext4`, or `f2fs`.
5.  **User & System Setup:** Configure your hostname, passwords (securely hashed), timezone, and locale.
6.  **Software Selection:** Choose which software groups you want to install (Desktop, Dev Tools, etc.).

Once Stage 1 is complete, you can reboot into your new minimal system.

<!-- ![Stage 1 Demo](URL_TO_STAGE1_DEMO.gif) -->

### Stage 2: The First Boot Provisioning

On the first boot, a `systemd` service will automatically take over and complete the installation non-interactively:

-   Installs all the software you selected.
-   Configures the advanced features (OverlayFS, Atomic Updates, Optimizations).
-   Sets up the GRUB bootloader with advanced menu entries.
-   Cleans up after itself and reboots into your fully functional system.

---

## 📖 Full Documentation

For a deep dive into all the features, commands, and runtime services, please refer to the **[USER MANUAL](./MANUAL.md)**.

## 🤝 Contributing

Contributions are welcome! If you'd like to help, please open an issue to discuss your idea or submit a pull request. All shell scripts are checked with `shellcheck`.

## 📜 License


This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
