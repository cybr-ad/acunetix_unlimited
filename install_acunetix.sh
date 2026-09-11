#!/usr/bin/env bash
# ============================================================
#  Acunetix v24.1 — Linux Automated Installer
#  Author : AD (D3viL) | Advanced Cybersecurity Lab
#  Usage  : sudo bash install_acunetix.sh
# ============================================================

set -euo pipefail

# ─── Constants ───────────────────────────────────────────────
readonly GDRIVE_URL="https://drive.google.com/file/d/1kxyybtPR6ZNOLXeiCYpdU66jnYTNdw0B/view?usp=sharing"
readonly RAR_FILE="Acunetix-v24.1-Linux.rar"
readonly INSTALL_DIR="Acunetix-v24.1-Linux"
readonly LOG_FILE="/tmp/acunetix_install_$(date +%Y%m%d_%H%M%S).log"

# ─── Colors ──────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';  BOLD='\033[1m'
DIM='\033[2m';       RESET='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────
log()     { echo -e "$(date '+%H:%M:%S') $*" | tee -a "$LOG_FILE"; }
banner()  { echo -e "\n${BOLD}${CYAN}$*${RESET}\n"; }
step()    { echo -e "\n${BOLD}${BLUE}[STEP]${RESET} ${BOLD}$*${RESET}" | tee -a "$LOG_FILE"; }
ok()      { echo -e "${GREEN}  ✔  $*${RESET}" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}  ⚠  $*${RESET}" | tee -a "$LOG_FILE"; }
err()     { echo -e "${RED}  ✘  $*${RESET}" | tee -a "$LOG_FILE"; exit 1; }
info()    { echo -e "${DIM}      $*${RESET}" | tee -a "$LOG_FILE"; }
divider() { echo -e "${DIM}──────────────────────────────────────────────────────${RESET}"; }

