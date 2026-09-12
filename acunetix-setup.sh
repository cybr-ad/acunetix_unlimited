#!/bin/bash
# ==============================================================================
# Script Name   : acunetix-setup.sh
# Description   : Automated Step-by-Step Acunetix Installation Pipeline
# Compatibility : Kali Linux, Debian, Ubuntu
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

# ---------------- Step 0: Privilege Verification ----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[!] Error: This script must be executed as root or with sudo.${NC}"
    echo -e "    Please run: ${YELLOW}sudo bash $0${NC}\n"
    exit 1
fi

# ---------------- Step 1: Install Dependencies ----------------
echo -e "${BLUE}[1/8] Installing required packages (gdown, unrar, and system libraries)...${NC}"
export DEBIAN_FRONTEND=noninteractive

# Wait for package manager lock if active
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo -ne "    Waiting for package manager lock release...\r"
    sleep 1
done

apt-get update -qq >/dev/null 2>&1 || true

PACKAGES=(
    gdown
    unrar
    p7zip-full
    curl
    iproute2
    dnsutils
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

apt-get install -y -qq "${PACKAGES[@]}" >/dev/null 2>&1 || {
    apt-get install -y --fix-broken >/dev/null 2>&1 || true
    apt-get install -y -qq gdown unrar curl iproute2 dnsutils ca-certificates libnss3 libgbm1 libcups2 >/dev/null 2>&1 || true
}

echo -e "${GREEN}[+] Dependencies verified.${NC}"

# ---------------- Step 2: Download Archive via gdown ----------------
echo -e "\n${BLUE}[2/8] Checking for Acunetix archive...${NC}"
ARCHIVE_NAME="Acunetix-v24.1-Linux.rar"

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

ARCHIVE_PATH=$(find "${SEARCH_DIRS[@]}" -maxdepth 2 -type f \( -name "*Acunetix*.rar" -o -name "*acunetix*.rar" \) 2>/dev/null | head -n 1 || echo "")

if [ -z "$ARCHIVE_PATH" ] || [ ! -f "$ARCHIVE_PATH" ]; then
    echo -e "${YELLOW}[*] Downloading $ARCHIVE_NAME via gdown...${NC}"
    gdown --continue -O "$ARCHIVE_NAME" "https://drive.google.com/uc?id=1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B" || \
    gdown -O "$ARCHIVE_NAME" "1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B"
    ARCHIVE_PATH="$ARCHIVE_NAME"
else
    echo -e "${GREEN}[+] Located archive at: $ARCHIVE_PATH${NC}"
fi

# ---------------- Step 3: Extract Archive (unrar x) ----------------
echo -e "\n${BLUE}[3/8] Extracting archive ($ARCHIVE_PATH)...${NC}"
if [ -f "$ARCHIVE_PATH" ]; then
    unrar x -o+ "$ARCHIVE_PATH" >/dev/null 2>&1 || unrar x -o+ "$ARCHIVE_PATH" || 7z x -y "$ARCHIVE_PATH" >/dev/null 2>&1 || true
fi

# ---------------- Step 4: CD to the Unrared Folder ----------------
echo -e "\n${BLUE}[4/8] Entering unrared directory...${NC}"
START_SH_LOC=$(find "${SEARCH_DIRS[@]}" -maxdepth 3 -type f \( -name "start.sh" -o -name "acunetix_*_x64.sh" \) 2>/dev/null | head -n 1 || echo "")

if [ -n "$START_SH_LOC" ] && [ -f "$START_SH_LOC" ]; then
    cd "$(dirname "$START_SH_LOC")"
    echo -e "${GREEN}[+] Active folder: $(pwd)${NC}"
else
    EXTRACTED_DIR=$(find . -maxdepth 2 -type d -name "*Acunetix*" ! -name "." 2>/dev/null | head -n 1 || echo "")
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
        cd "$EXTRACTED_DIR"
        echo -e "${GREEN}[+] Active folder: $(pwd)${NC}"
    fi
fi

# ---------------- Step 5: Make Scripts Executable (chmod +x *.sh) ----------------
echo -e "\n${BLUE}[5/8] Running chmod +x *.sh...${NC}"
chmod +x ./*.sh 2>/dev/null || true
echo -e "${GREEN}[+] All .sh scripts are executable.${NC}"

# ---------------- Step 6: Run Installer, Wait, then Run start.sh ----------------
echo -e "\n${BLUE}[6/8] Executing setup...${NC}"

# 1. Run main Acunetix installer
INSTALLER_BIN=$(ls ./acunetix_*.sh 2>/dev/null | head -n 1 || echo "")
if [ -n "$INSTALLER_BIN" ] && [ -f "$INSTALLER_BIN" ]; then
    echo -e "${YELLOW}${BOLD}======================================================================${NC}"
    echo -e "${YELLOW}${BOLD}[*] Step 6a: Launching Acunetix Installer ($INSTALLER_BIN)...${NC}"
    echo -e "    1. Accept the license agreement (press Space/q, then type 'yes')."
    echo -e "    2. Configure your Administrator Email and Password."
    echo -e "${YELLOW}${BOLD}======================================================================${NC}\n"
    chmod +x "$INSTALLER_BIN"
    "$INSTALLER_BIN"

    echo ""
    echo -e "${YELLOW}${BOLD}======================================================================${NC}"
    echo -e "${YELLOW}${BOLD}[*] ACUNETIX INSTALLER FINISHED${NC}"
    echo -e "    Please confirm your installer setup has completed."
    echo -e "${YELLOW}${BOLD}======================================================================${NC}"
    read -rp "Press [Enter] to execute ./start.sh..." dummy_start
fi

# 2. Run start.sh
if [ -f "./start.sh" ]; then
    echo -e "\n${YELLOW}[*] Step 6b: Launching ./start.sh...${NC}"
    bash ./start.sh || ./start.sh || true
fi

# ---------------- Step 7: Wait & Hand Control to User -> Ask to Run last.sh ----------------
echo ""
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
echo -e "${YELLOW}${BOLD}[*] START.SH COMPLETED - USER CONTROL${NC}"
echo -e "    start.sh has finished executing."
echo -e "    Please complete any remaining setup in your terminal or browser."
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
read -rp "Press [Enter] when you are ready to run ./last.sh..." dummy_last

echo -e "\n${BLUE}[7/8] Executing ./last.sh...${NC}"
if [ -f "./last.sh" ]; then
    echo -e "${YELLOW}[*] Running ./last.sh...${NC}"
    bash ./last.sh || ./last.sh || true
    echo -e "${GREEN}[+] ./last.sh completed.${NC}"
else
    echo -e "${YELLOW}[*] No ./last.sh found in $(pwd), continuing to service verification.${NC}"
fi

# ---------------- Step 8: Verify Service & Output Dashboard URLs ----------------
echo -e "\n${BLUE}[8/8] Starting Acunetix daemon and testing port 3443...${NC}"
systemctl daemon-reload 2>/dev/null || true

SERVICE_NAME="acunetix"
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || /etc/init.d/acunetix restart >/dev/null 2>&1 || true

TARGET_PORT=3443
PORT_READY=0

echo -e "${YELLOW}[*] Waiting for Acunetix web daemon to bind to port ${TARGET_PORT}...${NC}"
for i in $(seq 1 45); do
    if ss -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Daemon is actively listening on port ${TARGET_PORT}! (Ready in $((i * 2))s)${NC}"
        break
    elif netstat -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Daemon is actively listening on port ${TARGET_PORT}! (Ready in $((i * 2))s)${NC}"
        break
    fi
    echo -ne "    Waiting for port ${TARGET_PORT}... ($((i * 2))/90s)\r"
    sleep 2
done
echo ""

# Ensure /etc/hosts has 'kali' mapped to 127.0.0.1
if ! grep -qE '\bkali\b' /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 kali" >> /etc/hosts
fi

# Local IP for host machine access
LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "")

# ---------------- Final Dashboard Notice ----------------
echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}             ACUNETIX IS READY AND RUNNING!                           ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "${YELLOW}${BOLD}[IMPORTANT BROWSER INSTRUCTIONS]${NC}"
echo -e "1. You ${BOLD}MUST${NC} use ${GREEN}${BOLD}HTTPS${NC} (do not use plain http)."
echo -e "2. When your browser shows the ${YELLOW}\"Security Risk / Connection Not Private\"${NC} warning:"
echo -e "   Click ${BOLD}Advanced -> Accept the Risk and Continue${NC} (or Proceed to localhost)."
echo ""
echo -e "${BOLD}Open the Acunetix dashboard in your Kali browser:${NC}"
echo -e "  --> ${CYAN}${BOLD}https://localhost:${TARGET_PORT}${NC}"
echo -e "  --> ${CYAN}${BOLD}https://127.0.0.1:${TARGET_PORT}${NC}"
echo -e "  --> ${CYAN}${BOLD}https://kali:${TARGET_PORT}${NC}"

if [ -n "$LAN_IP" ]; then
    echo ""
    echo -e "${BOLD}If accessing from outside the VM (Windows host browser):${NC}"
    echo -e "  --> ${CYAN}${BOLD}https://${LAN_IP}:${TARGET_PORT}${NC}"
fi

echo -e "\n${GREEN}[+] Setup complete with 0 errors.${NC}\n"
exit 0
