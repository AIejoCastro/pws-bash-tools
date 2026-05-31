# Datacenter Administration Tools — User Guide

Two interactive sysadmin tools for data center administrators:

- **`datacenter_tool.sh`** — Bash script for Ubuntu / Debian Linux
- **`datacenter_tool.ps1`** — PowerShell script for Windows 10 / 11

Both tools present the same menu-driven interface with five options and loop back to the menu after each action until you choose to exit.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Quick Start](#quick-start)
   - [Linux (Bash)](#linux-bash)
   - [Windows (PowerShell)](#windows-powershell)
3. [Menu Options](#menu-options)
   - [Option 1 — System Users & Last Login](#option-1--system-users--last-login)
   - [Option 2 — Connected Filesystems / Disks](#option-2--connected-filesystems--disks)
   - [Option 3 — Top 10 Largest Files](#option-3--top-10-largest-files)
   - [Option 4 — Memory & Swap Usage](#option-4--memory--swap-usage)
   - [Option 5 — Backup Directory to USB](#option-5--backup-directory-to-usb)
   - [Option 0 — Exit](#option-0--exit)
4. [Permissions & Privileges](#permissions--privileges)
5. [Error Reference](#error-reference)
6. [Examples](#examples)

---

## Requirements

### Linux (`datacenter_tool.sh`)

| Requirement | Notes |
|---|---|
| Ubuntu 20.04+ or Debian 11+ | Other systemd-based distros likely work too |
| Bash 4.0 or newer | Pre-installed on all modern Ubuntu/Debian |
| `lastlog` command | Part of the `login` package — pre-installed by default |
| `df`, `find`, `stat`, `awk` | All part of GNU coreutils — pre-installed |
| Root / `sudo` | Recommended for full output (some user and disk data requires elevated access) |

### Windows (`datacenter_tool.ps1`)

| Requirement | Notes |
|---|---|
| Windows 10 / 11 | Either 32-bit or 64-bit |
| PowerShell 5.1 or newer | Pre-installed on Windows 10/11; PowerShell 7+ also supported |
| Administrator account | Required for memory, page file, and local user details |

---

## Quick Start

### Linux (Bash)

**Step 1 — Download or copy the script to your server.**

**Step 2 — Make it executable** (only needed once):

```bash
chmod +x datacenter_tool.sh
```

**Step 3 — Run it** (with `sudo` for full access):

```bash
sudo ./datacenter_tool.sh
```

You will see the main menu immediately:

```
============================================
    DATA CENTER ADMINISTRATION TOOL
============================================
 1. System Users & Last Login
 2. Connected Filesystems / Disks
 3. Top 10 Largest Files
 4. Memory & Swap Usage
 5. Backup Directory to USB
 0. Exit
============================================
Select an option [0-5]:
```

Type a number and press **Enter** to run that option.

---

### Windows (PowerShell)

**Step 1 — Allow local scripts** (run this once in an Administrator PowerShell window):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

> This is a one-time step. It allows locally created scripts to run while keeping internet-downloaded scripts blocked unless signed.

**Step 2 — Open PowerShell as Administrator.**

Right-click the Start button → **Terminal (Admin)** or **Windows PowerShell (Admin)**.

**Step 3 — Navigate to the script folder and run it:**

```powershell
cd "C:\path\to\scripts"
.\datacenter_tool.ps1
```

The same interactive menu appears. Type a number and press **Enter**.

---

## Menu Options

### Option 1 — System Users & Last Login

**What it does:**
Lists every user account that has a real interactive login shell, along with:
- Whether the account is enabled or locked
- The exact date and time of the user's last successful login

**How to use it:**

1. Select `1` from the menu and press Enter.
2. The output appears immediately — no further input needed.

**Sample output (Linux):**

```
=== System Users & Last Login ===

USERNAME               UID    ENABLED    LAST LOGIN
--------               ---    -------    ----------
root                   0      Yes        Never logged in
alejandro              1000   Yes        Fri May 30 09:14:22 2025
backup_user            1001   No (locked) Never logged in
```

**Sample output (Windows):**

```
=== System Users & Last Login ===

USERNAME                  ENABLED    LAST LOGON             DESCRIPTION
--------                  -------    ----------             -----------
Administrator             No         Never / Unknown        Built-in account for administering
alejandro                 Yes        2025-05-30 09:14:22    -
Guest                     No         Never / Unknown        Built-in account for guest access
```

> **Note:** On Windows, `LastLogon` is only populated for local accounts. Domain accounts managed via Active Directory will show `Never / Unknown`.

---

### Option 2 — Connected Filesystems / Disks

**What it does:**
Lists every mounted real filesystem and shows:
- The device or source identifier
- Total size in bytes
- Free (available) space in bytes
- The mount point (Linux) or drive letter (Windows)

Virtual filesystems (`tmpfs`, `devtmpfs`, snap loop mounts, etc.) are filtered out automatically on Linux.

**How to use it:**

1. Select `2` from the menu and press Enter.
2. The output appears immediately.

**Sample output (Linux):**

```
=== Connected Filesystems / Disks ===

DEVICE                              TOTAL (bytes)      FREE (bytes)       MOUNT POINT
------                              -------------      ------------       -----------
/dev/sda1                           512110190592       312489123840       /
/dev/sdb1                           2000398934016      1845123072000      /data
/dev/sdc1                           62914560000        58234880000        /media/user/USB
```

**Sample output (Windows):**

```
=== Connected Filesystems / Disks ===

DRIVE      TOTAL (bytes)          FREE (bytes)           LABEL / DESCRIPTION
-----      -------------          ------------           --------------------
C:\        511760465920           213492736000           Windows
D:\        2000398934016          1400123072000          Data
E:\        62914560000            58234880000            USB_DRIVE
```

---

### Option 3 — Top 10 Largest Files

**What it does:**
Recursively scans a directory you specify and returns the 10 largest files, sorted by size descending, showing the full path and exact size in bytes.

**How to use it:**

1. Select `3` from the menu and press Enter.
2. When prompted, type the full path to the directory you want to scan and press Enter.

```
Enter the directory path to search: /var/log
```

3. Wait for the scan to complete (large directories with many files may take several seconds).

**Sample output:**

```
=== Top 10 Largest Files ===

Searching in '/var/log' (permission errors silently skipped)...

SIZE (bytes)           FILE PATH
------------           ---------
2415919104             /var/log/syslog.1
1073741824             /var/log/kern.log
524288000              /var/log/auth.log.2.gz
...
```

> **Tip:** To search an entire disk, enter the mount point (e.g. `/data` on Linux or `D:\` on Windows). On large volumes this can take a few minutes.

> **Note:** Files you do not have read permission to access are silently skipped and will not appear in the results.

---

### Option 4 — Memory & Swap Usage

**What it does:**
Shows a snapshot of current memory usage:
- Total installed RAM
- Available (free) RAM in bytes and as a percentage
- Total swap / page file size
- Swap / page file currently in use, in bytes and as a percentage

**How to use it:**

1. Select `4` from the menu and press Enter.
2. The output appears immediately — no further input needed.

**Sample output (Linux):**

```
=== Memory & Swap Usage ===

--- RAM ---
  Total RAM      : 16777216000 bytes
  Available RAM  : 9663676416 bytes  (57.60% free)

--- Swap ---
  Total Swap     : 4294967296 bytes
  Swap In Use    : 524288000 bytes  (12.21% used)
```

**Sample output (Windows):**

```
=== Memory & Swap Usage ===

--- RAM ---
  Total RAM      :        17179869184 bytes
  Available RAM  :         9663676416 bytes  (56.25% free)

--- Page File (Swap) ---
  File           : C:\pagefile.sys
  Total Size     :         4294967296 bytes
  In Use         :          524288000 bytes  (12.21% used)
```

> **Note on Linux:** "Available RAM" uses `MemAvailable` from `/proc/meminfo`, which accounts for reclaimable cache — this is a more accurate picture of what applications can actually use than `MemFree`.

> **Note on Windows:** Page file data requires Administrator privileges. If the script is not run as Admin, a warning is shown but the RAM section still displays correctly.

---

### Option 5 — Backup Directory to USB

**What it does:**
Copies an entire directory tree to a USB drive (or any other destination path) and generates a **`catalog.txt`** file alongside the backup listing every file's name and last modification date.

**How to use it:**

1. Make sure your USB drive is connected and mounted.
   - **Linux:** Check the mount point with `lsblk` or option 2. Common paths: `/media/username/DRIVENAME` or `/mnt/usb`.
   - **Windows:** Check the drive letter with option 2. Common paths: `E:\Backup`, `F:\`.

2. Select `5` from the menu and press Enter.

3. Enter the **source directory** (the folder you want to back up):

```
Enter the source directory to back up: /home/alejandro/documents
```

4. Enter the **USB destination path**:

```
Enter the USB mount path (e.g. /media/user/USBDRIVE):  /media/alejandro/MY_USB
```

   On Windows:
```
Enter the USB destination path (e.g. E:\Backup):  E:\Backup
```

5. The script validates both paths, checks available space, copies the files, and generates the catalog.

**Sample output:**

```
=== Backup Directory to USB ===

Copying '/home/alejandro/documents' → '/media/alejandro/MY_USB' (this may take a while)...
Files copied successfully.

Generating '/media/alejandro/MY_USB/catalog.txt'...
Catalog generated successfully.

Backup complete!
  Source    : /home/alejandro/documents
  USB path  : /media/alejandro/MY_USB
  Catalog   : /media/alejandro/MY_USB/catalog.txt
```

**catalog.txt format:**

```
BACKUP CATALOG
==============
Source      : /home/alejandro/documents
Destination : /media/alejandro/MY_USB
Created     : 2025-05-30 09:45:00

FILE NAME                                                    LAST MODIFIED
---------                                                    -------------
budget_2025.xlsx                                             2025-05-15 14:30:00
network_diagram.pdf                                          2025-04-02 09:10:00
server_inventory.csv                                         2025-05-29 17:55:22
```

> **Warning:** The script will overwrite existing files at the destination if they share the same name. Make sure the destination path is correct before confirming.

---

### Option 0 — Exit

Select `0` and press Enter to quit the program cleanly.

---

## Permissions & Privileges

| Feature | Linux (without sudo) | Linux (with sudo) | Windows (Standard) | Windows (Admin) |
|---|---|---|---|---|
| List users & last login | Partial (own user only with lastlog) | Full | Partial | Full |
| List filesystems | Full | Full | Full | Full |
| Top 10 largest files | Skips restricted dirs | Full | Skips restricted dirs | Full |
| Memory & Swap | Full | Full | RAM only | Full (RAM + page file) |
| Backup to USB | Own files only | Full | Own files only | Full |

**Recommendation:** Always run these tools with elevated privileges (`sudo` on Linux, Administrator on Windows) to ensure complete and accurate output.

---

## Error Reference

| Error Message | Cause | Solution |
|---|---|---|
| `Error: 'lastlog' is not installed` | The `login` package is missing | Run `sudo apt install login` |
| `Error: '/path' is not a valid directory` | The entered path does not exist or is a file | Double-check the path and try again |
| `Error: Not enough free space on USB` | The source is larger than available USB space | Free up space or use a larger USB drive |
| `Error: USB mount path does not exist` | USB is not mounted or path is wrong | Run option 2 to confirm the correct path |
| `Warning: path does not appear to be a mount point` | The destination path exists but is not a mount point | Confirm you entered the right USB path; choose Y to continue or N to cancel |
| `Error: Drive 'X:\' is not available` (Windows) | USB is not connected or drive letter is wrong | Reconnect the USB and run option 2 to verify the drive letter |
| `Error: Could not retrieve local users. Run as Administrator` (Windows) | Script is not running with elevated privileges | Restart PowerShell as Administrator |

---

## Examples

### Linux — Full walkthrough

```bash
# 1. Make the script executable
chmod +x datacenter_tool.sh

# 2. Run with elevated privileges
sudo ./datacenter_tool.sh

# 3. At the menu, press 4 then Enter to check memory
# 4. Press Enter to return to the menu
# 5. Press 5 then Enter to start a backup
#    Source:      /etc
#    Destination: /media/root/BACKUP_USB
# 6. Press 0 then Enter to exit
```

### Windows — Full walkthrough

```powershell
# 1. Open PowerShell as Administrator (right-click Start → Terminal Admin)

# 2. Allow local scripts (one-time setup)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# 3. Navigate to the scripts folder
cd "C:\Tools\datacenter"

# 4. Run the tool
.\datacenter_tool.ps1

# 5. At the menu, press 2 then Enter to list drives and find the USB letter
# 6. Press 5 then Enter to start a backup
#    Source:      C:\Users\Admin\Documents
#    Destination: E:\Backup
# 7. Press 0 then Enter to exit
```
