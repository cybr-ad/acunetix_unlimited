#!/bin/bash
#
# acunetix_full.sh
# Full flow:
#   1. install gdown
#   2. download Acunetix-v24.1-Linux.rar from Google Drive
#   3. unrar + cd into extracted dir
#   4. chmod +x *.sh
#   5. run ./start.sh
#   6. PAUSE -> user finishes setup wizard in browser
#   7. run ./last.sh
#
# Usage: sudo bash acunetix_full.sh
#

set -euo pipefail

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

# ---------- Root check ----------
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (use sudo)."
    exit 1
fi

# ---------- Config ----------
RAR_FILE="Acunetix-v24.1-Linux.rar"
GDRIVE_ID="1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B"
EXTRACT_DIR="Acunetix-v24.1.240111130-Linux"

# ============================================================
# 1) Install gdown (and unrar if missing)
# ============================================================
log "Updating apt and installing prerequisites (gdown, unrar)..."
apt update
apt install -y gdown unrar

# ============================================================
# 2) Download the RAR from Google Drive
# ============================================================
if [[ -f "$RAR_FILE" ]]; then
    warn "'$RAR_FILE' already exists, skipping download."
else
    log "Downloading $RAR_FILE from Google Drive..."
    gdown -O "$RAR_FILE" "$GDRIVE_ID"
fi

# ============================================================
# 3) Extract and enter the directory
# ============================================================
if [[ ! -d "$EXTRACT_DIR" ]]; then
    log "Extracting $RAR_FILE ..."
    unrar x -o+ "$RAR_FILE"
else
    warn "'$EXTRACT_DIR' already exists, skipping extraction."
fi

if [[ ! -d "$EXTRACT_DIR" ]]; then
    err "Expected directory '$EXTRACT_DIR' not found after extraction."
    err "Check the actual extracted folder name with: ls"
    exit 1
fi

cd "$EXTRACT_DIR"
log "Working directory: $(pwd)"

# ============================================================
# 4) Make all .sh files executable
# ============================================================
log "Making .sh files executable..."
chmod +x ./*.sh 2>/dev/null || true
ls -l ./*.sh 2>/dev/null || warn "No .sh files found in $(pwd)"

# ============================================================
# 5) Run start.sh
# ============================================================
if [[ ! -x "./start.sh" ]]; then
    err "./start.sh not found or not executable."
    exit 1
fi

log "Running ./start.sh ..."
./start.sh

# ============================================================
# 6) PAUSE — wait for user to finish the setup wizard
# ============================================================
echo
echo "==================================================================="
info "Acunetix installer has finished the CLI portion."
info "Now open your browser and complete the Acunetix setup wizard:"
echo
info "    https://<your-server-ip>:3443/"
echo
info "Finish creating the admin account / target setup there."
echo "==================================================================="
echo
read -r -p "$(echo -e "${CYAN}[?]${NC} Press ENTER once the web setup wizard is fully complete...")" _
echo

# ============================================================
# 7) Run last.sh
# ============================================================
if [[ ! -x "./last.sh" ]]; then
    err "./last.sh not found or not executable."
    exit 1
fi

log "Running ./last.sh ..."
./last.sh

log "All done."
info "Acunetix should now be fully installed and licensed."
info "Verify with: systemctl status acunetix"