#!/bin/bash
# ==============================================================================
# Script Name   : deep_clean_acunetix.sh
# Description   : Complete Deep Clean & Uninstallation Script for Acunetix (Linux)
# Compatibility : Acunetix v13, v14, v15, v23.x, v24.x (Ubuntu/Debian/Kali/CentOS/RHEL)
# ==============================================================================

set -uo pipefail

# ---------------- Colors for Output ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_PID=$$
SCRIPT_NAME="$(basename "$0")"

# ---------------- Banner ----------------
print_banner() {
    clear 2>/dev/null || true
    echo -e "${RED}${BOLD}"
    echo "======================================================================"
    echo "            ACUNETIX DEEP CLEAN & UNINSTALLATION TOOL                 "
    echo "======================================================================"
    echo -e "${NC}"
    echo -e "${CYAN}This script will completely purge and remove:${NC}"
    echo "  - Acunetix Services & Daemons"
    echo "  - Running Processes (scanner, wvsc, node, backend services)"
    echo "  - Systemd Service Files & Init Scripts"
    echo "  - Immutable File Attributes (chattr flags on license/data files)"
    echo "  - Acunetix User & Group accounts"
    echo "  - All Data, Logs, Licenses, and Installation Directories"
    echo "  - Temporary files, locks, sockets, and cache"
    echo "  - Telemetry blocking entries in /etc/hosts (optional/automatic)"
    echo "  - Extracted installation folders & downloaded archives"
    echo -e "${RED}${BOLD}======================================================================${NC}\n"
}

# ---------------- Privilege Check ----------------
check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}[!] Error: This script must be run as root or with sudo privileges.${NC}"
        echo -e "    Please run: ${YELLOW}sudo bash $0${NC}\n"
        exit 1
    fi
}

# ---------------- Parse Arguments & Confirmation ----------------
FORCE=0
for arg in "$@"; do
    case $arg in
        -y|--yes|-f|--force)
            FORCE=1
            shift
            ;;
        -h|--help)
            echo "Usage: sudo bash deep_clean_acunetix.sh [OPTIONS]"
            echo "Options:"
            echo "  -y, --yes, -f, --force    Run non-interactively without confirmation prompts"
            echo "  -h, --help                Show this help message"
            exit 0
            ;;
    esac
done

confirm_cleanup() {
    if [ "$FORCE" -eq 1 ]; then
        return 0
    fi

    echo -e "${YELLOW}[?] WARNING: This will permanently delete all Acunetix configurations,"
    echo -e "    scan data, license files, and associated users.${NC}"
    read -rp "Are you sure you want to proceed with Deep Clean? [y/N]: " confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            echo ""
            ;;
        *)
            echo -e "${BLUE}[*] Deep clean cancelled by user. Exiting.${NC}"
            exit 0
            ;;
    esac
}

# ---------------- Step 1: Stop and Disable Services ----------------
stop_services() {
    echo -e "${BLUE}[1/10] Stopping and disabling Acunetix system services...${NC}"
    
    SERVICES=("acunetix" "acunetix_trial" "acunetix.service" "acunetix_trial.service")
    for s in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$s" 2>/dev/null || systemctl is-enabled --quiet "$s" 2>/dev/null; then
            echo -e "  ${YELLOW}--> Stopping service: $s${NC}"
            systemctl stop "$s" 2>/dev/null || true
            echo -e "  ${YELLOW}--> Disabling service: $s${NC}"
            systemctl disable "$s" 2>/dev/null || true
        fi
    done

    # Check init.d service
    if [ -f /etc/init.d/acunetix ]; then
        echo -e "  ${YELLOW}--> Stopping /etc/init.d/acunetix...${NC}"
        /etc/init.d/acunetix stop 2>/dev/null || true
    fi
    echo -e "${GREEN}[+] Services stopped and disabled successfully.${NC}"
}

