# Technical Explanation — Datacenter Administration Scripts

This document explains how each script is structured internally: the language constructs used, the system commands called, and the logic behind every function. It is intended for anyone who wants to understand, audit, or extend the tools.

---

## Table of Contents

1. [Script Architecture Overview](#1-script-architecture-overview)
2. [Bash Script — `datacenter_tool.sh`](#2-bash-script--datacenter_toolsh)
   - [Global Setup](#21-global-setup)
   - [Main Loop](#22-main-loop)
   - [Function: `show_menu`](#23-function-show_menu)
   - [Function: `list_users_and_logins`](#24-function-list_users_and_logins)
   - [Function: `list_filesystems`](#25-function-list_filesystems)
   - [Function: `top_10_largest_files`](#26-function-top_10_largest_files)
   - [Function: `show_memory_usage`](#27-function-show_memory_usage)
   - [Function: `backup_to_usb`](#28-function-backup_to_usb)
3. [PowerShell Script — `datacenter_tool.ps1`](#3-powershell-script--datacenter_toolps1)
   - [Global Setup](#31-global-setup)
   - [Main Loop](#32-main-loop)
   - [Function: `Show-Menu`](#33-function-show-menu)
   - [Function: `Get-UsersAndLogins`](#34-function-get-usersandlogins)
   - [Function: `Get-FilesystemInfo`](#35-function-get-filesysteminfo)
   - [Function: `Get-Top10LargestFiles`](#36-function-get-top10largestfiles)
   - [Function: `Get-MemoryAndSwapUsage`](#37-function-get-memoryanswapusage)
   - [Function: `Backup-ToUSB`](#38-function-backup-tousb)
4. [Side-by-Side Comparison](#4-side-by-side-comparison)

---

## 1. Script Architecture Overview

Both scripts share the same logical structure despite being written in different languages:

```
┌─────────────────────────────────────┐
│           Script starts             │
│  Global config / helper definitions │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│           Main loop                 │  ◄─────────────────────────┐
│  Show menu → read user input        │                             │
│  Dispatch to the matching function  │                             │
└────────────────┬────────────────────┘                             │
                 │                                                   │
      ┌──────────┼──────────┐                                        │
      ▼          ▼          ▼  ...                                   │
  Function1  Function2  Function3                                    │
  executes   executes   executes                                     │
      │          │          │                                        │
      └──────────┴──────────┘                                        │
                 │                                                   │
                 ▼                                                   │
      "Press Enter to continue" ──────────────────────────────────── ┘
                 │
         (user picks 0)
                 │
                 ▼
            exit / quit
```

Each option is isolated in its own function. The main loop never contains business logic — it only reads input, calls the right function, and then waits before looping again. This separation makes the code easier to read and extend.

---

## 2. Bash Script — `datacenter_tool.sh`

### 2.1 Global Setup

```bash
#!/bin/bash
```

The shebang line tells the OS to use `/bin/bash` to interpret this file. This is important: many systems have `/bin/sh` pointing to `dash`, which does not support Bash-specific syntax like `[[ ]]` or `<<<`.

```bash
RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'

err()  { echo -e "${RED}Error: $*${RESET}" >&2; }
warn() { echo -e "${YELLOW}Warning: $*${RESET}"; }
info() { echo -e "${CYAN}$*${RESET}"; }
```

**ANSI escape codes** are sequences that terminals interpret as formatting instructions rather than text. The format is `\033[<code>m` where `\033` is the ESC character (octal 33).

| Code | Effect |
|------|--------|
| `0;31` | Red foreground |
| `1;33` | Bold yellow foreground |
| `0;36` | Cyan foreground |
| `0;32` | Green foreground |
| `1` | Bold |
| `0` | Reset all formatting |

The three helper functions (`err`, `warn`, `info`) wrap `echo -e` (the `-e` flag enables escape sequence interpretation) so that coloured output can be called consistently from anywhere in the script. Errors are sent to `stderr` (`>&2`) so they can be redirected independently from normal output.

---

### 2.2 Main Loop

```bash
main() {
    while true; do
        show_menu
        read -r choice
        case "$choice" in
            1) list_users_and_logins  ;;
            2) list_filesystems       ;;
            ...
            0) exit 0 ;;
            *) warn "Invalid option..." ;;
        esac
        echo -n "Press Enter to return to the menu..."
        read -r
    done
}

main
```

- `while true` creates an infinite loop that only ends when `exit 0` is reached (option 0).
- `read -r` reads one line from stdin into the variable `choice`. The `-r` flag disables backslash interpretation so paths like `C:\Users` are read literally.
- `case "$choice" in ... esac` is Bash's multi-branch conditional. It matches the string in `$choice` against each pattern. The `*` at the end is a catch-all for any input that matches no other pattern.
- The final `read -r` (no variable) discards the Enter keypress, effectively pausing until the user is ready.
- The entire body is wrapped in a `main()` function that is called at the last line. This is a Bash best practice: it ensures all functions are defined before any of them are called.

---

### 2.3 Function: `show_menu`

```bash
show_menu() {
    echo -e "${BOLD}============================================${RESET}"
    ...
    echo -n "Select an option [0-5]: "
}
```

`echo -n` suppresses the trailing newline so the cursor stays on the same line as the prompt, waiting for input directly after the colon.

---

### 2.4 Function: `list_users_and_logins`

**Goal:** List all real user accounts and each account's last login time.

#### Step 1 — Dependency check

```bash
if ! command -v lastlog &>/dev/null; then
    err "'lastlog' is not installed."
    return
fi
```

`command -v <name>` returns the path to an executable if it exists, or nothing if it does not. Redirecting both stdout and stderr to `/dev/null` (`&>/dev/null`) silences all output — we only care about the exit code. If `lastlog` is missing the function exits early with an error rather than failing silently or crashing.

#### Step 2 — Reading `/etc/passwd` with `getent`

```bash
while IFS=: read -r username _ uid _ _ _ shell; do
    ...
done < <(getent passwd)
```

`getent passwd` queries the system's Name Service Switch (NSS) for all user accounts. Unlike reading `/etc/passwd` directly, `getent` also returns users from LDAP, NIS, or other directory services configured on the machine.

The colon-separated fields of `/etc/passwd` are:
```
username : password : uid : gid : comment : home : shell
```

`IFS=:` sets the Internal Field Separator to `:` so `read` splits each line on colons. The `_` variables are placeholders for fields we don't need (password hash, GID, comment, home). The `< <(...)` construct is **process substitution** — it feeds the output of `getent passwd` as if it were a file to the `while` loop.

#### Step 3 — Filtering accounts

```bash
if [[ "$uid" -eq 0 || "$uid" -ge 1000 ]] && \
   [[ "$shell" != */nologin && "$shell" != */false && "$shell" != */sync ]]; then
```

On Debian/Ubuntu, UIDs below 1000 are reserved for system service accounts (e.g. `www-data`, `daemon`). UID 0 is always root. The shell check uses the glob pattern `*/nologin` to match any path ending in `nologin` — this filters accounts that are explicitly marked as non-interactive.

#### Step 4 — Checking lock status

```bash
lock_flag=$(passwd -S "$username" 2>/dev/null | awk '{print $2}')
[[ "$lock_flag" == "L" ]] && status="No (locked)"
```

`passwd -S <user>` outputs a one-line status summary. The second field is a status code: `P` (password set), `L` (locked), or `NP` (no password). `awk '{print $2}'` extracts just that second field.

#### Step 5 — Parsing `lastlog` output

```bash
lastlog_line=$(lastlog -u "$username" 2>/dev/null | tail -1)

if echo "$lastlog_line" | grep -q "Never logged in"; then
    last_login="Never logged in"
else
    last_login=$(echo "$lastlog_line" | awk '{
        n = NF
        if (n >= 5) printf "%s %s %s %s %s", $(n-4), $(n-3), $(n-2), $(n-1), $n
        else        print "Unknown"
    }')
fi
```

`lastlog -u <user>` outputs exactly two lines: a header and a data row. `tail -1` discards the header.

The data line has variable-width fields (username, port, source IP, date). The date is always the last five space-separated tokens in the format: `Dow Mon DD HH:MM:SS YYYY`. The `awk` script counts total fields (`NF = Number of Fields`) and extracts the last five using negative offsets from `NF`. This approach is robust even if the username or IP contains unexpected whitespace.

#### Step 6 — Formatted output

```bash
printf "%-22s %-6s %-10s %s\n" "$username" "$uid" "$status" "$last_login"
```

`printf` with width specifiers (`%-22s` = left-aligned, 22 characters wide) aligns every row into readable columns regardless of the data length.

---

### 2.5 Function: `list_filesystems`

```bash
df -B1 --output=source,size,avail,target 2>/dev/null | tail -n +2 | \
while read -r source size avail target; do
    case "$source" in
        tmpfs|devtmpfs|udev|...) continue ;;
    esac
    [[ "$source" == /dev/loop* ]] && continue
    printf "%-35s %-18s %-18s %s\n" "$source" "$size" "$avail" "$target"
done
```

**`df` flags explained:**

| Flag | Meaning |
|------|---------|
| `-B1` | Report all sizes in units of 1 byte (no rounding to KB/MB) |
| `--output=source,size,avail,target` | Select specific columns: device, total bytes, available bytes, mount point |

`tail -n +2` skips the first line (the column header row).

The `case` statement filters out pseudo-filesystems that the Linux kernel exposes as filesystems but that do not correspond to real storage:

| Filtered type | What it is |
|---|---|
| `tmpfs` / `devtmpfs` | RAM-backed temporary filesystems |
| `sysfs` / `proc` | Kernel interfaces exposed as files |
| `cgroup` / `cgroup2` | Control group resource controllers |
| `devpts` | Pseudo-terminal device nodes |
| `overlay` | Docker/container layered filesystems |
| `/dev/loop*` | Snap package squashfs loop mounts (Ubuntu Desktop) |

---

### 2.6 Function: `top_10_largest_files`

```bash
find "$search_path" -type f -printf "%s\t%p\n" 2>/dev/null \
    | sort -rn \
    | head -10 \
    | while IFS=$'\t' read -r size filepath; do
          printf "%-22s %s\n" "$size" "$filepath"
      done
```

This is a **Unix pipeline** — each command's stdout feeds directly into the next command's stdin.

| Stage | Command | What it does |
|---|---|---|
| 1 | `find "$search_path" -type f -printf "%s\t%p\n"` | Recursively finds all regular files (`-type f`) and prints their size in bytes (`%s`) and full path (`%p`), separated by a tab |
| 2 | `sort -rn` | Sorts lines numerically (`-n`) in reverse/descending order (`-r`) |
| 3 | `head -10` | Keeps only the first 10 lines |
| 4 | `while IFS=$'\t' read -r size filepath` | Splits each tab-separated line into two variables |

Using `-printf "%s\t%p\n"` inside `find` is deliberately chosen over alternatives like `du` or `stat` because it outputs the size in a single pass without launching a separate process per file — this is significantly faster on directories with thousands of files.

`2>/dev/null` in the `find` command silently discards "Permission denied" errors so they don't clutter the output when searching directories the user cannot read.

---

### 2.7 Function: `show_memory_usage`

```bash
total_mem_kb=$(awk '/^MemTotal:/    {print $2}' /proc/meminfo)
free_mem_kb=$(awk  '/^MemAvailable:/{print $2}' /proc/meminfo)
total_swap_kb=$(awk '/^SwapTotal:/  {print $2}' /proc/meminfo)
free_swap_kb=$(awk  '/^SwapFree:/   {print $2}' /proc/meminfo)
```

**`/proc/meminfo`** is a virtual file maintained by the Linux kernel that exposes real-time memory statistics. Each line has the format `Label: value kB`. The `awk` pattern `/^MemTotal:/` matches the line that starts with that label and `{print $2}` extracts the numeric value (always in kilobytes).

**Why `MemAvailable` instead of `MemFree`?**

`MemFree` is the amount of RAM not used at all. `MemAvailable` is an estimate of how much memory is actually available for new applications — it includes `MemFree` plus reclaimable cache and buffers. On a busy server, `MemFree` can be near zero while the system is perfectly healthy because the kernel uses spare RAM as disk cache. `MemAvailable` gives a more accurate operational picture.

```bash
total_mem_bytes=$(( total_mem_kb * 1024 ))
```

Bash arithmetic expansion `$(( ... ))` performs integer arithmetic. `/proc/meminfo` always reports in kB, so multiplying by 1024 converts to bytes.

```bash
free_mem_pct=$(awk -v f="$free_mem_bytes" -v t="$total_mem_bytes" \
    'BEGIN { if (t>0) printf "%.2f", (f/t)*100; else print "N/A" }')
```

Bash cannot do floating-point arithmetic natively, so `awk` is used for the percentage calculation. The `-v` flag passes shell variables into awk as awk variables. The `BEGIN` block runs without needing input lines. The `if (t>0)` guard prevents division-by-zero on systems where memory information is somehow unavailable.

---

### 2.8 Function: `backup_to_usb`

#### Path validation

```bash
if [[ ! -d "$source_dir" ]]; then
    err "Source directory '$source_dir' does not exist."
    return
fi
```

`[[ -d path ]]` is a Bash conditional expression that returns true if `path` exists and is a directory. The `!` negates it. Using `return` (not `exit`) stops the current function and hands control back to the main loop — this is important so the entire script does not terminate on a user mistake.

#### Mount point check

```bash
if ! mountpoint -q "$usb_path" 2>/dev/null; then
    warn "'$usb_path' does not appear to be a mount point."
    echo -n "Continue anyway? [y/N]: "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Backup cancelled."; return; }
fi
```

`mountpoint -q <path>` exits with code 0 if the path is a genuine filesystem mount point, or non-zero if it is just a regular directory. The `-q` flag suppresses output. This warns the user if they accidentally typed a regular folder path instead of a USB mount point, while still allowing them to override and proceed.

#### Free space check

```bash
src_size=$(du -sb "$source_dir" 2>/dev/null | awk '{print $1}')
usb_free=$(df -B1 --output=avail "$usb_path" 2>/dev/null | tail -1 | xargs)
if [[ -n "$src_size" && -n "$usb_free" && "$src_size" -gt "$usb_free" ]]; then
    err "Not enough free space on USB."
    return
fi
```

`du -sb` calculates total disk usage of a directory in bytes (`-b`), summing all files (`-s` = summary, one line). `df -B1 --output=avail` reports available bytes on the filesystem at `$usb_path`. `xargs` trims surrounding whitespace from the `df` output. Both values are only compared if they are non-empty (the `-n` checks), guarding against commands that fail silently.

#### File copy

```bash
if cp -a "$source_dir/." "$usb_path/" 2>/tmp/cp_err; then
    echo -e "${GREEN}Files copied successfully.${RESET}"
else
    err "Copy failed: $(cat /tmp/cp_err)"
    return
fi
```

`cp -a` is **archive mode**, equivalent to `-dR --preserve=all`. It copies recursively (`-R`), preserves symbolic links (`-d`), and preserves file permissions, ownership, and timestamps.

The trailing `/.` on `"$source_dir/."` is a deliberate trick: it means "copy the *contents* of this directory into the destination" rather than "copy the directory itself as a subdirectory". Without it, `cp` would create `$usb_path/source_dir_name/` instead of placing files directly at `$usb_path/`.

Stderr is redirected to `/tmp/cp_err` so that if the copy fails, the specific error message can be displayed to the user.

#### Catalog generation

```bash
{
    echo "BACKUP CATALOG"
    ...
    find "$source_dir" -type f | sort | while read -r filepath; do
        fname=$(basename "$filepath")
        mtime=$(stat -c '%y' "$filepath" 2>/dev/null | cut -d'.' -f1)
        printf "%-60s %s\n" "$fname" "${mtime:-unknown}"
    done
} > "$catalog_file"
```

The entire block `{ ... }` is a **group command** — multiple commands whose combined stdout is redirected into `$catalog_file` with a single `>`. This is cleaner than opening, writing, and closing the file manually.

`stat -c '%y'` prints the last modification time in the format `YYYY-MM-DD HH:MM:SS.nanoseconds +timezone`. `cut -d'.' -f1` splits on the dot and keeps only the first field, removing sub-second precision. `${mtime:-unknown}` is a **default-value substitution** — if `mtime` is empty or unset, the string `unknown` is used instead.

---

## 3. PowerShell Script — `datacenter_tool.ps1`

### 3.1 Global Setup

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
```

`#Requires -Version 5.1` is a special comment PowerShell reads before executing the script. If the running PowerShell version is older than 5.1, the script refuses to start and displays a clear error message.

`Set-StrictMode -Version Latest` turns on strict variable checking — it raises an error if you reference an undefined variable or call a method on a null object, catching bugs early.

`$ErrorActionPreference = 'Stop'` changes the default behaviour for non-terminating errors from silently continuing to immediately throwing an exception. This makes `try/catch` blocks work reliably for cmdlets that would otherwise just write to the error stream and keep running.

---

### 3.2 Main Loop

```powershell
while ($true) {
    $choice = Show-Menu

    switch ($choice.Trim()) {
        "1" { Get-UsersAndLogins     }
        "2" { Get-FilesystemInfo     }
        ...
        "0" { exit 0 }
        default { Write-Host "Invalid option..." -ForegroundColor Yellow }
    }

    Wait-ForEnter
}
```

`while ($true)` is PowerShell's infinite loop. `$choice.Trim()` strips leading/trailing whitespace from the user's input — important because `Read-Host` sometimes captures a trailing space on certain terminal emulators.

`switch` in PowerShell is more powerful than a traditional `if/else` chain: it evaluates each branch in order and executes the first one that matches. The `default` branch is the catch-all equivalent to Bash's `*` pattern.

`Wait-ForEnter` is a small helper function that calls `Read-Host` and discards the result with `| Out-Null`, producing the "Press Enter" pause.

---

### 3.3 Function: `Show-Menu`

```powershell
function Show-Menu {
    Write-Host "..." -ForegroundColor Cyan
    return (Read-Host "Select an option [0-5]")
}
```

PowerShell functions return the last expression evaluated (or an explicit `return` value). Here `Read-Host` both displays the prompt and blocks until the user presses Enter, returning the input string which is passed back to the caller.

`Write-Host` is used (rather than `Write-Output`) because `Write-Host` goes directly to the console host and bypasses PowerShell's output pipeline — this prevents menu text from accidentally being captured if the function were ever called in a pipeline.

---

### 3.4 Function: `Get-UsersAndLogins`

```powershell
try {
    $users = Get-LocalUser -ErrorAction Stop
}
catch {
    Write-Host "Error: Could not retrieve local users." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    return
}
```

`Get-LocalUser` is a cmdlet from the `Microsoft.PowerShell.LocalAccounts` module, available since PowerShell 5.1. It queries the SAM (Security Account Manager) database for all local user accounts.

`-ErrorAction Stop` overrides the cmdlet-level error handling to throw a terminating exception if it fails (e.g., insufficient permissions). The `catch` block captures that exception — `$_` is the automatic variable containing the current error object, and `.Exception.Message` is the human-readable description.

```powershell
$lastLogon = if ($user.LastLogon) {
    $user.LastLogon.ToString("yyyy-MM-dd HH:mm:ss")
} else {
    "Never / Unknown"
}
```

`$user.LastLogon` is a `DateTime?` (nullable DateTime). In PowerShell, a null value is falsy in a boolean context. The inline `if` expression evaluates to the formatted date string if a logon time is recorded, or the fallback string otherwise. `.ToString("yyyy-MM-dd HH:mm:ss")` formats the `DateTime` object using a standard ISO-like pattern.

```powershell
$fmt = "{0,-25} {1,-10} {2,-22} {3}"
Write-Host ($fmt -f $user.Name, $enabled, $lastLogon, $desc)
```

The `-f` operator is PowerShell's **format operator** (equivalent to C#'s `string.Format`). `{0,-25}` means: positional argument 0, left-aligned (`-`), padded to 25 characters wide.

---

### 3.5 Function: `Get-FilesystemInfo`

```powershell
$drives = Get-PSDrive -PSProvider FileSystem -ErrorAction Stop |
          Where-Object { $_.Root -ne "" }
```

`Get-PSDrive` returns all PowerShell drives — this includes not just disk drives (`C:\`, `D:\`) but also virtual drives for the registry (`HKLM:\`), environment variables (`Env:\`), and aliases (`Alias:\`). `-PSProvider FileSystem` restricts results to drives backed by the filesystem provider only.

`Where-Object { $_.Root -ne "" }` filters out any filesystem drives that have no root path (which can occur with network-mapped drives in a disconnected state).

```powershell
$total = if ($null -ne $drive.Used -and $null -ne $drive.Free) {
    $drive.Used + $drive.Free
} else { "N/A" }
```

`Get-PSDrive` exposes `Used` and `Free` properties already in bytes. Some drives (CD-ROMs with no disc, disconnected network paths) return `$null` for these values. The explicit `$null -ne` check is required because with `Set-StrictMode` active, arithmetic on a null value throws an error.

---

### 3.6 Function: `Get-Top10LargestFiles`

```powershell
if (-not (Test-Path -LiteralPath $searchPath -PathType Container)) {
    Write-Host "Error: '$searchPath' is not a valid directory." -ForegroundColor Red
    return
}
```

`Test-Path -LiteralPath` validates existence of the path. `-LiteralPath` (as opposed to `-Path`) treats the string literally without interpreting glob characters like `*` or `?`. `-PathType Container` ensures the path points to a directory (container), not a file (leaf).

```powershell
$files = Get-ChildItem -LiteralPath $searchPath -Recurse -File `
             -ErrorAction SilentlyContinue |
         Sort-Object -Property Length -Descending |
         Select-Object -First 10
```

This is a **PowerShell pipeline**, analogous to the Bash pipeline in option 3:

| Stage | Cmdlet | Purpose |
|---|---|---|
| 1 | `Get-ChildItem -Recurse -File` | Recursively enumerates all files (not directories) under the path |
| 2 | `Sort-Object -Property Length -Descending` | Sorts the file objects by their `Length` property (size in bytes), largest first |
| 3 | `Select-Object -First 10` | Takes only the first 10 objects from the sorted stream |

`-ErrorAction SilentlyContinue` causes access-denied errors to be silently skipped rather than displayed or thrown — identical in purpose to `2>/dev/null` in the Bash version.

---

### 3.7 Function: `Get-MemoryAndSwapUsage`

```powershell
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
```

`Get-CimInstance` queries **WMI (Windows Management Instrumentation)** via the modern CIM (Common Information Model) protocol. `Win32_OperatingSystem` is a WMI class that exposes operating system properties including memory statistics. The relevant properties are:

| WMI Property | Unit | Meaning |
|---|---|---|
| `TotalVisibleMemorySize` | KB | Total physical RAM available to the OS |
| `FreePhysicalMemory` | KB | Currently unused physical RAM |

```powershell
$totalRamBytes = [long]$os.TotalVisibleMemorySize * 1KB
```

WMI returns these values as 32-bit integers in kilobytes. `[long]` casts the value to a 64-bit integer **before** multiplication to prevent integer overflow on systems with more than 2 GB of RAM (a 32-bit int maxes out at ~2.1 billion, but 2 GB in bytes is ~2.1 billion — very close to overflow). `1KB` is a PowerShell numeric multiplier constant equal to 1024.

```powershell
$pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop
```

`Win32_PageFileUsage` is a separate WMI class for page file statistics. It returns one object per page file (most systems have one). Its properties:

| WMI Property | Unit | Meaning |
|---|---|---|
| `AllocatedBaseSize` | MB | Total size of the page file |
| `CurrentUsage` | MB | How much of the page file is currently in use |
| `Name` | — | Full path to the page file (e.g. `C:\pagefile.sys`) |

The page file query is in its own nested `try/catch` block because it requires Administrator rights. If it fails, a yellow warning is shown but the RAM section (which already displayed) is not affected — this is **graceful degradation**.

---

### 3.8 Function: `Backup-ToUSB`

#### Drive validation

```powershell
$driveLetter = Split-Path -Qualifier $usbPath
if (-not (Test-Path -LiteralPath "$driveLetter\")) {
    Write-Host "Error: Drive '$driveLetter' is not available." -ForegroundColor Red
    return
}
```

`Split-Path -Qualifier` extracts the drive portion of a Windows path (e.g. `E:` from `E:\Backup`). Testing `"$driveLetter\"` (with the trailing backslash) confirms that the drive root itself is accessible — just checking the drive letter is not enough because a drive can exist in the registry but be disconnected.

#### Directory creation

```powershell
if (-not (Test-Path -LiteralPath $usbPath)) {
    New-Item -Path $usbPath -ItemType Directory -Force | Out-Null
}
```

`New-Item -ItemType Directory -Force` creates the directory and all intermediate parent directories if they do not exist (equivalent to `mkdir -p` on Linux). `| Out-Null` discards the `DirectoryInfo` object that `New-Item` returns so it does not print to the console.

#### Free space check

```powershell
$srcSizeB = (Get-ChildItem -LiteralPath $sourceDir -Recurse -File `
                 -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
```

`Measure-Object -Property Length -Sum` walks all file objects from `Get-ChildItem` and accumulates their `Length` values. The result is a `MeasureInfo` object; `.Sum` extracts the numeric total in bytes. This is the PowerShell equivalent of `du -sb`.

#### File copy

```powershell
Copy-Item -LiteralPath $sourceDir -Destination $usbPath `
          -Recurse -Force -ErrorAction Stop
```

`Copy-Item -Recurse` copies the entire directory tree. `-Force` overwrites existing files at the destination without prompting. `-LiteralPath` prevents glob expansion so paths with brackets or other special characters are handled safely.

#### Catalog generation

```powershell
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("BACKUP CATALOG")
...
Get-ChildItem -LiteralPath $sourceDir -Recurse -File |
    Sort-Object -Property Name |
    ForEach-Object {
        $lines.Add(("{0,-60} {1}" -f $_.Name, $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")))
    }

$lines | Out-File -FilePath $catalogPath -Encoding UTF8
```

A `List<string>` (from .NET's `System.Collections.Generic` namespace) is used instead of a PowerShell array (`@()`) because appending to a `List<T>` with `.Add()` is O(1), whereas the `+=` operator on a PowerShell array is O(n) — it copies the entire array each time. For directories with many files this makes a measurable difference.

`$_.LastWriteTime` is a `DateTime` property on every `FileInfo` object returned by `Get-ChildItem`. It corresponds to the file's last modification time — the same data `stat -c '%y'` returns on Linux.

`Out-File -Encoding UTF8` writes the catalog with UTF-8 encoding, ensuring that filenames with international characters are preserved correctly.

The catalog is built by walking the **source** directory (not the destination) — this is intentional to avoid the catalog listing itself, which would happen if we walked the destination after copying.

---

## 4. Side-by-Side Comparison

| Aspect | Bash (`datacenter_tool.sh`) | PowerShell (`datacenter_tool.ps1`) |
|---|---|---|
| **Language paradigm** | Procedural shell scripting; tools composed via pipes | Object-oriented pipeline; cmdlets pass typed objects |
| **Data model** | Everything is text; parsing is manual with `awk`, `cut`, `grep` | Cmdlets return .NET objects with typed properties (`Length`, `LastWriteTime`) |
| **User data source** | `getent passwd` — reads NSS (covers LDAP, NIS, local) | `Get-LocalUser` — queries SAM (local accounts only) |
| **Last login source** | `lastlog` — reads `/var/log/lastlog` binary database | `$user.LastLogon` property from the `Get-LocalUser` object |
| **Disk information** | `df -B1` — reports sizes in bytes directly | `Get-PSDrive` — `Used` and `Free` already in bytes |
| **File search** | `find -printf "%s\t%p\n" \| sort -rn \| head -10` | `Get-ChildItem \| Sort-Object Length -Descending \| Select-Object -First 10` |
| **Memory data source** | `/proc/meminfo` virtual file (kernel exposes it) | `Win32_OperatingSystem` WMI class |
| **Swap data source** | `/proc/meminfo` — `SwapTotal` / `SwapFree` keys | `Win32_PageFileUsage` WMI class |
| **Unit conversion** | Manual: `$(( value_kb * 1024 ))` | `[long]$value * 1KB` using PowerShell multiplier |
| **Float arithmetic** | Delegated to `awk` (Bash has no native floats) | `[math]::Round(...)` using .NET Math class |
| **File copy** | `cp -a` — archive mode, preserves all metadata | `Copy-Item -Recurse -Force` |
| **Catalog timestamps** | `stat -c '%y' file \| cut -d'.' -f1` | `$file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")` |
| **Error handling** | `if/else` on command exit codes; `2>/dev/null` to suppress stderr | `try/catch` blocks; `-ErrorAction Stop/SilentlyContinue` |
| **Colour output** | ANSI escape codes (`\033[0;31m`) via `echo -e` | `-ForegroundColor` parameter on `Write-Host` |
| **Privilege requirement** | `sudo` / root for full access | Run as Administrator |
