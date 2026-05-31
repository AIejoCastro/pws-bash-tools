#!/bin/bash

# ============================================================
# datacenter_tool.sh — Sysadmin Tool for Data Center (Linux)
# Tested on Ubuntu / Debian
# Run as root or with sudo for full access to all features.
# ============================================================

# ---- Colour helpers ----------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'

err()  { echo -e "${RED}Error: $*${RESET}" >&2; }
warn() { echo -e "${YELLOW}Warning: $*${RESET}"; }
info() { echo -e "${CYAN}$*${RESET}"; }

# ---- Display menu ------------------------------------------
show_menu() {
    echo ""
    echo -e "${BOLD}============================================${RESET}"
    echo -e "${BOLD}    DATA CENTER ADMINISTRATION TOOL         ${RESET}"
    echo -e "${BOLD}============================================${RESET}"
    echo " 1. System Users & Last Login"
    echo " 2. Connected Filesystems / Disks"
    echo " 3. Top 10 Largest Files"
    echo " 4. Memory & Swap Usage"
    echo " 5. Backup Directory to USB"
    echo " 0. Exit"
    echo -e "${BOLD}============================================${RESET}"
    echo -n "Select an option [0-5]: "
}

# ============================================================
# Option 1 — System Users & Last Login
# Lists users with a real login shell and shows each user's
# last login from the lastlog database.
# ============================================================
list_users_and_logins() {
    echo ""
    info "=== System Users & Last Login ==="
    echo ""

    # Require lastlog (part of the 'login' package on Debian/Ubuntu)
    if ! command -v lastlog &>/dev/null; then
        err "'lastlog' is not installed. Install it with: sudo apt install login"
        return
    fi

    printf "${BOLD}%-22s %-6s %-10s %s${RESET}\n" "USERNAME" "UID" "ENABLED" "LAST LOGIN"
    printf "%-22s %-6s %-10s %s\n"                 "--------" "---" "-------" "----------"

    while IFS=: read -r username _ uid _ _ _ shell; do
        # Include root (uid 0) and normal users (uid >= 1000).
        # Skip accounts whose shell marks them as non-interactive.
        if [[ "$uid" -eq 0 || "$uid" -ge 1000 ]] && \
           [[ "$shell" != */nologin && "$shell" != */false && "$shell" != */sync ]]; then

            # Determine if the account is locked (passwd -S) — graceful fallback
            status="Yes"
            if passwd -S "$username" &>/dev/null; then
                lock_flag=$(passwd -S "$username" 2>/dev/null | awk '{print $2}')
                [[ "$lock_flag" == "L" ]] && status="No (locked)"
            fi

            # lastlog -u <user> emits a header line + one data line
            lastlog_line=$(lastlog -u "$username" 2>/dev/null | tail -1)

            if echo "$lastlog_line" | grep -q "Never logged in"; then
                last_login="Never logged in"
            else
                # The date occupies the last five tokens: Dow Mon DD HH:MM:SS YYYY
                last_login=$(echo "$lastlog_line" | awk '{
                    n = NF
                    if (n >= 5) printf "%s %s %s %s %s", $(n-4), $(n-3), $(n-2), $(n-1), $n
                    else        print "Unknown"
                }')
                [[ -z "$last_login" ]] && last_login="Never logged in"
            fi

            printf "%-22s %-6s %-10s %s\n" "$username" "$uid" "$status" "$last_login"
        fi
    done < <(getent passwd)

    echo ""
}

# ============================================================
# Option 2 — Connected Filesystems / Disks
# Uses df -B1 to report sizes in bytes.
# Skips virtual/pseudo filesystems for readability.
# ============================================================
list_filesystems() {
    echo ""
    info "=== Connected Filesystems / Disks ==="
    echo ""

    printf "${BOLD}%-35s %-18s %-18s %s${RESET}\n" "DEVICE" "TOTAL (bytes)" "FREE (bytes)" "MOUNT POINT"
    printf "%-35s %-18s %-18s %s\n"                 "------" "-------------" "------------" "-----------"

    # -B1 → byte units; --output selects columns; skip header with tail -n +2
    df -B1 --output=source,size,avail,target 2>/dev/null | tail -n +2 | \
    while read -r source size avail target; do
        # Keep only block devices and network/FUSE mounts; drop pseudo filesystems
        case "$source" in
            tmpfs|devtmpfs|udev|sysfs|proc|cgroup|cgroup2|pstore| \
            devpts|hugetlbfs|mqueue|debugfs|tracefs|securityfs|configfs| \
            fusectl|binfmt_misc|overlay|none|nsfs|sunrpc)
                continue ;;
        esac
        # Also skip squashfs snap loop mounts (noisy on Ubuntu Desktop)
        [[ "$source" == /dev/loop* ]] && continue

        printf "%-35s %-18s %-18s %s\n" "$source" "$size" "$avail" "$target"
    done

    echo ""
}