# Spinner for background waits
spinner() {
    local pid=$1 msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${RESET}  %s  " "${frames[i % ${#frames[@]}]}" "$msg"
        (( i++ )) || true
        sleep 0.1
    done
    printf "\r%-60s\r" " "   # clear spinner line
}

# Run a command silently, logging output, die on failure
run() {
    local label="$1"; shift
    info "Running: $*"
    if "$@" >> "$LOG_FILE" 2>&1; then
        ok "$label"
    else
        err "$label FAILED — see $LOG_FILE"
    fi
}

# ─── Root check ──────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Run as root:  sudo bash $0"
    fi
}

# ─── Banner ──────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    cat << 'EOF'
  ╔═══════════════════════════════════════════════════════╗
  ║         ACUNETIX v24.1  —  LINUX INSTALLER           ║
  ║         Advanced Cybersecurity Lab  ·  D3viL          ║
  ╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
    echo -e "  ${DIM}Log file : ${LOG_FILE}${RESET}"
    echo -e "  ${DIM}Date     : $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
    divider
}

# ─── STEP 1 — Dependencies ───────────────────────────────────
install_dependencies() {
    step "1/6  Installing dependencies (apt + gdown)"

    # apt update
    info "Updating package lists…"
    (apt-get update -qq >> "$LOG_FILE" 2>&1) &
    spinner $! "apt update"
    ok "apt update"

    # Ensure unrar, python3-pip, curl present
    local pkgs=()
    for pkg in unrar python3-pip curl; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            pkgs+=("$pkg")
        else
            info "$pkg already installed — skipping"
        fi
    done

    if [[ ${#pkgs[@]} -gt 0 ]]; then
        info "Installing: ${pkgs[*]}"
        (DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}" >> "$LOG_FILE" 2>&1) &
        spinner $! "apt install ${pkgs[*]}"
        ok "Packages installed: ${pkgs[*]}"
    fi

    # gdown via pip
    if python3 -c "import gdown" &>/dev/null 2>&1; then
        info "gdown already present — skipping"
    else
        info "Installing gdown via pip…"
        (pip3 install -q gdown >> "$LOG_FILE" 2>&1) &
        spinner $! "pip3 install gdown"
        ok "gdown installed"
    fi
}

# ─── STEP 2 — Download ───────────────────────────────────────
download_rar() {
    step "2/6  Downloading Acunetix installer from Google Drive"

    if [[ -f "$RAR_FILE" ]]; then
        warn "$RAR_FILE already exists — skipping download"
        info "Delete it first if you want a fresh download."
        return
    fi

    info "Source : $GDRIVE_URL"
    info "Target : $(pwd)/$RAR_FILE"
    echo ""

    # gdown outputs its own progress — let it print directly
    if ! gdown "$GDRIVE_URL" -O "$RAR_FILE" 2>&1 | tee -a "$LOG_FILE"; then
        err "Download failed. Check the URL or your internet connection."
    fi

    # Verify we actually got a RAR file
    local size
    size=$(du -sh "$RAR_FILE" 2>/dev/null | cut -f1)
    ok "Download complete  (${size}B)"
}

# ─── STEP 3 — Extract ────────────────────────────────────────
extract_rar() {
    step "3/6  Extracting $RAR_FILE"

    if [[ -d "$INSTALL_DIR" ]]; then
        warn "Directory '$INSTALL_DIR' already exists — skipping extraction"
        info "Remove it if you want a clean extract."
        return
    fi

    (unrar x -y "$RAR_FILE" >> "$LOG_FILE" 2>&1) &
    spinner $! "Extracting — this may take a moment…"

    if [[ ! -d "$INSTALL_DIR" ]]; then
        err "Extraction failed — '$INSTALL_DIR' not found. See $LOG_FILE"
    fi

    ok "Extracted to ./$INSTALL_DIR/"
}

# ─── STEP 4 — Permissions ────────────────────────────────────
fix_permissions() {
    step "4/6  Setting execute permissions on shell scripts"

    local scripts
    scripts=$(find "$INSTALL_DIR" -maxdepth 2 -name "*.sh" 2>/dev/null | wc -l)

    if [[ "$scripts" -eq 0 ]]; then
        warn "No .sh files found in $INSTALL_DIR — check the archive contents"
    else
        chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
        # Also handle nested scripts if any
        find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
        ok "chmod +x applied to $scripts script(s)"
    fi
}

# ─── STEP 5 — start.sh ───────────────────────────────────────
run_start() {
    step "5/6  Launching start.sh  (interactive setup)"
    divider
    echo -e "${YELLOW}  ➜  Handing control to Acunetix setup wizard…${RESET}"
    echo -e "${DIM}     Complete the setup in the browser/terminal, then${RESET}"
    echo -e "${DIM}     return here and press ENTER to continue.${RESET}"
    divider
    echo ""

    cd "$INSTALL_DIR"

    if [[ ! -f "start.sh" ]]; then
        err "start.sh not found in $INSTALL_DIR — check extraction"
    fi

    # Run interactively (user sees all output)
    bash start.sh 2>&1 | tee -a "$LOG_FILE" || true
}

# ─── STEP 6 — Wait + last.sh ─────────────────────────────────
wait_and_finish() {
    step "6/6  Post-setup finalizer (last.sh)"
    divider
    echo ""
    echo -e "${BOLD}${YELLOW}  ⏸   Acunetix setup is running…${RESET}"
    echo ""
    echo -e "  When you have completed the Acunetix web UI setup:"
    echo -e "  ${BOLD}(create admin account, activate license, finish wizard)${RESET}"
    echo ""

    # Wait for user to confirm setup is done
    while true; do
        echo -ne "  ${CYAN}➜  Have you finished the Acunetix setup? [y/N]: ${RESET}"
        read -r answer < /dev/tty
        case "${answer,,}" in
            y|yes) break ;;
            n|no|"")
                echo -e "  ${DIM}Take your time — press y when ready.${RESET}"
                ;;
            *)
                echo -e "  ${YELLOW}Please enter y (yes) or n (no)${RESET}"
                ;;
        esac
    done

    echo ""
    info "User confirmed setup complete — running last.sh"

    if [[ ! -f "last.sh" ]]; then
        err "last.sh not found — check if it is inside $INSTALL_DIR"
    fi

    divider
    echo -e "${BOLD}${CYAN}  ➜  Running last.sh…${RESET}"
    divider
    echo ""

    bash last.sh 2>&1 | tee -a "$LOG_FILE"
}

# ─── Summary ─────────────────────────────────────────────────
print_summary() {
    divider
    echo ""
    echo -e "${BOLD}${GREEN}  ✔  Acunetix v24.1 installation complete!${RESET}"
    echo ""
    echo -e "  ${DIM}Full install log : ${LOG_FILE}${RESET}"
    echo ""
    divider
    echo ""
}

# ─── Main ────────────────────────────────────────────────────
main() {
    print_banner
    check_root

    # Run from a consistent working directory
    local WORK_DIR
    WORK_DIR="$(pwd)"
    cd "$WORK_DIR"

    install_dependencies
    download_rar
    extract_rar
    fix_permissions
    run_start
    wait_and_finish
    print_summary
}

# ─── Trap for clean exit on Ctrl+C ───────────────────────────
trap 'echo -e "\n${RED}  Interrupted. Log saved to ${LOG_FILE}${RESET}"; exit 130' INT TERM

main "$@"
