# Guide: Using SSH with Arch Live

Using SSH allows you to control the installation from another computer. This is **highly recommended** as it lets you easily copy-paste commands.

### Prerequisites
-   Your Arch Live environment is connected to the internet (see [Internet Guide](./002_connect_internet.md)).
-   You have another computer (the "client") on the same network.

---

### Step 1: On the Arch Live Environment (The "Server")

1.  **Set a root password.** SSH requires a password for the `root` user to log in.
    ```bash
    passwd
    ```
    Enter a temporary, simple password (like "root"). You will only need it once.

2.  **Start the SSH service.**
    ```bash
    systemctl start sshd
    ```

3.  **Find the IP Address.** You will need this to connect from your client computer.
    ```bash
    ip addr show
    ```
    Look for the `inet` address under your active network interface (e.g., `enp3s0` or `wlan0`). It will look like `192.168.1.123`.

---

### Step 2: On Your Other Computer (The "Client")

1.  **Open a terminal** (on Linux/macOS) or **PowerShell/CMD** (on Windows).

2.  **Connect using the `ssh` command.** Replace `192.168.1.123` with the IP address you found in the previous step.
    ```bash
    ssh root@192.168.1.123
    ```

3.  **Accept the fingerprint.** The first time you connect, you will see a message like:
    `The authenticity of host '...' can't be established.`
    Type `yes` and press Enter.

4.  **Enter the password.** Enter the password you set for the `root` user earlier (e.g., "root").

You are now connected! Your terminal is controlling the Arch Live environment. You can now copy-paste commands, including the `curl` command to run Arch Gate.