# ============================================================
# Option 3 — Top 10 Largest Files
# Prompts for a path, then uses 'find' with -printf to get
# file sizes in bytes without shelling out to stat per file.
# ============================================================
top_10_largest_files() {
    echo ""
    info "=== Top 10 Largest Files ==="
    echo ""
    echo -n "Enter the directory path to search: "
    read -r search_path

    if [[ -z "$search_path" ]]; then
        err "No path entered."
        return
    fi

    if [[ ! -d "$search_path" ]]; then
        err "'$search_path' is not a valid directory."
        return
    fi

    echo ""
    echo "Searching in '$search_path' (permission errors are silently skipped)..."
    echo ""

    printf "${BOLD}%-22s %s${RESET}\n" "SIZE (bytes)" "FILE PATH"
    printf "%-22s %s\n"                "------------" "---------"

    # -printf "%s\t%p\n" writes "<size><tab><path>" for every regular file.
    # sort -rn sorts numerically descending; head -10 keeps the ten biggest.
    find "$search_path" -type f -printf "%s\t%p\n" 2>/dev/null \
        | sort -rn \
        | head -10 \
        | while IFS=$'\t' read -r size filepath; do
              printf "%-22s %s\n" "$size" "$filepath"
          done

    echo ""
}

# ============================================================
# Option 4 — Memory & Swap Usage
# Reads /proc/meminfo directly (always available, no extra
# tools needed). All values converted from kB to bytes.
# ============================================================
show_memory_usage() {
    echo ""
    info "=== Memory & Swap Usage ==="
    echo ""

    if [[ ! -r /proc/meminfo ]]; then
        err "/proc/meminfo is not readable."
        return
    fi

    # Read the relevant lines (values are in kB)
    total_mem_kb=$(awk '/^MemTotal:/    {print $2}' /proc/meminfo)
    free_mem_kb=$(awk  '/^MemAvailable:/{print $2}' /proc/meminfo)  # "available" is more useful than "free"
    total_swap_kb=$(awk '/^SwapTotal:/  {print $2}' /proc/meminfo)
    free_swap_kb=$(awk  '/^SwapFree:/   {print $2}' /proc/meminfo)

    # Convert to bytes
    total_mem_bytes=$(( total_mem_kb   * 1024 ))
    free_mem_bytes=$(( free_mem_kb     * 1024 ))
    total_swap_bytes=$(( total_swap_kb * 1024 ))
    used_swap_bytes=$(( (total_swap_kb - free_swap_kb) * 1024 ))

    # Percentages (guard against division by zero with awk)
    free_mem_pct=$(awk -v f="$free_mem_bytes" -v t="$total_mem_bytes" \
        'BEGIN { if (t>0) printf "%.2f", (f/t)*100; else print "N/A" }')

    if [[ "$total_swap_bytes" -gt 0 ]]; then
        used_swap_pct=$(awk -v u="$used_swap_bytes" -v t="$total_swap_bytes" \
            'BEGIN { printf "%.2f", (u/t)*100 }')
    else
        used_swap_pct="N/A"
    fi

    echo -e "${BOLD}--- RAM ---${RESET}"
    printf "  Total RAM      : %s bytes\n"            "$total_mem_bytes"
    printf "  Available RAM  : %s bytes  (%s%% free)\n" "$free_mem_bytes" "$free_mem_pct"
    echo ""
    echo -e "${BOLD}--- Swap ---${RESET}"
    printf "  Total Swap     : %s bytes\n"            "$total_swap_bytes"

    if [[ "$total_swap_bytes" -gt 0 ]]; then
        printf "  Swap In Use    : %s bytes  (%s%% used)\n" "$used_swap_bytes" "$used_swap_pct"
    else
        echo "  (No swap space configured on this system)"
    fi

    echo ""
}

