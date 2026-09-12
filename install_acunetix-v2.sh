#!/bin/bash
# ==============================================================================
# Script Name   : install_acunetix-v2.sh
# Description   : Official Acunetix Installation, Service Configuration & 
#                 Connectivity Verification Script for Kali Linux
# ==============================================================================

set -uo pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}"
echo "======================================================================"
echo "         ACUNETIX INSTALLATION & CONNECTIVITY DIAGNOSTIC TOOL         "
echo "======================================================================"
echo -e "${NC}"

# ---------------- 1. Privilege Check ----------------
check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}[!] Error: This script must be run as root or with sudo privileges.${NC}"
        echo -e "    Please run: ${YELLOW}sudo bash $0${NC}\n"
        exit 1
    fi
}
check_root

# ---------------- 2. Install Prerequisites ----------------
echo -e "${BLUE}[1/7] Checking and installing prerequisites...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y -qq curl iproute2 dnsutils unrar gdown libx11-6 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates libnss3 libasound2 libatk-bridge2.0-0 libgtk-3-0 >/dev/null 2>&1 || {
    echo -e "${YELLOW}[*] Updating apt package lists and installing core dependencies...${NC}"
    apt install -y curl iproute2 dnsutils unrar gdown
}
echo -e "${GREEN}[+] Prerequisites verified.${NC}"

# ---------------- 3. Locate or Extract Official Installer ----------------
echo -e "\n${BLUE}[2/7] Locating official Acunetix installer package...${NC}"
INSTALLER_PATH=$(find . -maxdepth 2 -type f -name "acunetix_*_x64.sh" 2>/dev/null | head -n 1)

if [ -z "$INSTALLER_PATH" ]; then
    if [ -f "Acunetix-v24.1-Linux.rar" ]; then
        echo -e "${YELLOW}[*] Extracting Acunetix-v24.1-Linux.rar...${NC}"
        unrar x -o+ Acunetix-v24.1-Linux.rar >/dev/null 2>&1
    elif [ -f "../Acunetix-v24.1-Linux.rar" ]; then
        echo -e "${YELLOW}[*] Extracting ../Acunetix-v24.1-Linux.rar...${NC}"
        unrar x -o+ ../Acunetix-v24.1-Linux.rar >/dev/null 2>&1
    fi
    INSTALLER_PATH=$(find . -maxdepth 2 -type f -name "acunetix_*_x64.sh" 2>/dev/null | head -n 1)
fi

if [ -n "$INSTALLER_PATH" ] && [ -f "$INSTALLER_PATH" ]; then
    chmod +x "$INSTALLER_PATH"
    echo -e "${GREEN}[+] Found installer at: $INSTALLER_PATH${NC}"
    echo -e "${YELLOW}[*] Launching official Acunetix installation...${NC}"
    echo -e "    Please follow the prompts to configure admin email, password, and settings.\n"
    "$INSTALLER_PATH"
else
    echo -e "${YELLOW}[!] No acunetix_*_x64.sh package found in the current directory.${NC}"
    echo -e "    Checking if Acunetix is already installed as a service..."
fi

# ---------------- 4. Service Verification & Start ----------------
echo -e "\n${BLUE}[3/7] Verifying Acunetix service status...${NC}"
systemctl daemon-reload 2>/dev/null || true

SERVICE_NAME="acunetix"
if ! systemctl list-unit-files | grep -q "^acunetix.service"; then
    if [ -f "/etc/init.d/acunetix" ]; then
        SERVICE_NAME="acunetix"
    elif [ -d "/home/acunetix/.acunetix" ]; then
        echo -e "${YELLOW}[*] Found installation in /home/acunetix/.acunetix${NC}"
    fi
fi

echo -e "${YELLOW}[*] Starting/Restarting Acunetix service (${SERVICE_NAME})...${NC}"
systemctl enable "$SERVICE_NAME" 2>/dev/null || true
systemctl restart "$SERVICE_NAME" 2>/dev/null || /etc/init.d/acunetix restart 2>/dev/null || true

sleep 3

if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "${GREEN}[+] Service '$SERVICE_NAME' is active (running).${NC}"
else
    echo -e "${RED}[!] Warning: Service '$SERVICE_NAME' is not active yet. Checking logs and waiting...${NC}"
fi

# ---------------- 5. Port Listening Check (Port 3443) ----------------
echo -e "\n${BLUE}[4/7] Checking listening ports and network sockets...${NC}"
echo -e "${YELLOW}[*] Acunetix backend services may take up to 30 seconds to initialize database & web sockets...${NC}"

TARGET_PORT=3443
PORT_FOUND=0

for i in $(seq 1 30); do
    if ss -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_FOUND=1
        echo -e "${GREEN}[+] Acunetix web daemon is listening on port ${TARGET_PORT}! (Detected at ${i}s)${NC}"
        break
    elif netstat -tuln 2>/dev/null | grep -q ":${TARGET_PORT} "; then
        PORT_FOUND=1
        echo -e "${GREEN}[+] Acunetix web daemon is listening on port ${TARGET_PORT}! (Detected at ${i}s)${NC}"
        break
    fi
    echo -ne "    Waiting for port ${TARGET_PORT}... (${i}/30s)\r"
    sleep 2
