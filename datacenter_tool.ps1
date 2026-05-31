# ============================================================
# datacenter_tool.ps1 — Sysadmin Tool for Data Center (Windows)
# Compatible with Windows 10 / 11
# Run as Administrator for full access to all features.
# ============================================================

# Require at least PowerShell 5.1
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- Helper: pause and wait for Enter ----------------------
function Wait-ForEnter {
    Write-Host ""
    Read-Host "Press Enter to return to the menu" | Out-Null
}

# ---- Display menu ------------------------------------------
function Show-Menu {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor White
    Write-Host "    DATA CENTER ADMINISTRATION TOOL         " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor White
    Write-Host " 1. System Users & Last Login"
    Write-Host " 2. Connected Filesystems / Disks"
    Write-Host " 3. Top 10 Largest Files"
    Write-Host " 4. Memory & Swap Usage"
    Write-Host " 5. Backup Directory to USB"
    Write-Host " 0. Exit"
    Write-Host "============================================" -ForegroundColor White
    return (Read-Host "Select an option [0-5]")
}

# ============================================================
# Option 1 — System Users & Last Login
# Uses Get-LocalUser (requires Administrator for full details).
# LastLogon is populated only for local accounts; domain
# accounts managed by AD will show an empty value.
# ============================================================
function Get-UsersAndLogins {
    Write-Host ""
    Write-Host "=== System Users & Last Login ===" -ForegroundColor Cyan
    Write-Host ""

    try {
        $users = Get-LocalUser -ErrorAction Stop
    }
    catch {
        Write-Host "Error: Could not retrieve local users. Run as Administrator." `
                   -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return
    }

    $fmt = "{0,-25} {1,-10} {2,-22} {3}"
    Write-Host ($fmt -f "USERNAME", "ENABLED", "LAST LOGON", "DESCRIPTION") `
               -ForegroundColor White
    Write-Host ($fmt -f "--------", "-------", "----------", "-----------")

    foreach ($user in $users) {
        $lastLogon = if ($user.LastLogon) {
            $user.LastLogon.ToString("yyyy-MM-dd HH:mm:ss")
        } else {
            "Never / Unknown"
        }

        $enabled = if ($user.Enabled) { "Yes" } else { "No" }
        $desc    = if ($user.Description) { $user.Description } else { "-" }

        Write-Host ($fmt -f $user.Name, $enabled, $lastLogon, $desc)
    }

    Write-Host ""
}

# ============================================================
# Option 2 — Connected Filesystems / Disks
# Get-PSDrive -PSProvider FileSystem returns all drives that
# PowerShell can see.  Used + Free are already in bytes.
# ============================================================
function Get-FilesystemInfo {
    Write-Host ""
    Write-Host "=== Connected Filesystems / Disks ===" -ForegroundColor Cyan
    Write-Host ""

    try {
        # Filter out drives without a Root (e.g. registry hives)
        $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction Stop |
                  Where-Object { $_.Root -ne "" }
    }
    catch {
        Write-Host "Error: Could not retrieve drive information." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return
    }

    if (-not $drives) {
        Write-Host "No filesystems found." -ForegroundColor Yellow
        return
    }

    $fmt = "{0,-10} {1,-22} {2,-22} {3}"
    Write-Host ($fmt -f "DRIVE", "TOTAL (bytes)", "FREE (bytes)", "LABEL / DESCRIPTION") `
               -ForegroundColor White
    Write-Host ($fmt -f "-----", "-------------", "------------", "--------------------")

    foreach ($drive in $drives) {
        $total = if ($null -ne $drive.Used -and $null -ne $drive.Free) {
            $drive.Used + $drive.Free
        } else { "N/A" }

        $free  = if ($null -ne $drive.Free) { $drive.Free } else { "N/A" }
        $label = if ($drive.Description)    { $drive.Description } else { "-" }

        Write-Host ($fmt -f $drive.Root, $total, $free, $label)
    }

    Write-Host ""
}

# ============================================================
# Option 3 — Top 10 Largest Files
# Recursively searches a user-supplied path with
# Get-ChildItem.  Access-denied entries are silently skipped.
# ============================================================
function Get-Top10LargestFiles {
    Write-Host ""
    Write-Host "=== Top 10 Largest Files ===" -ForegroundColor Cyan
    Write-Host ""

    $searchPath = Read-Host "Enter the directory path to search"

    if ([string]::IsNullOrWhiteSpace($searchPath)) {
        Write-Host "Error: No path entered." -ForegroundColor Red
        return
    }

    if (-not (Test-Path -LiteralPath $searchPath -PathType Container)) {
        Write-Host "Error: '$searchPath' is not a valid directory." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Searching '$searchPath' (access-denied items are skipped)..."
    Write-Host ""

    try {
        $files = Get-ChildItem -LiteralPath $searchPath -Recurse -File `
                     -ErrorAction SilentlyContinue |
                 Sort-Object -Property Length -Descending |
                 Select-Object -First 10

        if (-not $files) {
            Write-Host "No files found in '$searchPath'." -ForegroundColor Yellow
            return
        }

        $fmt = "{0,-22} {1}"
        Write-Host ($fmt -f "SIZE (bytes)", "FILE PATH") -ForegroundColor White
        Write-Host ($fmt -f "------------", "---------")

        foreach ($file in $files) {
            Write-Host ($fmt -f $file.Length, $file.FullName)
        }
    }
    catch {
        Write-Host "Error while searching directory: $($_.Exception.Message)" `
                   -ForegroundColor Red
    }

    Write-Host ""
}

# ============================================================
# Option 4 — Memory & Swap (Page File) Usage
# Win32_OperatingSystem gives physical RAM in KB.
# Win32_PageFileUsage gives page-file totals in MB; we
# convert everything to bytes for consistency.
# ============================================================
function Get-MemoryAndSwapUsage {
    Write-Host ""
    Write-Host "=== Memory & Swap Usage ===" -ForegroundColor Cyan
    Write-Host ""

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    }
    catch {
        Write-Host "Error: Could not query Win32_OperatingSystem." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        return
    }

    # Win32_OperatingSystem values are in KB — multiply by 1024 for bytes
    $totalRamBytes = [long]$os.TotalVisibleMemorySize * 1KB
    $freeRamBytes  = [long]$os.FreePhysicalMemory     * 1KB

    $freeRamPct = if ($totalRamBytes -gt 0) {
        [math]::Round(($freeRamBytes / $totalRamBytes) * 100, 2)
    } else { 0 }

    Write-Host "--- RAM ---" -ForegroundColor White
    Write-Host ("  Total RAM      : {0,20} bytes" -f $totalRamBytes)
    Write-Host ("  Available RAM  : {0,20} bytes  ({1}% free)" -f $freeRamBytes, $freeRamPct)
    Write-Host ""

    # Page file (swap) — Win32_PageFileUsage values are in MB
    Write-Host "--- Page File (Swap) ---" -ForegroundColor White

    try {
        $pageFiles = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop

        if (-not $pageFiles) {
            Write-Host "  No page file configured on this system."
        }
        else {
            foreach ($pf in $pageFiles) {
                $totalSwapBytes = [long]$pf.AllocatedBaseSize * 1MB
                $usedSwapBytes  = [long]$pf.CurrentUsage      * 1MB

                $usedSwapPct = if ($totalSwapBytes -gt 0) {
                    [math]::Round(($usedSwapBytes / $totalSwapBytes) * 100, 2)
                } else { 0 }

                Write-Host ("  File           : {0}" -f $pf.Name)
                Write-Host ("  Total Size     : {0,20} bytes" -f $totalSwapBytes)
                Write-Host ("  In Use         : {0,20} bytes  ({1}% used)" `
                            -f $usedSwapBytes, $usedSwapPct)
                Write-Host ""
            }
        }
    }
    catch {
        # Not fatal — display a warning and continue
        Write-Host "  Warning: Could not query page file info (requires Administrator)." `
                   -ForegroundColor Yellow
    }

    Write-Host ""
}

# ============================================================
# Option 5 — Backup Directory to USB
# Copies source → USB destination with Copy-Item -Recurse.
# Creates the destination folder if it doesn't exist, then
# writes catalog.txt listing every file and its last-write
# time into the USB root.
# ============================================================
function Backup-ToUSB {
    Write-Host ""
    Write-Host "=== Backup Directory to USB ===" -ForegroundColor Cyan
    Write-Host ""

    # --- Validate source ----------------------------------------
    $sourceDir = Read-Host "Enter the source directory to back up"

    if ([string]::IsNullOrWhiteSpace($sourceDir)) {
        Write-Host "Error: No source directory entered." -ForegroundColor Red
        return
    }
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
        Write-Host "Error: Source directory '$sourceDir' does not exist." `
                   -ForegroundColor Red
        return
    }

    # --- Validate USB destination -------------------------------
    $usbPath = Read-Host "Enter the USB destination path (e.g. E:\Backup)"

    if ([string]::IsNullOrWhiteSpace($usbPath)) {
        Write-Host "Error: No USB path entered." -ForegroundColor Red
        return
    }

    # Verify the drive letter exists
    $driveLetter = Split-Path -Qualifier $usbPath
    if (-not (Test-Path -LiteralPath "$driveLetter\")) {
        Write-Host "Error: Drive '$driveLetter' is not available." -ForegroundColor Red
        Write-Host "Tip: Use option 2 to list connected drives." -ForegroundColor Yellow
        return
    }

    # Create the destination folder if it does not yet exist
    if (-not (Test-Path -LiteralPath $usbPath)) {
        try {
            New-Item -Path $usbPath -ItemType Directory -Force | Out-Null
            Write-Host "Created destination directory: $usbPath"
        }
        catch {
            Write-Host "Error: Could not create '$usbPath': $($_.Exception.Message)" `
                       -ForegroundColor Red
            return
        }
    }

    # Rough free-space check
    $drive    = Get-PSDrive -PSProvider FileSystem |
                Where-Object { $_.Root -eq "$driveLetter\" } |
                Select-Object -First 1
    $srcSizeB = (Get-ChildItem -LiteralPath $sourceDir -Recurse -File `
                     -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum

    if ($drive -and $drive.Free -and $srcSizeB -and ($srcSizeB -gt $drive.Free)) {
        Write-Host ("Error: Not enough space. Need {0} bytes, USB has {1} bytes free." `
                    -f $srcSizeB, $drive.Free) -ForegroundColor Red
        return
    }

    # --- Copy files ---------------------------------------------
    Write-Host ""
    Write-Host "Copying '$sourceDir' → '$usbPath'  (this may take a while)..."

    try {
        Copy-Item -LiteralPath $sourceDir -Destination $usbPath `
                  -Recurse -Force -ErrorAction Stop
        Write-Host "Files copied successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Error during copy: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # --- Generate catalog.txt -----------------------------------
    $catalogPath = Join-Path -Path $usbPath -ChildPath "catalog.txt"
    Write-Host ""
    Write-Host "Generating '$catalogPath'..."

    try {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("BACKUP CATALOG")
        $lines.Add("==============")
        $lines.Add("Source      : $sourceDir")
        $lines.Add("Destination : $usbPath")
        $lines.Add("Created     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $lines.Add("")
        $lines.Add(("{0,-60} {1}" -f "FILE NAME", "LAST MODIFIED"))
        $lines.Add(("{0,-60} {1}" -f ("-" * 60), ("-" * 19)))

        # Walk source, not destination, to avoid cataloguing the catalog itself
        Get-ChildItem -LiteralPath $sourceDir -Recurse -File `
                -ErrorAction SilentlyContinue |
            Sort-Object -Property Name |
            ForEach-Object {
                $lines.Add(("{0,-60} {1}" -f `
                    $_.Name, `
                    $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")))
            }

        $lines | Out-File -FilePath $catalogPath -Encoding UTF8 -ErrorAction Stop

        Write-Host "Catalog generated successfully." -ForegroundColor Green
        Write-Host ""
        Write-Host "Backup complete!" -ForegroundColor Green
        Write-Host "  Source    : $sourceDir"
        Write-Host "  USB path  : $usbPath"
        Write-Host "  Catalog   : $catalogPath"
    }
    catch {
        Write-Host "Warning: Backup succeeded but catalog could not be written." `
                   -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }

    Write-Host ""
}

# ============================================================
# Main loop — runs until the user selects 0
# ============================================================
while ($true) {
    $choice = Show-Menu

    switch ($choice.Trim()) {
        "1" { Get-UsersAndLogins     }
        "2" { Get-FilesystemInfo     }
        "3" { Get-Top10LargestFiles  }
        "4" { Get-MemoryAndSwapUsage }
        "5" { Backup-ToUSB           }
        "0" {
            Write-Host ""
            Write-Host "Exiting. Goodbye!" -ForegroundColor Green
            exit 0
        }
        default {
            Write-Host ""
            Write-Host "Invalid option '$choice'. Please select 0-5." `
                       -ForegroundColor Yellow
        }
    }

    Wait-ForEnter
}
