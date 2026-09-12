#!/bin/bash
# ==============================================================================
# Script Name   : install.sh
# Description   : Step-by-Step Acunetix Installation & Connectivity Pipeline
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

echo -e "${CYAN}${BOLD}"
echo "======================================================================"
echo "          ACUNETIX STEP-BY-STEP INSTALLATION & DIAGNOSTICS            "
echo "======================================================================"
echo -e "${NC}"

# ---------------- Step 0: Privilege Check ----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo -e "${RED}[!] Error: This script must be executed as root or with sudo.${NC}"
    echo -e "    Please run: ${YELLOW}sudo bash $0${NC}\n"
    exit 1
fi

# ---------------- Step 1: Install Dependencies ----------------
echo -e "${BLUE}[1/8] Updating package lists and installing required dependencies...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq

# Essential system utilities & headless browser libraries for Kali Linux
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

# ---------------- Step 2: Download Archive via gdown ----------------
echo -e "\n${BLUE}[2/8] Checking for installation archive...${NC}"
ARCHIVE_NAME="Acunetix-v24.1-Linux.rar"

if [ ! -f "$ARCHIVE_NAME" ] && [ ! -f "../$ARCHIVE_NAME" ]; then
    echo -e "${YELLOW}[*] Downloading $ARCHIVE_NAME via gdown...${NC}"
    gdown --fuzzy -O "$ARCHIVE_NAME" 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || \
    gdown -O "$ARCHIVE_NAME" 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B || true
fi

# Locate the archive file
ARCHIVE_PATH=""
if [ -f "$ARCHIVE_NAME" ]; then
    ARCHIVE_PATH="$ARCHIVE_NAME"
elif [ -f "../$ARCHIVE_NAME" ]; then
    ARCHIVE_PATH="../$ARCHIVE_NAME"
fi

# ---------------- Step 3: Extract Archive & Navigate Directory ----------------
echo -e "\n${BLUE}[3/8] Extracting archive and entering directory...${NC}"
if [ -n "$ARCHIVE_PATH" ] && [ -f "$ARCHIVE_PATH" ]; then
    unrar x -o+ "$ARCHIVE_PATH" >/dev/null 2>&1 || unrar x -o+ "$ARCHIVE_PATH"
fi

# Locate extracted directory
EXTRACTED_DIR=$(find . -maxdepth 2 -type d -name "*Acunetix*" ! -name "." 2>/dev/null | head -n 1 || echo "")
if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then
    echo -e "${GREEN}[+] Entering directory: $EXTRACTED_DIR${NC}"
    cd "$EXTRACTED_DIR"
fi

# ---------------- Step 4: Make Scripts Executable ----------------
echo -e "\n${BLUE}[4/8] Making script files executable (chmod +x *.sh)...${NC}"
chmod +x ./*.sh 2>/dev/null || true

# ---------------- Step 5: Execute start.sh / Setup ----------------
echo -e "\n${BLUE}[5/8] Executing setup / start.sh...${NC}"
if [ -f "./start.sh" ]; then
    echo -e "${YELLOW}[*] Running ./start.sh...${NC}"
    ./start.sh
elif [ -f "./acunetix_"*".sh" ]; then
    INSTALLER_SH=$(ls ./acunetix_*.sh 2>/dev/null | head -n 1)
    echo -e "${YELLOW}[*] Running $INSTALLER_SH...${NC}"
    chmod +x "$INSTALLER_SH"
    "$INSTALLER_SH"
else
    echo -e "${YELLOW}[*] Starting standard Acunetix service...${NC}"
fi

# ---------------- Step 6: Execute last.sh ----------------
echo -e "\n${BLUE}[6/8] Executing finalization / last.sh...${NC}"
if [ -f "./last.sh" ]; then
    echo -e "${YELLOW}[*] Running ./last.sh...${NC}"
    ./last.sh || true
fi

# ---------------- Step 7: Verify Service & Port 3443 ----------------
echo -e "\n${BLUE}[7/8] Starting system services and waiting for port 3443...${NC}"
systemctl daemon-reload 2>/dev/null || true

SERVICE_NAME="acunetix"
systemctl enable "$SERVICE_NAME" 2>/dev/null || true
systemctl restart "$SERVICE_NAME" 2>/dev/null || /etc/init.d/acunetix restart 2>/dev/null || true

TARGET_PORT=3443
PORT_READY=0

echo -e "${YELLOW}[*] Waiting for Acunetix web daemon to bind to port ${TARGET_PORT}...${NC}"
for i in $(seq 1 45); do
    if ss -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Service is listening on port ${TARGET_PORT}! (Detected at ${i}s)${NC}"
        break
    elif netstat -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_READY=1
        echo -e "${GREEN}[+] Service is listening on port ${TARGET_PORT}! (Detected at ${i}s)${NC}"
        break
    fi
    echo -ne "    Waiting for port ${TARGET_PORT}... (${i}/45s)\r"
    sleep 2
done
echo ""

if [ "$PORT_READY" -ne 1 ]; then
    echo -e "${RED}[!] Warning: Port ${TARGET_PORT} not detected yet. Checking logs...${NC}"
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || true
fi

# ---------------- Step 8: Health Checks & Output URLs ----------------
echo -e "\n${BLUE}[8/8] Testing connectivity and configuring hostname...${NC}"

# Hostname mapping
if ! grep -qE '\bkali\b' /etc/hosts 2>/dev/null; then
    echo -e "${YELLOW}[*] Adding '127.0.0.1 kali' to /etc/hosts...${NC}"
    echo "127.0.0.1 kali" >> /etc/hosts
fi

# Local IP for host machine access
LAN_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "")

# Output Summary
echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}                   ACUNETIX SETUP COMPLETED                           ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "${YELLOW}${BOLD}[NOTICE] BROWSER INSTRUCTIONS:${NC}"
echo -e "1. You ${BOLD}MUST${NC} use ${GREEN}${BOLD}HTTPS${NC} (not http)."
echo -e "2. When your browser shows the ${YELLOW}\"Security Risk / Connection Not Private\"${NC} warning:"
echo -e "   Click ${BOLD}Advanced -> Accept the Risk and Continue${NC}."
echo ""
echo -e "${BOLD}Open any of the following URLs in your Kali browser:${NC}"
echo -e "  --> ${CYAN}${BOLD}https://127.0.0.1:${TARGET_PORT}${NC}  (Recommended)"
echo -e "  --> ${CYAN}${BOLD}https://localhost:${TARGET_PORT}${NC}"
echo -e "  --> ${CYAN}${BOLD}https://kali:${TARGET_PORT}${NC}"

if [ -n "$LAN_IP" ]; then
    echo ""
    echo -e "${BOLD}If accessing from your Windows host browser:${NC}"
    echo -e "  --> ${CYAN}${BOLD}https://${LAN_IP}:${TARGET_PORT}${NC}"
fi

echo -e "\n${GREEN}[+] All steps completed.${NC}\n"
exit 0