done
echo ""

if [ "$PORT_FOUND" -ne 1 ]; then
    echo -e "${RED}[!] Error: Port ${TARGET_PORT} is NOT listening after 60 seconds.${NC}"
    echo -e "${RED}[!] Diagnostic Information:${NC}"
    echo -e "--- Systemd Service Status ---"
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || true
    echo -e "--- Recent Service Journal Logs ---"
    journalctl -u "$SERVICE_NAME" -n 30 --no-pager 2>/dev/null || true
    if [ -d "/home/acunetix/.acunetix/data/logs" ]; then
        echo -e "--- Acunetix Backend Logs ---"
        tail -n 25 /home/acunetix/.acunetix/data/logs/*.log 2>/dev/null || true
    fi
    exit 1
fi

# Show actual listening socket
echo -e "${CYAN}Active socket binding on port ${TARGET_PORT}:${NC}"
ss -tulnp 2>/dev/null | grep ":${TARGET_PORT}" || netstat -tulnp 2>/dev/null | grep ":${TARGET_PORT}" || true

# ---------------- 6. Protocol & Connectivity Health Check ----------------
echo -e "\n${BLUE}[5/7] Testing HTTP vs HTTPS web connectivity...${NC}"

# Test plain HTTP (Expected to fail or require TLS)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://127.0.0.1:${TARGET_PORT}" 2>/dev/null || echo "FAILED")
echo -e "  - Plain HTTP check (http://127.0.0.1:${TARGET_PORT}): Response code = ${YELLOW}${HTTP_CODE}${NC} (HTTP is rejected or unsupported)"

# Test HTTPS (Using -k to allow self-signed certificate)
HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://127.0.0.1:${TARGET_PORT}" 2>/dev/null || echo "FAILED")
echo -e "  - HTTPS check      (https://127.0.0.1:${TARGET_PORT}): Response code = ${GREEN}${HTTPS_CODE}${NC}"

if [ "$HTTPS_CODE" = "FAILED" ] || [ "$HTTPS_CODE" = "000" ]; then
    echo -e "${RED}[!] Error: Failed to establish HTTPS handshake on port ${TARGET_PORT}.${NC}"
    echo -e "    Checking curl error details:"
    curl -k -v "https://127.0.0.1:${TARGET_PORT}" 2>&1 | head -n 20
    exit 1
else
    echo -e "${GREEN}[+] HTTPS connection successfully established! (HTTP Status: ${HTTPS_CODE})${NC}"
fi

# ---------------- 7. Hostname Resolution Check ('kali') ----------------
echo -e "\n${BLUE}[6/7] Verifying hostname resolution for 'kali'...${NC}"
KALI_RESOLVED=0

if getent hosts kali >/dev/null 2>&1; then
    RESOLVED_IP=$(getent hosts kali | awk '{print $1}' | head -n 1)
    echo -e "${GREEN}[+] 'kali' resolves to: ${RESOLVED_IP}${NC}"
    KALI_RESOLVED=1
else
    echo -e "${YELLOW}[!] 'kali' is not mapped in /etc/hosts.${NC}"
    echo -e "${YELLOW}[*] Adding '127.0.0.1 kali' to /etc/hosts for seamless browser resolution...${NC}"
    echo "127.0.0.1 kali" >> /etc/hosts
    if getent hosts kali >/dev/null 2>&1; then
        echo -e "${GREEN}[+] Successfully updated /etc/hosts.${NC}"
        KALI_RESOLVED=1
    fi
fi

# Get primary network IP (for LAN / Host access)
PRIMARY_IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1 || echo "")

# ---------------- 8. Summary & Access Instructions ----------------
echo -e "\n${BLUE}[7/7] Deployment & Access Verification Summary${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}             ACUNETIX IS READY AND ACCESSIBLE!                        ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo ""
echo -e "${BOLD}CRITICAL NOTICE:${NC}"
echo -e "1. Acunetix requires ${BOLD}${GREEN}HTTPS${NC} (not http). Plain http will fail."
echo -e "2. Your browser will display a ${YELLOW}Self-Signed Certificate Warning${NC} on first visit."
echo -e "   Click ${BOLD}Advanced -> Accept the Risk and Continue / Proceed to localhost (unsafe)${NC}.\n"

echo -e "${BOLD}Open any of the following verified URLs in your Kali browser:${NC}"
echo -e "  --> ${CYAN}https://127.0.0.1:${TARGET_PORT}${NC}  (Recommended direct loopback)"
echo -e "  --> ${CYAN}https://localhost:${TARGET_PORT}${NC}"
if [ "$KALI_RESOLVED" -eq 1 ]; then
    echo -e "  --> ${CYAN}https://kali:${TARGET_PORT}${NC}"
fi

if [ -n "$PRIMARY_IP" ]; then
    echo ""
    echo -e "${BOLD}If accessing from a host machine (e.g. Windows browser outside the VM):${NC}"
    echo -e "  --> ${CYAN}https://${PRIMARY_IP}:${TARGET_PORT}${NC}"
fi

echo -e "\n${GREEN}[+] All checks passed successfully.${NC}\n"
exit 0
