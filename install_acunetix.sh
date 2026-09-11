#!/bin/bash
set -e

# 1. Update package list and install dependencies
echo "[+] Installing prerequisites (gdown, unrar)..."
sudo apt update && sudo apt install -y gdown unrar

# 2. Download Acunetix archive using gdown
echo "[+] Downloading Acunetix-v24.1-Linux.rar..."
gdown -O Acunetix-v24.1-Linux.rar 1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B

# 3. Extract the RAR archive and navigate into the extracted directory
echo "[+] Extracting archive..."
unrar x -o+ Acunetix-v24.1-Linux.rar
cd Acunetix-v24.1.240111130-Linux

# 4. Make all .sh files executable
echo "[+] Making .sh scripts executable..."
chmod +x *.sh

# 5. Run the official Acunetix installer
# This creates the 'acunetix' user and required directories (/home/acunetix/.acunetix/...)
echo ""
echo "================================================================="
echo "[+] Starting Acunetix Installer (acunetix_*_x64.sh)..."
echo "    - Follow the prompts to accept the license agreement."
echo "    - Configure your admin email and password."
echo "================================================================="
echo ""
sudo ./acunetix_*.sh

# 6. Run start.sh with sudo privileges (if present)
if [ -f "./start.sh" ]; then
    echo "[+] Executing start.sh..."
    sudo ./start.sh
fi

# 7. Wait for user confirmation / finish setup before running last.sh
echo ""
read -p "Press [Enter] once the setup is complete to run last.sh..."

# 8. Run last.sh with sudo privileges (if present)
if [ -f "./last.sh" ]; then
    echo "[+] Executing last.sh..."
    sudo ./last.sh
fi

echo ""
echo "[+] Setup completed successfully!"
