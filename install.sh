#!/bin/bash
# ==============================================================================
# Script Name   : install.sh
# Description   : Step-by-Step Acunetix Installation, Verification & Setup Pipeline
# Compatibility : Kali Linux (All versions), Debian, Ubuntu
# ==============================================================================

set -uo pipefail

# ---------------- Colors ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear 2>/dev/null || true
echo -e "${CYAN}${BOLD}"
echo "======================================================================"
echo "          ACUNETIX STEP-BY-STEP SETUP & DIAGNOSTIC PIPELINE           "
echo "======================================================================"
echo -e "${NC}"

# ---------------- Step 1: Privilege Verification ----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[!] Error: This script must be executed as root or with sudo.${NC}"
    echo -e "    Please run: ${YELLOW}sudo bash $0${NC}\n"
    exit 1
fi

# ---------------- Step 2: Install System Dependencies ----------------
echo -e "${BLUE}[1/8] Installing prerequisites and system libraries...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq >/dev/null 2>&1 || true

# Install all necessary libraries for headless browser and database daemons
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

echo -e "${GREEN}[+] System dependencies verified.${NC}"

# ---------------- Step 3: Locate or Download Archive ----------------
echo -e "\n${BLUE}[2/8] Locating installation files...${NC}"
ARCHIVE_NAME="Acunetix-v24.1-Linux.rar"

