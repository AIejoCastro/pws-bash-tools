# Datacenter Administration Tools

A pair of interactive sysadmin tools built for data center administrators — one for Linux, one for Windows. Both present the same menu-driven interface and cover the most common day-to-day tasks: inspecting users, disks, memory, large files, and performing USB backups.

| File | Platform | Language |
|------|----------|----------|
| `datacenter_tool.sh` | Ubuntu / Debian Linux | Bash |
| `datacenter_tool.ps1` | Windows 10 / 11 | PowerShell 5.1+ |

---

## Features

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
```

| # | Feature | What it shows |
|---|---------|---------------|
| 1 | **System Users & Last Login** | All interactive user accounts, lock status, and exact last login date/time |
| 2 | **Connected Filesystems / Disks** | Every mounted real disk with total size and free space in bytes |
| 3 | **Top 10 Largest Files** | Recursively finds the 10 biggest files under any path you specify |
| 4 | **Memory & Swap Usage** | Free RAM and swap/page-file consumption in bytes and as a percentage |
| 5 | **Backup Directory to USB** | Copies a directory to a USB drive and generates a `catalog.txt` manifest |

The menu loops after every option — the tool stays open until you explicitly choose **0 to exit**.

---

## Quick Start

### Linux

```bash
# Make the script executable (one-time)
chmod +x datacenter_tool.sh

# Run with elevated privileges for full output
sudo ./datacenter_tool.sh
```

### Windows

```powershell
# Allow local scripts to run (one-time, in an Admin PowerShell window)
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Run as Administrator
.\datacenter_tool.ps1
```

> Both scripts require **Administrator / root privileges** to display complete information for all options. They will still run without elevated rights, but some output may be partial.

---

## Documentation

| Document | Description |
|----------|-------------|
| [`INSTRUCTIONS.md`](INSTRUCTIONS.md) | Step-by-step usage guide for every menu option, with sample output, common errors, and platform-specific tips |
| [`TECHNICAL_EXPLANATION.md`](TECHNICAL_EXPLANATION.md) | In-depth explanation of how each function works internally — commands used, parsing logic, design decisions, and a side-by-side comparison of both scripts |

---

## Requirements

### Linux (`datacenter_tool.sh`)

- Ubuntu 20.04+ or Debian 11+
- Bash 4.0 or newer
- GNU coreutils (`df`, `find`, `stat`, `awk`, `cp`) — pre-installed
- `lastlog` — part of the `login` package, pre-installed on Ubuntu/Debian

### Windows (`datacenter_tool.ps1`)

- Windows 10 or Windows 11
- PowerShell 5.1 or newer (pre-installed on Windows 10/11)
- Administrator account recommended

---

## File Structure

```
pws-bash-tools/
├── datacenter_tool.sh        # Bash script (Linux)
├── datacenter_tool.ps1       # PowerShell script (Windows)
├── README.md                 # This file
├── INSTRUCTIONS.md           # User guide
└── TECHNICAL_EXPLANATION.md  # Internal logic and design explanation
```

---

## Authors

Developed as a final project for the Operating Systems course — Doceavo Semestre.
