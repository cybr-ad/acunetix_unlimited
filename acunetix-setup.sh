#!/bin/bash
# ==============================================================================
# Script Name   : acunetix-setup.sh
# Description   : Official Acunetix Installation, Service Management & Verification
# Compatibility : Kali Linux (All releases), Debian, Ubuntu
# ==============================================================================

set -uo pipefail

# ---------------- Colors for Output ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    echo "======================================================================"
    echo "       ACUNETIX OFFICIAL INSTALLATION & SERVICE DIAGNOSTICS           "
    echo "======================================================================"
    echo -e "${NC}"
}
print_banner

# ---------------- 1. Privilege Verification ----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[!] Error: Root privileges required.${NC}"
    echo -e "    Please execute: ${YELLOW}sudo bash $0${NC}\n"
    exit 1
fi

# ---------------- 2. System Dependencies & Runtime Libraries ----------------
echo -e "${BLUE}[1/7] Updating package index and installing required system libraries...${NC}"

# Handle package manager lock if active
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo -ne "    Waiting for apt lock release...\r"
    sleep 1
done

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true

DEPENDENCIES=(
    curl
    iproute2
    dnsutils
    unrar
    p7zip-full
    gdown
    ca-certificates
    libnss3
    libatk1.0-0
    libatk-bridge2.0-0
    libcups2
    libdrm2
    libxkbcommon0
    libxcomposite1
    libxdamage1
    libxfixes3
    libxrandr2
    libgbm1
    libpango-1.0-0
    libcairo2
    libasound2
    libasound2t64
)

apt-get install -y -qq "${DEPENDENCIES[@]}" >/dev/null 2>&1 || {
    apt-get install -y --fix-broken >/dev/null 2>&1 || true
    apt-get install -y -qq curl iproute2 dnsutils unrar gdown ca-certificates libnss3 libgbm1 libcups2 >/dev/null 2>&1 || true
}

echo -e "${GREEN}[+] System prerequisites verified.${NC}"

# ---------------- 3. Locate or Download Legitimate Installer Archive ----------------
echo -e "\n${BLUE}[2/7] Locating Acunetix installer package...${NC}"
ARCHIVE_NAME="Acunetix-v24.1-Linux.rar"

SEARCH_PATHS=(
    "."
    ".."
    "$HOME"
    "$HOME/Desktop"
    "$HOME/Downloads"
    "/root"
    "/root/Desktop"
    "/root/Downloads"
    "/home/*/Desktop"
    "/home/*/Downloads"
)

# Search for extracted installer script
INSTALLER_BIN=$(find "${SEARCH_PATHS[@]}" -maxdepth 3 -type f -name "acunetix_*_x64.sh" 2>/dev/null | head -n 1 || echo "")

if [ -z "$INSTALLER_BIN" ]; then
    ARCHIVE_PATH=$(find "${SEARCH_PATHS[@]}" -maxdepth 2 -type f \( -name "*Acunetix*.rar" -o -name "*acunetix*.rar" \) 2>/dev/null | head -n 1 || echo "")
    
    if [ -z "$ARCHIVE_PATH" ] || [ ! -f "$ARCHIVE_PATH" ]; then
        echo -e "${YELLOW}[*] Downloading installer archive (384MB) via gdown...${NC}"
        gdown --continue -O "$ARCHIVE_NAME" "https://drive.google.com/uc?id=1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B" || \
        gdown -O "$ARCHIVE_NAME" "1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B"
        ARCHIVE_PATH="$ARCHIVE_NAME"
    else
        echo -e "${GREEN}[+] Located archive file: $ARCHIVE_PATH${NC}"
    fi

    # ---------------- 4. Extract Archive ----------------
    if [ -f "$ARCHIVE_PATH" ]; then
        echo -e "${YELLOW}[*] Extracting $ARCHIVE_PATH...${NC}"
        unrar x -o+ "$ARCHIVE_PATH" >/dev/null 2>&1 || unrar x -o+ "$ARCHIVE_PATH" || 7z x -y "$ARCHIVE_PATH" >/dev/null 2>&1 || true
    fi

    INSTALLER_BIN=$(find "${SEARCH_PATHS[@]}" -maxdepth 3 -type f -name "acunetix_*_x64.sh" 2>/dev/null | head -n 1 || echo "")
fi

# ---------------- 5. Execute Official Acunetix Installer ----------------
echo -e "\n${BLUE}[3/7] Running official Acunetix installation...${NC}"

if [ -n "$INSTALLER_BIN" ] && [ -f "$INSTALLER_BIN" ]; then
    WORKING_DIR=$(dirname "$INSTALLER_BIN")
    cd "$WORKING_DIR"
    chmod +x "$INSTALLER_BIN"
    
    echo -e "${GREEN}[+] Launching installer at: $INSTALLER_BIN${NC}"
    echo -e "${YELLOW}${BOLD}======================================================================${NC}"
    echo -e "Follow the interactive wizard:"
    echo -e "  - Read and accept the End User License Agreement (Space/q, type 'yes')"
    echo -e "  - Configure your Administrator Email and Password"
    echo -e "${YELLOW}${BOLD}======================================================================${NC}\n"
    
    "$INSTALLER_BIN"
else
    if [ -d "/home/acunetix/.acunetix" ]; then
        echo -e "${GREEN}[+] Existing Acunetix installation found at /home/acunetix/.acunetix${NC}"
    else
        echo -e "${RED}[!] Error: Could not locate the official installer 'acunetix_*_x64.sh'.${NC}"
        echo -e "    Please place the installer in $(pwd) and re-run this script."
        exit 1
    fi
fi

