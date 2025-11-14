# Guide: Connecting to the Internet in Arch Live

This guide covers connecting to the internet using **LAN (Ethernet)**, **Wi-Fi**, and **USB Tethering** in the Arch Linux live environment without NetworkManager.

---

### Step 0: Identify Your Network Interface

First, list all network interfaces to find the correct name.

```bash
ip link
```

**Example Output:**
```
1: lo: <LOOPBACK,UP,...>  # Ignore this
2: enp3s0: <BROADCAST,...> # This is a wired LAN (Ethernet) interface
3: wlan0: <BROADCAST,...>  # This is a Wi-Fi interface
```
*Your names may be different (e.g., `enp5s0`, `wlp2s0`).* Use the names you see.

---

### Method 1: Wired LAN (Ethernet)

This is the easiest method.

1.  **Connect** an Ethernet cable from your router to your computer.
2.  **Bring up the interface** (replace `enp3s0` with your LAN interface name):
    ```bash
    ip link set enp3s0 up
    ```
3.  **Get an IP address** using DHCP:
    ```bash
    dhcpcd enp3s0
    ```
4.  **Test the connection:**
    ```bash
    ping -c 3 archlinux.org
    ```
    If you see replies, you are connected!

---

### Method 2: Wi-Fi (using iwd)

1.  **Bring up the Wi-Fi interface** (replace `wlan0` with your Wi-Fi name):
    ```bash
    ip link set wlan0 up
    ```
    *If it's blocked, run `rfkill unblock all`.*

2.  **Start the `iwd` interactive tool:**
    ```bash
    iwctl
    ```

3.  **Inside `iwctl`, run these commands:**
    ```bash
    # Show available devices
    [iwd]# device list
    
    # Scan for networks (replace wlan0 if needed)
    [iwd]# station wlan0 scan
    
    # List available networks
    [iwd]# station wlan0 get-networks
    
    # Connect to your network (replace "Your_WiFi_Name")
    [iwd]# station wlan0 connect "Your_WiFi_Name"
    ```
    You will be prompted to enter your Wi-Fi password.

4.  **Exit `iwctl`:**
    ```bash
    [iwd]# exit
    ```

5.  **Get an IP address:**
    ```bash
    dhcpcd wlan0
    ```

6.  **Test the connection:**
    ```bash
    ping -c 3 archlinux.org
    ```

---

### Method 3: USB Tethering (Mobile Internet)

1.  **On your phone:**
    -   Connect it to your computer with a USB cable.
    -   Go to `Settings` -> `Network & internet` -> `Hotspot & tethering`.
    -   Enable **USB tethering**.
2.  **Find the new interface name** (it's often `usb0` or similar):
    ```bash
    ip link
    ```
3.  **Get an IP address** (replace `usb0` if needed):
    ```bash
    dhcpcd usb0
    ```
4.  **Test the connection:**
    ```bash
    ping -c 3 archlinux.org