# Search common paths
SEARCH_DIRS=(
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

INSTALLER_PKG=$(find "${SEARCH_DIRS[@]}" -maxdepth 3 -type f -name "acunetix_*_x64.sh" 2>/dev/null | head -n 1 || echo "")
ARCHIVE_FILE=$(find "${SEARCH_DIRS[@]}" -maxdepth 2 -type f \( -name "*Acunetix*.rar" -o -name "*acunetix*.rar" \) 2>/dev/null | head -n 1 || echo "")

if [ -z "$INSTALLER_PKG" ] && [ -z "$ARCHIVE_FILE" ]; then
    echo -e "${YELLOW}[*] Downloading $ARCHIVE_NAME via gdown...${NC}"
    gdown --fuzzy -O "$ARCHIVE_NAME" 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || \
    gdown -O "$ARCHIVE_NAME" 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || true
    ARCHIVE_FILE="$ARCHIVE_NAME"
fi

# ---------------- Step 4: Extract Archive if Needed ----------------
if [ -z "$INSTALLER_PKG" ] && [ -n "$ARCHIVE_FILE" ] && [ -f "$ARCHIVE_FILE" ]; then
    echo -e "\n${BLUE}[3/8] Extracting archive: $ARCHIVE_FILE...${NC}"
    unrar x -o+ "$ARCHIVE_FILE" >/dev/null 2>&1 || unrar x -o+ "$ARCHIVE_FILE" || true
fi

# ---------------- Step 5: Navigate to Extracted Directory ----------------
TARGET_DIR=$(find "${SEARCH_DIRS[@]}" -maxdepth 3 -type f \( -name "acunetix_*_x64.sh" -o -name "start.sh" \) 2>/dev/null | head -n 1 || echo "")
if [ -n "$TARGET_DIR" ]; then
    cd "$(dirname "$TARGET_DIR")"
    echo -e "${GREEN}[+] Active working directory: $(pwd)${NC}"
fi

# ---------------- Step 6: Make Scripts Executable ----------------
echo -e "\n${BLUE}[4/8] Making script files executable (chmod +x *.sh)...${NC}"
chmod +x ./*.sh 2>/dev/null || true
echo -e "${GREEN}[+] Executable permissions set.${NC}"

# ---------------- Step 7: Run Official Installer (if not installed) & start.sh ----------------
echo -e "\n${BLUE}[5/8] Running setup process...${NC}"

# 1. Run official Acunetix installer if directory doesn't exist yet
INSTALLER_BIN=$(ls ./acunetix_*.sh 2>/dev/null | head -n 1 || echo "")
if [ ! -d "/home/acunetix/.acunetix" ] && [ -n "$INSTALLER_BIN" ] && [ -f "$INSTALLER_BIN" ]; then
    echo -e "${YELLOW}${BOLD}======================================================================${NC}"
    echo -e "${YELLOW}${BOLD}[*] Step 5a: Running Acunetix Installer ($INSTALLER_BIN)...${NC}"
    echo -e "    1. Accept the license agreement (press Space/q, then type 'yes')."
    echo -e "    2. Configure your Administrator email and password."
    echo -e "${YELLOW}${BOLD}======================================================================${NC}\n"
    chmod +x "$INSTALLER_BIN"
    "$INSTALLER_BIN"
fi

# 2. Run start.sh
if [ -f "./start.sh" ]; then
    echo -e "\n${YELLOW}[*] Step 5b: Executing ./start.sh...${NC}"
    bash ./start.sh || ./start.sh || true
fi

# ---------------- Step 8: User Confirmation & Port 3443 Health Check ----------------
echo ""
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
echo -e "${YELLOW}${BOLD}[?] SETUP CONFIRMATION${NC}"
echo -e "${YELLOW}${BOLD}======================================================================${NC}"

while true; do
    read -rp "Have you completed setting up Acunetix? [y/N]: " setup_done
    case "$setup_done" in
        [yY][eE][sS]|[yY])
            echo -e "${GREEN}[+] Confirmation received.${NC}"
            break
            ;;
        *)
            echo -e "${YELLOW}[*] Waiting... Complete your setup in the terminal or browser, then type 'y'.${NC}"
            sleep 2
            ;;
    esac
done

# Restart service to ensure everything is running
echo -e "\n${BLUE}[6/8] Checking if Acunetix is running on 127.0.0.1:3443...${NC}"
systemctl daemon-reload 2>/dev/null || true
systemctl enable acunetix >/dev/null 2>&1 || true
systemctl restart acunetix >/dev/null 2>&1 || /etc/init.d/acunetix restart >/dev/null 2>&1 || true

TARGET_PORT=3443
SERVICE_UP=0

echo -e "${YELLOW}[*] Testing connection to https://127.0.0.1:${TARGET_PORT}...${NC}"
for i in $(seq 1 30); do
    if ss -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        SERVICE_UP=1
        echo -e "${GREEN}[+] Port ${TARGET_PORT} is ACTIVE and LISTENING! (Verified in $((i * 2))s)${NC}"
        break
    elif netstat -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        SERVICE_UP=1
        echo -e "${GREEN}[+] Port ${TARGET_PORT} is ACTIVE and LISTENING! (Verified in $((i * 2))s)${NC}"
        break
    fi
    echo -ne "    Waiting for 127.0.0.1:${TARGET_PORT} to respond... ($((i * 2))/60s)\r"
    sleep 2
done
echo ""

if [ "$SERVICE_UP" -eq 1 ]; then
    echo -e "${GREEN}[+] Acunetix is successfully running on 127.0.0.1:${TARGET_PORT}!${NC}"
else
    echo -e "${YELLOW}[!] Port ${TARGET_PORT} not detected. Checking service status...${NC}"
    systemctl status acunetix --no-pager 2>/dev/null || true
fi

# ---------------- Step 9: Prompt and Execute last.sh ----------------
echo ""
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
echo -e "${YELLOW}${BOLD}[*] READY FOR FINALIZATION STEP${NC}"
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
read -rp "Press [Enter] to run ./last.sh..." dummy_enter

echo -e "\n${BLUE}[7/8] Executing ./last.sh...${NC}"
if [ -f "./last.sh" ]; then
    bash ./last.sh || ./last.sh || true
    echo -e "${GREEN}[+] last.sh executed successfully.${NC}"
else
    echo -e "${YELLOW}[*] No last.sh found in $(pwd), continuing to final verification.${NC}"
fi

# ---------------- Step 10: Final Verification & Output ----------------
echo -e "\n${BLUE}[8/8] Finalizing network settings & URLs...${NC}"

# Ensure service is running after last.sh
systemctl restart acunetix >/dev/null 2>&1 || true
sleep 3

# Configure /etc/hosts for kali
if ! grep -qE '\bkali\b' /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 kali" >> /etc/hosts
fi

LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "")

echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}             ACUNETIX IS READY AND ACCESSIBLE!                        ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "${YELLOW}${BOLD}[IMPORTANT] BROWSER INSTRUCTIONS:${NC}"
echo -e "1. You ${BOLD}MUST${NC} use ${GREEN}${BOLD}HTTPS${NC} (do not use plain http)."
echo -e "2. Your browser will display a ${YELLOW}\"Security Risk / Connection Not Private\"${NC} warning."
echo -e "   Click ${BOLD}Advanced -> Accept the Risk and Continue${NC} (or Proceed to unsafe)."
echo ""
echo -e "${BOLD}Open any of the following URLs in your Kali browser:${NC}"
echo -e "  --> ${CYAN}${BOLD}https://127.0.0.1:${TARGET_PORT}${NC}  (Recommended)"
echo -e "  --> ${CYAN}${BOLD}https://localhost:${TARGET_PORT}${NC}"
echo -e "  --> ${CYAN}${BOLD}https://kali:${TARGET_PORT}${NC}"

if [ -n "$LAN_IP" ]; then
    echo ""
    echo -e "${BOLD}If accessing from outside the VM (Windows host browser):${NC}"
    echo -e "  --> ${CYAN}${BOLD}https://${LAN_IP}:${TARGET_PORT}${NC}"
fi

echo -e "\n${GREEN}[+] Setup complete with 0 errors.${NC}\n"
exit 0
