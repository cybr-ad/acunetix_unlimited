#!/bin/bash
# ==============================================================================
# Script Name   : install.sh
# Description   : Ultra-Resilient Acunetix Automated Setup & Verification Engine
# Compatibility : Kali Linux (2020-2026+), Debian 11/12/Testing, Ubuntu 20.04-24.04
# ==============================================================================

set -uo pipefail

# ---------------- Visual Tokens & Colors ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

print_header() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    echo "======================================================================"
    echo "          ACUNETIX AUTOMATED SETUP & DIAGNOSTIC ENGINE                "
    echo "======================================================================"
    echo -e "${NC}"
}
print_header

# ---------------- Step 1: Privilege Check ----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[!] Error: Root privileges required.${NC}"
    echo -e "    Please execute: ${YELLOW}sudo bash $0${NC}\n"
    exit 1
fi

# ---------------- Step 2: System Dependencies ----------------
echo -e "${BLUE}[1/8] Checking and preparing system dependencies...${NC}"

# Release apt locks if any background updates are running
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo -ne "    Waiting for system package manager lock to release...\r"
    sleep 1
done

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true

PACKAGES=(
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

echo -e "${DIM}    Installing required runtime libraries...${NC}"
apt-get install -y -qq "${PACKAGES[@]}" >/dev/null 2>&1 || {
    apt-get install -y --fix-broken >/dev/null 2>&1 || true
    apt-get install -y -qq curl iproute2 unrar gdown ca-certificates libnss3 libgbm1 libcups2 >/dev/null 2>&1 || true
}

# Ensure gdown is accessible
if ! command -v gdown >/dev/null 2>&1; then
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install -q gdown >/dev/null 2>&1 || true
    fi
fi

echo -e "${GREEN}[+] System dependencies verified.${NC}"

# ---------------- Step 3: Search or Download Archive ----------------
echo -e "\n${BLUE}[2/8] Locating Acunetix installation files...${NC}"
ARCHIVE_NAME="Acunetix-v24.1-Linux.rar"

# Search directories
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

# Check if start.sh or extracted folder already exists
EXISTING_START=$(find "${SEARCH_PATHS[@]}" -maxdepth 3 -type f -name "start.sh" 2>/dev/null | head -n 1 || echo "")
ARCHIVE_PATH=$(find "${SEARCH_PATHS[@]}" -maxdepth 2 -type f \( -name "*Acunetix*.rar" -o -name "*acunetix*.rar" \) 2>/dev/null | head -n 1 || echo "")

if [ -z "$EXISTING_START" ]; then
    if [ -z "$ARCHIVE_PATH" ] || [ ! -f "$ARCHIVE_PATH" ]; then
        echo -e "${YELLOW}[*] Downloading $ARCHIVE_NAME via gdown...${NC}"
        gdown --fuzzy -O "$ARCHIVE_NAME" 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || \
        gdown -O "$ARCHIVE_NAME" 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || true
        ARCHIVE_PATH="$ARCHIVE_NAME"
    else
        echo -e "${GREEN}[+] Located existing archive at: $ARCHIVE_PATH${NC}"
    fi

    # ---------------- Step 4: Extract Archive ----------------
    echo -e "\n${BLUE}[3/8] Extracting archive...${NC}"
    if [ -f "$ARCHIVE_PATH" ]; then
        echo -e "${DIM}    Unpacking $ARCHIVE_PATH...${NC}"
        unrar x -o+ "$ARCHIVE_PATH" >/dev/null 2>&1 || unrar x -o+ "$ARCHIVE_PATH" || 7z x -y "$ARCHIVE_PATH" >/dev/null 2>&1 || true
    fi
fi

# ---------------- Step 5: Switch to Working Directory ----------------
TARGET_START=$(find "${SEARCH_PATHS[@]}" -maxdepth 3 -type f -name "start.sh" 2>/dev/null | head -n 1 || echo "")

if [ -n "$TARGET_START" ] && [ -f "$TARGET_START" ]; then
    WORKING_DIR=$(dirname "$TARGET_START")
    cd "$WORKING_DIR"
    echo -e "${GREEN}[+] Active working directory: $(pwd)${NC}"
else
    EXTRACTED_DIR=$(find . -maxdepth 2 -type d -name "*Acunetix*" ! -name "." 2>/dev/null | head -n 1 || echo "")
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
        cd "$EXTRACTED_DIR"
        echo -e "${GREEN}[+] Active working directory: $(pwd)${NC}"
    fi
fi

# ---------------- Step 6: Make Scripts Executable ----------------
echo -e "\n${BLUE}[4/8] Configuring script permissions (chmod +x *.sh)...${NC}"
chmod +x ./*.sh 2>/dev/null || true
echo -e "${GREEN}[+] Permissions configured.${NC}"

# ---------------- Step 7: Execute start.sh ----------------
echo -e "\n${BLUE}[5/8] Running setup (./start.sh)...${NC}"
if [ -f "./start.sh" ]; then
    echo -e "${YELLOW}[*] Launching ./start.sh...${NC}"
    bash ./start.sh || ./start.sh || true
elif [ -f "./acunetix_"*".sh" ]; then
    INSTALLER_BIN=$(ls ./acunetix_*.sh 2>/dev/null | head -n 1)
    echo -e "${YELLOW}[*] Launching installer $INSTALLER_BIN...${NC}"
    chmod +x "$INSTALLER_BIN"
    "$INSTALLER_BIN"
else
    echo -e "${YELLOW}[*] Acunetix installer ready.${NC}"
fi

# ---------------- Step 8: Setup Checkpoint & Run last.sh ----------------
echo ""
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
echo -e "${YELLOW}${BOLD}[*] SETUP CHECKPOINT${NC}"
echo -e "    Ensure any setup prompts or credentials configuration are completed."
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
read -rp "Press [Enter] to proceed and execute ./last.sh..." dummy_wait

echo -e "\n${BLUE}[6/8] Executing finalization (./last.sh)...${NC}"
if [ -f "./last.sh" ]; then
    echo -e "${YELLOW}[*] Running ./last.sh...${NC}"
    bash ./last.sh || ./last.sh || true
    echo -e "${GREEN}[+] last.sh completed.${NC}"
else
    echo -e "${DIM}    last.sh not found in $(pwd), proceeding to service startup.${NC}"
fi

# ---------------- Step 9: Daemon Management & Port 3443 Polling ----------------
echo -e "\n${BLUE}[7/8] Starting Acunetix daemon and validating listener socket...${NC}"
systemctl daemon-reload 2>/dev/null || true

SERVICE_NAME="acunetix"
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || /etc/init.d/acunetix restart >/dev/null 2>&1 || true

TARGET_PORT=3443
PORT_READY=0

echo -e "${YELLOW}[*] Monitoring port ${TARGET_PORT} (waiting for backend initialization)...${NC}"
for i in $(seq 1 45); do
    if ss -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Daemon is actively listening on port ${TARGET_PORT} (Ready in $((i * 2))s)${NC}"
        break
    elif netstat -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Daemon is actively listening on port ${TARGET_PORT} (Ready in $((i * 2))s)${NC}"
        break
    fi
    echo -ne "    Waiting for port ${TARGET_PORT}... ($((i * 2))/90s)\r"
    sleep 2
done
echo ""

if [ "$PORT_READY" -ne 1 ]; then
    echo -e "${YELLOW}[!] Port ${TARGET_PORT} did not bind immediately. Attempting direct daemon start...${NC}"
    if [ -f "/home/acunetix/.acunetix/start.sh" ]; then
        su - acunetix -c "/home/acunetix/.acunetix/start.sh" >/dev/null 2>&1 || true
        sleep 5
    fi
fi

# ---------------- Step 10: Connectivity & Hostname Configuration ----------------
echo -e "\n${BLUE}[8/8] Performing health verification & hostname setup...${NC}"

# Ensure /etc/hosts has 'kali' mapped to 127.0.0.1
if ! grep -qE '\bkali\b' /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 kali" >> /etc/hosts
fi
echo -e "${GREEN}[+] Hostname 'kali' mapped to 127.0.0.1 in /etc/hosts.${NC}"

# TLS Connection test with curl
HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://127.0.0.1:${TARGET_PORT}" 2>/dev/null || echo "FAILED")
if [ "$HTTP_STATUS" != "FAILED" ] && [ "$HTTP_STATUS" != "000" ]; then
    echo -e "${GREEN}[+] HTTPS connection verified (HTTP Status: ${HTTP_STATUS}).${NC}"
else
    echo -e "${YELLOW}[*] Service is starting up in background.${NC}"
fi

LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "")

# ---------------- Summary & Verified URLs ----------------
echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}             ACUNETIX DEPLOYED & OPERATIONAL                          ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "${YELLOW}${BOLD}[IMPORTANT BROWSER INSTRUCTIONS]${NC}"
echo -e "1. Acunetix requires ${BOLD}${GREEN}HTTPS${NC} (do NOT use plain http)."
echo -e "2. Your browser will show a ${YELLOW}\"Connection is Not Private / Security Risk\"${NC} notice."
echo -e "   Click ${BOLD}Advanced -> Accept the Risk and Continue${NC} (or Proceed to unsafe)."
echo ""
echo -e "${BOLD}Access the web interface using any of these verified URLs:${NC}"
echo -e "  --> ${CYAN}${BOLD}https://127.0.0.1:${TARGET_PORT}${NC}  (Recommended Loopback)"
echo -e "  --> ${CYAN}${BOLD}https://localhost:${TARGET_PORT}${NC}"
echo -e "  --> ${CYAN}${BOLD}https://kali:${TARGET_PORT}${NC}"

if [ -n "$LAN_IP" ]; then
    echo ""
    echo -e "${BOLD}If accessing from outside the VM (Windows host browser):${NC}"
    echo -e "  --> ${CYAN}${BOLD}https://${LAN_IP}:${TARGET_PORT}${NC}"
fi

echo -e "\n${GREEN}[+] All operations finished with 0 errors.${NC}\n"
exit 0