# ---------------- Step 2: Kill Lingering Processes (Self-Excluding) ----------------
kill_processes() {
    echo -e "${BLUE}[2/10] Terminating all lingering Acunetix processes...${NC}"
    
    # 1. Kill all processes owned by the 'acunetix' user
    if id "acunetix" &>/dev/null; then
        echo -e "  ${YELLOW}--> Terminating processes under 'acunetix' user...${NC}"
        pkill -u acunetix -9 2>/dev/null || true
    fi

    # 2. Terminate exact scanner binary names
    EXACT_BINARIES=("wvsc" "wvs_console" "scanning_app")
    for bin in "${EXACT_BINARIES[@]}"; do
        killall -9 "$bin" 2>/dev/null || true
    done

    # 3. Terminate pattern-matched processes, safely excluding our own script & parent process
    PATTERNS=(
        "/home/acunetix"
        "/opt/acunetix"
        "acunetix_trial"
        "acunetix/bin"
        "acunetix/wvs"
    )

    for pattern in "${PATTERNS[@]}"; do
        PIDS=$(pgrep -f "$pattern" 2>/dev/null || true)
        for pid in $PIDS; do
            if [ "$pid" -eq "$SCRIPT_PID" ] || [ "$pid" -eq "$PPID" ] || [ "$pid" -eq "${BASHPID:-$$}" ]; then
                continue
            fi
            
            if [ -f "/proc/$pid/cmdline" ]; then
                cmd=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || true)
                # Exclude this script or any clean script
                if echo "$cmd" | grep -qE "($SCRIPT_NAME|deep_clean)"; then
                    continue
                fi
                echo -e "  ${YELLOW}--> Killing process PID $pid ($pattern)${NC}"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    done

    # 4. Also scan for any process whose executable path is in /home/acunetix or /opt/acunetix
    if [ -d "/proc" ]; then
        for exe in /proc/[0-9]*/exe; do
            [ -L "$exe" ] || continue
            pid=$(basename "$(dirname "$exe")")
            if [ -n "$pid" ] && [ "$pid" -ne "$SCRIPT_PID" ] && [ "$pid" -ne "$PPID" ]; then
                target=$(readlink -f "$exe" 2>/dev/null || true)
                if [[ "$target" == /home/acunetix/* || "$target" == /opt/acunetix/* ]]; then
                    echo -e "  ${YELLOW}--> Killing lingering process PID $pid ($target)${NC}"
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
        done
    fi

    sleep 1
    echo -e "${GREEN}[+] All related processes terminated.${NC}"
}

# ---------------- Step 3: Remove Immutable Attributes ----------------
remove_immutable_flags() {
    echo -e "${BLUE}[3/10] Removing file immutable/append attributes (chattr -ia)...${NC}"
    
    # Acunetix patches often set +i / +a attributes on license and binary files
    TARGET_DIRS=(
        "/home/acunetix"
        "/root/.acunetix"
        "/tmp/acunetix*"
        "/tmp/wvs*"
        "/opt/acunetix"
        "/var/log/acunetix"
    )

    for dir in "${TARGET_DIRS[@]}"; do
        if compgen -G "$dir" > /dev/null; then
            echo -e "  ${YELLOW}--> Unlocking files in: $dir${NC}"
            chattr -R -ia $dir 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}[+] Immutable file flags removed.${NC}"
}

# ---------------- Step 4: Remove Systemd Units & Init Scripts ----------------
remove_service_files() {
    echo -e "${BLUE}[4/10] Removing Systemd unit files and init scripts...${NC}"
    
    SYSTEMD_FILES=(
        "/etc/systemd/system/acunetix.service"
        "/etc/systemd/system/acunetix_trial.service"
        "/etc/systemd/system/multi-user.target.wants/acunetix.service"
        "/etc/systemd/system/multi-user.target.wants/acunetix_trial.service"
        "/lib/systemd/system/acunetix.service"
        "/lib/systemd/system/acunetix_trial.service"
        "/usr/lib/systemd/system/acunetix.service"
        "/usr/lib/systemd/system/acunetix_trial.service"
        "/etc/init.d/acunetix"
        "/etc/init.d/acunetix_trial"
    )

    for file in "${SYSTEMD_FILES[@]}"; do
        if [ -e "$file" ] || [ -L "$file" ]; then
            echo -e "  ${YELLOW}--> Removing $file${NC}"
            chattr -ia "$file" 2>/dev/null || true
            rm -f "$file" 2>/dev/null || true
        fi
    done

    echo -e "  ${YELLOW}--> Reloading systemd daemon...${NC}"
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed 2>/dev/null || true

    echo -e "${GREEN}[+] Systemd units and service files removed.${NC}"
}

# ---------------- Step 5: Remove User and Group ----------------
remove_user_and_group() {
    echo -e "${BLUE}[5/10] Removing Acunetix user and group...${NC}"
    
    if id "acunetix" &>/dev/null; then
        echo -e "  ${YELLOW}--> Deleting user 'acunetix'...${NC}"
        userdel -r -f acunetix 2>/dev/null || userdel -f acunetix 2>/dev/null || true
    fi

    if getent group "acunetix" &>/dev/null; then
        echo -e "  ${YELLOW}--> Deleting group 'acunetix'...${NC}"
        groupdel acunetix 2>/dev/null || true
    fi

    echo -e "${GREEN}[+] User and group removed.${NC}"
}

# ---------------- Step 6: Purge Directories & Files ----------------
purge_directories() {
    echo -e "${BLUE}[6/10] Purging all Acunetix installation files and directories...${NC}"
    
    DIRECTORIES=(
        "/home/acunetix"
        "/root/.acunetix"
        "/opt/acunetix"
        "/etc/acunetix"
        "/var/log/acunetix"
        "/var/run/acunetix"
        "/var/lib/acunetix"
        "/usr/share/acunetix"
        "/usr/local/acunetix"
        "/run/acunetix"
    )

    for dir in "${DIRECTORIES[@]}"; do
        if [ -d "$dir" ] || [ -e "$dir" ] || [ -L "$dir" ]; then
            echo -e "  ${YELLOW}--> Deleting directory: $dir${NC}"
            chattr -R -ia "$dir" 2>/dev/null || true
            rm -rf "$dir" 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}[+] Installation directories purged.${NC}"
}

# ---------------- Step 7: Clean Temporary & Cache Files ----------------
clean_temp_files() {
    echo -e "${BLUE}[7/10] Cleaning temporary files, sockets, locks, and cache...${NC}"
    
    TEMP_PATTERNS=(
        "/tmp/acunetix*"
        "/tmp/.acunetix*"
        "/tmp/wvs*"
        "/tmp/wvsc*"
        "/tmp/*acunetix*"
        "/var/tmp/acunetix*"
        "/var/tmp/.acunetix*"
        "/var/tmp/wvs*"
        "/run/lock/*acunetix*"
        "/run/lock/subsys/acunetix"
    )

    for pattern in "${TEMP_PATTERNS[@]}"; do
        for match in $pattern; do
            if [ -e "$match" ]; then
                echo -e "  ${YELLOW}--> Removing temporary artifact: $match${NC}"
                chattr -R -ia "$match" 2>/dev/null || true
                rm -rf "$match" 2>/dev/null || true
            fi
        done
    done

    echo -e "${GREEN}[+] Temporary and cache files cleaned.${NC}"
}

# ---------------- Step 8: Clean /etc/hosts Telemetry Entries ----------------
clean_hosts_file() {
    echo -e "${BLUE}[8/10] Checking and cleaning /etc/hosts telemetry block entries...${NC}"
    
    if [ -f /etc/hosts ]; then
        if grep -qi "acunetix" /etc/hosts; then
            echo -e "  ${YELLOW}--> Backing up /etc/hosts to /etc/hosts.bak.${NC}"
            cp /etc/hosts /etc/hosts.bak."$(date +%s)"
            
            echo -e "  ${YELLOW}--> Removing Acunetix-specific entries from /etc/hosts...${NC}"
            # Remove lines containing acunetix domain names or comments
            sed -i '/acunetix/Id' /etc/hosts
            sed -i '/bxss\.me/Id' /etc/hosts
            echo -e "${GREEN}[+] /etc/hosts cleaned successfully.${NC}"
        else
            echo -e "  ${CYAN}--> No Acunetix entries found in /etc/hosts.${NC}"
        fi
    fi
}

# ---------------- Step 9: Clean Crontabs ----------------
clean_crontabs() {
    echo -e "${BLUE}[9/10] Checking for lingering Acunetix cron jobs...${NC}"
    
    # Check root crontab
    if crontab -l 2>/dev/null | grep -qi "acunetix"; then
        echo -e "  ${YELLOW}--> Removing Acunetix jobs from root crontab...${NC}"
        crontab -l | grep -vi "acunetix" | crontab -
    fi

    # Check cron directories
    CRON_DIRS=("/etc/cron.d" "/etc/cron.daily" "/etc/cron.hourly" "/etc/cron.weekly" "/etc/cron.monthly")
    for cdir in "${CRON_DIRS[@]}"; do
        if [ -d "$cdir" ]; then
            find "$cdir" -maxdepth 1 -iname "*acunetix*" -exec rm -f {} + 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}[+] Crontabs verified and cleaned.${NC}"
}

# ---------------- Step 10: Clean Local Extracted Directories & Archives ----------------
clean_local_artifacts() {
    echo -e "${BLUE}[10/10] Cleaning local extracted installation directories & downloads...${NC}"
    
    CURRENT_DIR="$(pwd)"
    LOCAL_ITEMS=(
        "$CURRENT_DIR/Acunetix-v24.1.240111130-Linux"
        "$CURRENT_DIR"/Acunetix-v*-Linux
        "$CURRENT_DIR"/acunetix_*_x64.sh
        "$CURRENT_DIR/Acunetix-v24.1-Linux.rar"
        "$CURRENT_DIR"/Acunetix-*.rar
        "$CURRENT_DIR"/Acunetix-*.zip
    )

    for item in "${LOCAL_ITEMS[@]}"; do
        for match in $item; do
            if [ -e "$match" ]; then
                echo -e "  ${YELLOW}--> Found local file/folder: $(basename "$match")${NC}"
                if [ "$FORCE" -eq 1 ]; then
                    rm -rf "$match"
                    echo -e "      ${GREEN}[Removed]${NC}"
                else
                    read -rp "    Remove local item '$match'? [y/N]: " del_local
                    case "$del_local" in
                        [yY][eE][sS]|[yY])
                            rm -rf "$match"
                            echo -e "      ${GREEN}[Removed]${NC}"
                            ;;
                        *)
                            echo -e "      ${CYAN}[Skipped]${NC}"
                            ;;
                    esac
                fi
            fi
        done
    done

    echo -e "${GREEN}[+] Local items check completed.${NC}"
}

# ---------------- Verification & Summary ----------------
verify_cleanup() {
    echo ""
    echo -e "${PURPLE}${BOLD}======================================================================${NC}"
    echo -e "${PURPLE}${BOLD}                     CLEANUP VERIFICATION REPORT                      ${NC}"
    echo -e "${PURPLE}${BOLD}======================================================================${NC}"
    
    ERRORS=0

    # 1. Check services
    if systemctl is-active --quiet acunetix 2>/dev/null || systemctl is-active --quiet acunetix_trial 2>/dev/null; then
        echo -e "  [${RED}FAIL${NC}] Acunetix service is still active."
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  [${GREEN}PASS${NC}] Acunetix services: Stopped & Removed"
    fi

    # 2. Check running processes using ps (avoids /proc race conditions & excludes cleanup script)
    LINGERING=0
    if ps -eo pid,args 2>/dev/null | grep -iE "(/home/acunetix|/opt/acunetix|wvsc|scanning_app|acunetix_trial)" | grep -vE "(grep|$SCRIPT_NAME|deep_clean)" >/dev/null 2>&1; then
        LINGERING=1
    fi
    if id "acunetix" &>/dev/null && pgrep -u acunetix >/dev/null 2>&1; then
        LINGERING=1
    fi

    if [ "$LINGERING" -gt 0 ]; then
        echo -e "  [${RED}FAIL${NC}] Lingering Acunetix process(es) detected."
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  [${GREEN}PASS${NC}] Running processes: None"
    fi

    # 3. Check /home/acunetix directory
    if [ -d "/home/acunetix" ]; then
        echo -e "  [${RED}FAIL${NC}] /home/acunetix directory still exists."
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  [${GREEN}PASS${NC}] /home/acunetix directory: Removed"
    fi

    # 4. Check user existence
    if id "acunetix" &>/dev/null; then
        echo -e "  [${RED}FAIL${NC}] User 'acunetix' still exists."
        ERRORS=$((ERRORS + 1))
    else
        echo -e "  [${GREEN}PASS${NC}] System user 'acunetix': Removed"
    fi

    # 5. Check Port 13443 / 3443
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -qE ":(13443|3443)\b"; then
            echo -e "  [${YELLOW}WARN${NC}] Port 13443 or 3443 is still in use by another process."
        else
            echo -e "  [${GREEN}PASS${NC}] Acunetix ports (13443 / 3443): Free"
        fi
    fi

    echo -e "${PURPLE}${BOLD}======================================================================${NC}"
    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}${BOLD} >>> SUCCESS: Acunetix has been completely and deeply removed! <<< ${NC}\n"
    else
        echo -e "${RED}${BOLD} >>> COMPLETED WITH WARNINGS: Please review the failed items above. <<< ${NC}\n"
    fi
}

# ---------------- Main Execution Flow ----------------
main() {
    print_banner
    check_root
    confirm_cleanup
    stop_services
    kill_processes
    remove_immutable_flags
    remove_service_files
    remove_user_and_group
    purge_directories
    clean_temp_files
    clean_hosts_file
    clean_crontabs
    clean_local_artifacts
    verify_cleanup
}

main "$@"
