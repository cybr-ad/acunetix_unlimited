#!/bin/bash
#
# acunetix_remove.sh
# Completely remove Acunetix (AWVS) from Linux — every leftover.
#
# Usage: sudo bash acunetix_remove.sh
#        sudo bash acunetix_remove.sh --yes     # non-interactive
#

set -uo pipefail

# ============================================================
# Colors / logging
# ============================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
hdr()  { echo; echo -e "${BOLD}=== $* ===${NC}"; }

# ============================================================
# Root check
# ============================================================
if [[ $EUID -ne 0 ]]; then
    err "Run as root:  sudo bash $0"
    exit 1
fi

# ============================================================
# Confirmation
# ============================================================
NONINTERACTIVE=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && NONINTERACTIVE=1

echo
warn "This will PERMANENTLY remove Acunetix from this system:"
echo "   - all services and running processes"
echo "   - all installation directories and scan data"
echo "   - the 'acunetix' user and group"
echo "   - licenses, systemd units, cron jobs, ports"
echo
if [[ $NONINTERACTIVE -eq 0 ]]; then
    read -r -p "$(echo -e "${CYAN}[?]${NC} Type 'yes' to continue: ")" C
    [[ "$C" != "yes" ]] && { info "Aborted."; exit 0; }
fi
echo

# ============================================================
# 1) Stop and disable services (all known names)
# ============================================================
hdr "1/10 — Stopping & disabling services"

SERVICES=(
    acunetix
    acunetix_trial
    acunetix.service
    acunetix_trial.service
    acunetix-daemon
    acunetix-daemon.service
)

for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${svc}"; then
        log "  Service found: $svc"
        systemctl stop    "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        systemctl reset-failed "$svc" 2>/dev/null || true
    fi
done

# ============================================================
# 2) Kill leftover processes
# ============================================================
hdr "2/10 — Killing leftover processes"
if pgrep -i acunetix >/dev/null 2>&1; then
    pgrep -ai acunetix | while read -r line; do warn "  killing: $line"; done
    pkill -9 -i acunetix 2>/dev/null || true
    sleep 1
    # second pass
    pkill -9 -i acunetix 2>/dev/null || true
else
    info "  No acunetix processes running."
fi

# Kill anything listening on Acunetix default ports
hdr "Ports 3443 / 13443 cleanup"
for port in 3443 13443; do
    if command -v ss >/dev/null 2>&1; then
        pids="$(ss -lptn "sport = :$port" 2>/dev/null | awk 'NR>1 {print $NF}' | grep -oP 'pid=\K[0-9]+' | sort -u)"
        for pid in $pids; do
            warn "  killing pid $pid on port $port"
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
done

# ============================================================
# 3) Run official uninstallers if present
# ============================================================
hdr "3/10 — Running official uninstaller (if present)"
FOUND_UNINSTALLER=0
UNINSTALLERS=(
    /home/acunetix/.acunetix_trial/uninstall.sh
    /home/acunetix/.acunetix/uninstall.sh
    /usr/local/acunetix/uninstall.sh
    /opt/acunetix/uninstall.sh
)
for u in "${UNINSTALLERS[@]}"; do
    if [[ -f "$u" ]]; then
        FOUND_UNINSTALLER=1
        log "  Running: $u"
        chmod +x "$u" 2>/dev/null || true
        yes | bash "$u" 2>/dev/null || warn "  uninstaller exited non-zero (continuing)"
    fi
done
[[ $FOUND_UNINSTALLER -eq 0 ]] && info "  No official uninstaller found."

# ============================================================
# 4) Clear chattr +i immutable flags on license files
# ============================================================
hdr "4/10 — Clearing immutable license flags"
for d in /home/acunetix/.acunetix/data/license \
         /home/acunetix/.acunetix_trial/data/license \
         /usr/local/acunetix/data/license \
         /opt/acunetix/data/license ; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*; do
        [[ -e "$f" ]] || continue
        chattr -i "$f" 2>/dev/null && log "  chattr -i $f"
    done
done
# Also nuke immutable flags anywhere under /home/acunetix just in case
if [[ -d /home/acunetix ]]; then
    find /home/acunetix -type f -exec chattr -i {} \; 2>/dev/null || true
fi

# ============================================================
# 5) Remove all installation directories
# ============================================================
hdr "5/10 — Removing installation directories"
DIRS=(
    /home/acunetix
    /usr/local/acunetix
    /opt/acunetix
    /etc/acunetix
    /var/lib/acunetix
    /var/log/acunetix
    /var/opt/acunetix
    /usr/share/acunetix
    /var/tmp/acunetix
    /tmp/acunetix
)
for d in "${DIRS[@]}"; do
    if [[ -e "$d" ]]; then
        log "  rm -rf $d"
        rm -rf "$d" 2>/dev/null || warn "  failed to remove $d"
    fi
done

# ============================================================
# 6) Remove the acunetix user and group
# ============================================================
hdr "6/10 — Removing user and group"
if id acunetix >/dev/null 2>&1; then
    # kill any processes still owned by the user
    pkill -9 -u acunetix 2>/dev/null || true
    sleep 1
    userdel -r acunetix 2>/dev/null || userdel acunetix 2>/dev/null || true
    log "  user 'acunetix' removed"
else
    info "  user 'acunetix' not present"
fi
if getent group acunetix >/dev/null 2>&1; then
    groupdel acunetix 2>/dev/null || true
    log "  group 'acunetix' removed"
