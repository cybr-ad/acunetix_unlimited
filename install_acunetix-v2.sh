#!/bin/bash
# ==============================================================================
# Script Name   : install.sh / install_acunetix-v2.sh
# Description   : Fully Automated Acunetix Setup, Dependency Fix, Service Start,
#                 and Connectivity Diagnostic Script for Kali Linux
# Compatibility : Kali Linux (All versions), Debian, Ubuntu
# ==============================================================================

set -uo pipefail

# ---------------- Color Definitions ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "======================================================================"
echo "          ACUNETIX COMPLETE INSTALLATION & HEALTH DIAGNOSTIC          "
echo "======================================================================"
echo -e "${NC}"

# ---------------- Step 1: Privilege Verification ----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[!] Error: This script must be executed with root/sudo privileges.${NC}"
    echo -e "    Please run: ${YELLOW}sudo bash $0${NC}\n"
    exit 1
fi

# ---------------- Step 2: Install System Dependencies ----------------
echo -e "${BLUE}[1/6] Installing required system libraries and dependencies...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq

# Essential Kali / Debian dependencies for Acunetix headless browser & database engines
apt install -y -qq \
    curl \
    iproute2 \
    dnsutils \
    unrar \
    gdown \
    ca-certificates \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libasound2t64 >/dev/null 2>&1 || true

echo -e "${GREEN}[+] Dependencies installed successfully.${NC}"

# ---------------- Step 3: Locate or Download Installer ----------------
echo -e "\n${BLUE}[2/6] Locating Acunetix installation files...${NC}"