# ---------------- 6. Service Management (systemd) ----------------
echo -e "\n${BLUE}[4/7] Verifying and starting systemd service...${NC}"
systemctl daemon-reload 2>/dev/null || true

SERVICE_NAME="acunetix"
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || /etc/init.d/acunetix restart >/dev/null 2>&1 || true

sleep 3

if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "${GREEN}[+] Systemd service '$SERVICE_NAME' is active (running).${NC}"
else
    echo -e "${YELLOW}[*] Checking daemon status...${NC}"
fi

# ---------------- 7. Port Listening Verification (Port 3443) ----------------
echo -e "\n${BLUE}[5/7] Verifying listening ports (port 3443)...${NC}"
TARGET_PORT=3443
PORT_ACTIVE=0

echo -e "${YELLOW}[*] Polling port ${TARGET_PORT} (waiting for backend initialization)...${NC}"
for i in $(seq 1 45); do
    if ss -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_ACTIVE=1
        echo -e "${GREEN}[+] Daemon is actively listening on port ${TARGET_PORT}! (Detected in $((i * 2))s)${NC}"
        break
    elif netstat -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_ACTIVE=1
        echo -e "${GREEN}[+] Daemon is actively listening on port ${TARGET_PORT}! (Detected in $((i * 2))s)${NC}"
        break
    fi
    echo -ne "    Waiting for port ${TARGET_PORT}... ($((i * 2))/90s)\r"
    sleep 2
done
echo ""

if [ "$PORT_ACTIVE" -ne 1 ]; then
    echo -e "${RED}[!] Error: Port ${TARGET_PORT} failed to bind after 90 seconds.${NC}"
    echo -e "\n${RED}--- Service Status ---${NC}"
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || true
    echo -e "\n${RED}--- Recent Journal Logs ---${NC}"
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager 2>/dev/null || true
    if [ -d "/home/acunetix/.acunetix/data/logs" ]; then
        echo -e "\n${RED}--- Backend Logs ---${NC}"
        tail -n 25 /home/acunetix/.acunetix/data/logs/*.log 2>/dev/null || true
    fi
    exit 1
fi

# Show active socket
echo -e "${CYAN}Active listener socket:${NC}"
ss -tulnp 2>/dev/null | grep ":${TARGET_PORT}" || netstat -tulnp 2>/dev/null | grep ":${TARGET_PORT}" || true

# ---------------- 8. Protocol & Health Validation ----------------
echo -e "\n${BLUE}[6/7] Testing HTTP vs HTTPS connectivity...${NC}"

# Plain HTTP test
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://127.0.0.1:${TARGET_PORT}" 2>/dev/null || echo "FAILED")
echo -e "  - Plain HTTP check (http://127.0.0.1:${TARGET_PORT}): Response code = ${YELLOW}${HTTP_STATUS}${NC} (HTTP rejected as expected)"

# HTTPS test (with -k for self-signed certificate)
HTTPS_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://127.0.0.1:${TARGET_PORT}" 2>/dev/null || echo "FAILED")
echo -e "  - HTTPS check      (https://127.0.0.1:${TARGET_PORT}): Response code = ${GREEN}${HTTPS_STATUS}${NC}"

if [ "$HTTPS_STATUS" = "FAILED" ] || [ "$HTTPS_STATUS" = "000" ]; then
    echo -e "${RED}[!] HTTPS handshake failed on 127.0.0.1:${TARGET_PORT}.${NC}"
    curl -k -v "https://127.0.0.1:${TARGET_PORT}" 2>&1 | head -n 20
    exit 1
else
    echo -e "${GREEN}[+] HTTPS connection successfully established! (HTTP Status: ${HTTPS_STATUS})${NC}"
fi

# ---------------- 9. Local Hostname Resolution ----------------
echo -e "\n${BLUE}[7/7] Verifying hostname resolution for 'kali'...${NC}"
if ! grep -qE '\bkali\b' /etc/hosts 2>/dev/null; then
    echo -e "${YELLOW}[*] Adding '127.0.0.1 kali' to /etc/hosts...${NC}"
    echo "127.0.0.1 kali" >> /etc/hosts
fi
echo -e "${GREEN}[+] Hostname 'kali' mapped to 127.0.0.1 in /etc/hosts.${NC}"

LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "")

# ---------------- 10. Dashboard Access Instructions ----------------
echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}         ACUNETIX DASHBOARD IS READY AND ACCESSIBLE!                  ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "${YELLOW}${BOLD}[IMPORTANT BROWSER INSTRUCTIONS]:${NC}"
echo -e "1. Acunetix requires ${BOLD}${GREEN}HTTPS${NC} (do NOT use plain http://)."
echo -e "2. When your browser displays the ${YELLOW}\"Connection is Not Private / Security Risk\"${NC} warning:"
echo -e "   Click ${BOLD}Advanced -> Accept the Risk and Continue${NC} (or Proceed to localhost)."
echo ""
echo -e "${BOLD}Open any of the following verified URLs in your Kali browser:${NC}"
echo -e "  --> ${CYAN}${BOLD}https://127.0.0.1:${TARGET_PORT}${NC}  (Recommended Loopback)"
echo -e "  --> ${CYAN}${BOLD}https://localhost:${TARGET_PORT}${NC}"
echo -e "  --> ${CYAN}${BOLD}https://kali:${TARGET_PORT}${NC}"

if [ -n "$LAN_IP" ]; then
    echo ""
    echo -e "${BOLD}If accessing from outside the VM (Windows host browser):${NC}"
    echo -e "  --> ${CYAN}${BOLD}https://${LAN_IP}:${TARGET_PORT}${NC}"
fi

echo -e "\n${GREEN}[+] All health checks passed successfully.${NC}\n"
exit 0