fi

# ============================================================
# 7) Remove systemd unit files
# ============================================================
hdr "7/10 — Removing systemd unit files"
for unit in \
    /etc/systemd/system/acunetix*.service \
    /etc/systemd/system/acunetix*.timer \
    /lib/systemd/system/acunetix*.service \
    /lib/systemd/system/acunetix*.timer \
    /usr/lib/systemd/system/acunetix*.service \
    /usr/lib/systemd/system/acunetix*.timer ; do
    [[ -e "$unit" ]] && { log "  rm $unit"; rm -f "$unit"; }
done
systemctl daemon-reload 2>/dev/null || true
systemctl reset-failed 2>/dev/null || true

# ============================================================
# 8) Clean cron jobs and init scripts
# ============================================================
hdr "8/10 — Cleaning cron and init"
# root crontab
crontab -l 2>/dev/null | grep -i acunetix | while read -r line; do
    warn "  removing root cron: $line"
done
crontab -l 2>/dev/null | grep -vi acunetix | crontab - 2>/dev/null || true

# /etc/cron.*
for f in /etc/cron.d/*acunetix* \
         /etc/cron.daily/*acunetix* \
         /etc/cron.hourly/*acunetix* \
         /etc/cron.weekly/*acunetix* \
         /etc/cron.monthly/*acunetix* ; do
    [[ -e "$f" ]] && { log "  rm $f"; rm -f "$f"; }
done

# init.d / rc.d just in case
for f in /etc/init.d/acunetix* /etc/rc*.d/*acunetix*; do
    [[ -e "$f" ]] && { log "  rm $f"; rm -f "$f"; }
done

# ============================================================
# 9) Clean logrotate, sudoers, profile snippets, docker/snap
# ============================================================
hdr "9/10 — Extra cleanup"

# logrotate
for f in /etc/logrotate.d/acunetix* ; do
    [[ -e "$f" ]] && { log "  rm $f"; rm -f "$f"; }
done

# sudoers drop-ins
for f in /etc/sudoers.d/*acunetix* ; do
    [[ -e "$f" ]] && { log "  rm $f"; rm -f "$f"; }
done

# shell profile snippets
for f in /etc/profile.d/*acunetix* ; do
    [[ -e "$f" ]] && { log "  rm $f"; rm -f "$f"; }
done

# tmp files
find /tmp /var/tmp -maxdepth 1 -iname '*acunetix*' -exec rm -rf {} + 2>/dev/null || true

# Docker (if acunetix was ever run as a container)
if command -v docker >/dev/null 2>&1; then
    CID="$(docker ps -a --filter 'name=acunetix' --format '{{.ID}}' 2>/dev/null)"
    if [[ -n "$CID" ]]; then
        for id in $CID; do
            warn "  docker rm -f $id"
            docker rm -f "$id" >/dev/null 2>&1 || true
        done
    fi
fi

# Snap (rare, but possible on some distros)
if command -v snap >/dev/null 2>&1; then
    if snap list 2>/dev/null | grep -qi acunetix; then
        warn "  snap remove acunetix"
        snap remove --purge acunetix >/dev/null 2>&1 || true
    fi
fi

# ============================================================
# 10) Optional: delete local installer artefacts
# ============================================================
hdr "10/10 — Local installer cleanup"
if [[ $NONINTERACTIVE -eq 0 ]]; then
    read -r -p "$(echo -e "${CYAN}[?]${NC} Delete local installer files (RAR + extracted folder)? [y/N] ")" D
    if [[ "${D,,}" == "y" ]]; then
        # Run from wherever the user is
        for f in Acunetix-*.rar Acunetix-*-Linux ; do
            [[ -e "$f" ]] && { log "  rm -rf $f"; rm -rf "$f"; }
        done
        # Also check Desktop if invoked from elsewhere
        if [[ -n "${SUDO_USER:-}" ]]; then
            UHOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
            for f in "$UHOME"/Desktop/Acunetix-*.rar "$UHOME"/Desktop/Acunetix-*-Linux ; do
                [[ -e "$f" ]] && { log "  rm -rf $f"; rm -rf "$f"; }
            done
        fi
    else
        info "  Keeping local installer files."
    fi
fi

# ============================================================
# Verify
# ============================================================
hdr "Verification"
FAIL=0

if id acunetix >/dev/null 2>&1; then
    err "  user 'acunetix' STILL EXISTS"; FAIL=1
else
    log "  ✓ user gone"
fi

if systemctl list-unit-files 2>/dev/null | grep -qi '^acunetix'; then
    err "  systemd unit STILL PRESENT"; FAIL=1
else
    log "  ✓ systemd units gone"
fi

for d in /home/acunetix /opt/acunetix /etc/acunetix /var/lib/acunetix; do
    if [[ -e "$d" ]]; then
        err "  $d STILL EXISTS"; FAIL=1
    fi
done
[[ $FAIL -eq 0 ]] && log "  ✓ directories gone"

if pgrep -i acunetix >/dev/null 2>&1; then
    err "  processes STILL RUNNING:"; pgrep -ai acunetix
    FAIL=1
else
    log "  ✓ no processes"
fi

echo
if [[ $FAIL -eq 0 ]]; then
    log "Acunetix removal COMPLETE. Reboot recommended."
else
    warn "Removal finished with warnings. Review items above and reboot."
fi