# ============================================================
# Option 5 — Backup Directory to USB
# Copies source → USB with cp -a (preserves attributes).
# Generates catalog.txt at the USB root listing every file
# and its last-modification timestamp.
# ============================================================
backup_to_usb() {
    echo ""
    info "=== Backup Directory to USB ==="
    echo ""

    # --- Collect and validate source ---
    echo -n "Enter the source directory to back up: "
    read -r source_dir

    if [[ -z "$source_dir" ]]; then
        err "No source directory entered."
        return
    fi
    if [[ ! -d "$source_dir" ]]; then
        err "Source directory '$source_dir' does not exist."
        return
    fi

    # --- Collect and validate USB mount point ---
    echo -n "Enter the USB mount path (e.g. /media/user/USBDRIVE): "
    read -r usb_path

    if [[ -z "$usb_path" ]]; then
        err "No USB mount path entered."
        return
    fi
    if [[ ! -d "$usb_path" ]]; then
        err "Path '$usb_path' does not exist or is not mounted."
        warn "Use option 2 to list mounted filesystems, or 'lsblk' to list block devices."
        return
    fi

    # Warn if the path is not an actual mount point (might still be valid)
    if ! mountpoint -q "$usb_path" 2>/dev/null; then
        warn "'$usb_path' does not appear to be a mount point."
        echo -n "Continue anyway? [y/N]: "
        read -r confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Backup cancelled."; return; }
    fi

    # Check there is space on the USB (rough check)
    src_size=$(du -sb "$source_dir" 2>/dev/null | awk '{print $1}')
    usb_free=$(df -B1 --output=avail "$usb_path" 2>/dev/null | tail -1 | xargs)
    if [[ -n "$src_size" && -n "$usb_free" && "$src_size" -gt "$usb_free" ]]; then
        err "Not enough free space on USB. Need $src_size bytes, have $usb_free bytes."
        return
    fi

    echo ""
    echo "Copying '$source_dir' → '$usb_path'  (this may take a while)..."

    # -a = archive mode (recursive + preserves timestamps, permissions, symlinks)
    if cp -a "$source_dir/." "$usb_path/" 2>/tmp/cp_err; then
        echo -e "${GREEN}Files copied successfully.${RESET}"
    else
        err "Copy failed: $(cat /tmp/cp_err)"
        return
    fi

    # --- Generate catalog.txt ---
    catalog_file="$usb_path/catalog.txt"
    echo ""
    echo "Generating '$catalog_file'..."

    {
        echo "BACKUP CATALOG"
        echo "=============="
        printf "Source      : %s\n" "$source_dir"
        printf "Destination : %s\n" "$usb_path"
        printf "Created     : %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        printf "%-60s %s\n" "FILE NAME" "LAST MODIFIED"
        printf "%-60s %s\n" "---------" "-------------"
        # stat -c '%y' gives the modification time; cut removes sub-second precision
        find "$source_dir" -type f | sort | while read -r filepath; do
            fname=$(basename "$filepath")
            mtime=$(stat -c '%y' "$filepath" 2>/dev/null | cut -d'.' -f1)
            printf "%-60s %s\n" "$fname" "${mtime:-unknown}"
        done
    } > "$catalog_file"

    if [[ -f "$catalog_file" ]]; then
        echo -e "${GREEN}Catalog generated successfully.${RESET}"
        echo ""
        echo -e "${GREEN}Backup complete!${RESET}"
        echo "  Source    : $source_dir"
        echo "  USB path  : $usb_path"
        echo "  Catalog   : $catalog_file"
    else
        warn "Backup completed but catalog.txt could not be created."
    fi

    echo ""
}

# ============================================================
# Main loop — runs until the user chooses option 0
# ============================================================
main() {
    while true; do
        show_menu
        read -r choice

        case "$choice" in
            1) list_users_and_logins  ;;
            2) list_filesystems       ;;
            3) top_10_largest_files   ;;
            4) show_memory_usage      ;;
            5) backup_to_usb          ;;
            0)
                echo ""
                echo -e "${GREEN}Exiting. Goodbye!${RESET}"
                exit 0
                ;;
            *)
                echo ""
                warn "Invalid option '$choice'. Please select 0–5."
                ;;
        esac

        echo ""
        echo -n "Press Enter to return to the menu..."
        read -r
    done
}

main