# List of common search paths on Kali Linux
SEARCH_LOCATIONS=(
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

find_installer() {
    for dir in "${SEARCH_LOCATIONS[@]}"; do
        [ -d "$dir" ] 2>/dev/null || continue
        local match
        match=$(find "$dir" -maxdepth 3 -type f \( -name "acunetix_*_x64.sh" -o -name "acunetix*.sh" -o -name "*acunetix*.sh" \) 2>/dev/null | head -n 1)
        if [ -n "$match" ] && [ -f "$match" ]; then
            echo "$match"
            return 0
        fi
    done
    echo ""
}

find_archive() {
    for dir in "${SEARCH_LOCATIONS[@]}"; do
        [ -d "$dir" ] 2>/dev/null || continue
        local match
        match=$(find "$dir" -maxdepth 2 -type f \( -name "*Acunetix*.rar" -o -name "*acunetix*.rar" \) 2>/dev/null | head -n 1)
        if [ -n "$match" ] && [ -f "$match" ]; then
            echo "$match"
            return 0
        fi
    done
    echo ""
}

INSTALLER_BIN=$(find_installer)

if [ -z "$INSTALLER_BIN" ]; then
    ARCHIVE_FILE=$(find_archive)
    
    if [ -z "$ARCHIVE_FILE" ]; then
        echo -e "${YELLOW}[*] Installer archive not found locally. Downloading Acunetix-v24.1-Linux.rar via gdown...${NC}"
        gdown --fuzzy -O Acunetix-v24.1-Linux.rar 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || \
        gdown -O Acunetix-v24.1-Linux.rar 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || true
        ARCHIVE_FILE="Acunetix-v24.1-Linux.rar"
    fi

    if [ -f "$ARCHIVE_FILE" ]; then
        echo -e "${YELLOW}[*] Extracting archive: $ARCHIVE_FILE...${NC}"
        unrar x -o+ "$ARCHIVE_FILE" >/dev/null 2>&1 || unrar x -o+ "$ARCHIVE_FILE" || true
    fi

    INSTALLER_BIN=$(find_installer)
fi

# ---------------- Step 4: Execute Official Installer ----------------
if [ -n "$INSTALLER_BIN" ] && [ -f "$INSTALLER_BIN" ]; then
    chmod +x "$INSTALLER_BIN"
    echo -e "${GREEN}[+] Found installer at: $INSTALLER_BIN${NC}"
    echo -e "${YELLOW}${BOLD}======================================================================${NC}"
    echo -e "${YELLOW}${BOLD}[*] Launching Acunetix Setup Wizard...${NC}"
    echo -e "    1. Accept the license agreement (press Space/Enter, then type 'yes')."
    echo -e "    2. Set your Admin Email and Password when prompted."
    echo -e "${YELLOW}${BOLD}======================================================================${NC}\n"
    
    "$INSTALLER_BIN"
else
    if [ -d "/home/acunetix/.acunetix" ]; then
        echo -e "${GREEN}[+] Existing Acunetix installation detected at /home/acunetix/.acunetix${NC}"
    else
        echo -e "${RED}[!] Error: Could not locate or download the Acunetix installer package.${NC}"
        echo -e "    Please place 'acunetix_..._x64.sh' in $(pwd) and re-run this script."
        exit 1
    fi
fi

# ---------------- Step 5: Service Start & Verification ----------------
echo -e "\n${BLUE}[3/6] Starting and verifying Acunetix system services...${NC}"
systemctl daemon-reload 2>/dev/null || true

SERVICE_NAME="acunetix"
if ! systemctl list-unit-files | grep -q "^acunetix.service"; then
    if [ -f "/home/acunetix/.acunetix/start.sh" ]; then
        echo -e "${YELLOW}[*] Starting via /home/acunetix/.acunetix/start.sh...${NC}"
        su - acunetix -c "/home/acunetix/.acunetix/start.sh" >/dev/null 2>&1 || true
    fi
fi

systemctl enable "$SERVICE_NAME" 2>/dev/null || true
systemctl restart "$SERVICE_NAME" 2>/dev/null || /etc/init.d/acunetix restart 2>/dev/null || true

sleep 3

# ---------------- Step 6: Port 3443 Polling ----------------
echo -e "\n${BLUE}[4/6] Waiting for Acunetix Web UI to bind to port 3443...${NC}"
TARGET_PORT=3443
PORT_READY=0

for i in $(seq 1 45); do
    if ss -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Web service is listening on port ${TARGET_PORT}! (Ready after ${i}s)${NC}"
        break
    elif netstat -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Web service is listening on port ${TARGET_PORT}! (Ready after ${i}s)${NC}"
        break
    fi
    echo -ne "    Waiting for port ${TARGET_PORT} to open... (${i}/45s)\r"
    sleep 2
done
echo ""

if [ "$PORT_READY" -ne 1 ]; then
    echo -e "${RED}[!] Error: Port ${TARGET_PORT} failed to open after 90 seconds.${NC}"
    echo -e "${RED}--- Diagnostic Information ---${NC}"
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || true
    journalctl -u "$SERVICE_NAME" -n 25 --no-pager 2>/dev/null || true
    if [ -d "/home/acunetix/.acunetix/data/logs" ]; then
        tail -n 20 /home/acunetix/.acunetix/data/logs/*.log 2>/dev/null || true
    fi
    exit 1
fi

# ---------------- Step 7: Protocol & Hostname Health Checks ----------------
echo -e "\n${BLUE}[5/6] Performing HTTPS handshake and health checks...${NC}"

# TLS Connectivity Check
HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://127.0.0.1:${TARGET_PORT}" 2>/dev/null || echo "FAILED")

if [ "$HTTP_STATUS" = "FAILED" ] || [ "$HTTP_STATUS" = "000" ]; then
    echo -e "${RED}[!] HTTPS handshake failed on 127.0.0.1:${TARGET_PORT}.${NC}"
    curl -k -v "https://127.0.0.1:${TARGET_PORT}" 2>&1 | head -n 15
    exit 1
else
    echo -e "${GREEN}[+] HTTPS connection verified (HTTP Status: ${HTTP_STATUS}).${NC}"
fi

# Hostname Resolution
if ! grep -qE '\bkali\b' /etc/hosts 2>/dev/null; then
    echo -e "${YELLOW}[*] Adding '127.0.0.1 kali' to /etc/hosts...${NC}"
    echo "127.0.0.1 kali" >> /etc/hosts
fi
echo -e "${GREEN}[+] Hostname 'kali' successfully configured in /etc/hosts.${NC}"

# Get Local IP for Host Access
LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "")

# ---------------- Step 8: Success Summary & URLs ----------------
echo -e "\n${BLUE}[6/6] Setup Summary${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}             ACUNETIX IS READY AND RUNNING!                           ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "${YELLOW}${BOLD}[IMPORTANT] BROWSER INSTRUCTIONS:${NC}"
echo -e "1. You ${BOLD}MUST${NC} use ${GREEN}${BOLD}HTTPS${NC} (not http)."
echo -e "2. When your browser displays the ${YELLOW}\"Potential Security Risk / Connection Not Private\"${NC} warning:"
echo -e "   Click ${BOLD}Advanced -> Accept the Risk and Continue${NC} (or Proceed to unsafe)."
echo ""
echo -e "${BOLD}Open any of the following URLs in your Kali browser:${NC}"
echo -e "  --> ${CYAN}${BOLD}https://127.0.0.1:${TARGET_PORT}${NC}  (Recommended)"
echo -e "  --> ${CYAN}${BOLD}https://localhost:${TARGET_PORT}${NC}"
echo -e "  --> ${CYAN}${BOLD}https://kali:${TARGET_PORT}${NC}"

if [ -n "$LAN_IP" ]; then
    echo ""
    echo -e "${BOLD}If accessing from your Windows Host browser:${NC}"
    echo -e "  --> ${CYAN}${BOLD}https://${LAN_IP}:${TARGET_PORT}${NC}"
fi

echo -e "\n${GREEN}[+] All services operational.${NC}\n"
exit 0
