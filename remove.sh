#!/bin/bash

# ==================================================
# Acunetix Deep Removal Script
# ==================================================
# This script attempts to completely remove Acunetix,
# including services, files, users, and configuration.
# ==================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }

# --------------------------------------------
# 1. Stop and disable Acunetix services
# --------------------------------------------
log "Stopping and disabling Acunetix services..."

for svc in acunetix.service acunetix_trial.service; do
    if systemctl list-unit-files | grep -q "^${svc}"; then
        warn "Found systemd service: ${svc}"
        systemctl stop "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
        rm -f "/etc/systemd/system/${svc}" 2>/dev/null || true
        rm -f "/lib/systemd/system/${svc}" 2>/dev/null || true
        log "Removed systemd unit: ${svc}"
    fi
done

# Also try legacy service command
if command -v service >/dev/null 2>&1; then
    service acunetix stop 2>/dev/null || true
    service acunetix_trial stop 2>/dev/null || true
fi

# Reload systemd
systemctl daemon-reload 2>/dev/null || true

# --------------------------------------------
# 2. Remove installation directories
# --------------------------------------------
log "Removing Acunetix installation directories..."

# Common installation paths
PATHS=(
    "/home/acunetix"
    "/opt/acunetix"
    "/usr/local/acunetix"
    "/usr/share/acunetix"
    "/var/lib/acunetix"
    "/var/log/acunetix"
    "/etc/acunetix"
    "/tmp/acunetix*"
)

for p in "${PATHS[@]}"; do
    # Use globbing for patterns
    for match in $p; do
        if [[ -e "$match" ]]; then
            warn "Removing: $match"
            rm -rf "$match" 2>/dev/null || true
        fi
    done
done

# --------------------------------------------
# 3. Delete Acunetix user and group
# --------------------------------------------
log "Deleting Acunetix user and group..."

if id "acunetix" &>/dev/null; then
    userdel -r acunetix 2>/dev/null || userdel acunetix 2>/dev/null || true
    log "Deleted user: acunetix"
fi

if getent group "acunetix" &>/dev/null; then
    groupdel acunetix 2>/dev/null || true
    log "Deleted group: acunetix"
fi

# --------------------------------------------
# 4. Remove lock files and runtime data
# --------------------------------------------
log "Removing lock files and runtime data..."

rm -f /var/lock/acunetix* 2>/dev/null || true
rm -f /var/run/acunetix* 2>/dev/null || true
rm -f /run/acunetix* 2>/dev/null || true
rm -rf /var/cache/acunetix* 2>/dev/null || true
rm -rf /var/spool/acunetix* 2>/dev/null || true

# --------------------------------------------
# 5. Clean up cron jobs
# --------------------------------------------
log "Cleaning up Acunetix cron jobs..."

# System-wide crontabs
for cronfile in /etc/crontab /etc/cron.d/* /etc/cron.daily/* /etc/cron.hourly/* /etc/cron.weekly/* /etc/cron.monthly/*; do
    if [[ -f "$cronfile" ]] && grep -qi "acunetix" "$cronfile" 2>/dev/null; then
        warn "Removing cron file with Acunetix entries: $cronfile"
        rm -f "$cronfile" 2>/dev/null || true
    fi
done

# User crontabs
if command -v crontab >/dev/null 2>&1; then
    if id "acunetix" &>/dev/null; then
        crontab -u acunetix -r 2>/dev/null || true
    fi
fi

# --------------------------------------------
# 6. Remove logrotate configurations
# --------------------------------------------
log "Removing logrotate configurations..."

for lr in /etc/logrotate.d/acunetix* /etc/logrotate.d/acunetix_trial*; do
    if [[ -e "$lr" ]]; then
        warn "Removing logrotate config: $lr"
        rm -f "$lr" 2>/dev/null || true
    fi
done

# --------------------------------------------
# 7. Remove any remaining files by name
# --------------------------------------------
log "Searching for remaining Acunetix files..."

# Search common directories for acunetix-named files
FOUND_FILES=$(find /etc /opt /usr /var /home -iname "*acunetix*" -type f 2>/dev/null || true)
if [[ -n "$FOUND_FILES" ]]; then
    warn "Found leftover files:"
    echo "$FOUND_FILES"
    read -r -p "Delete these files? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo "$FOUND_FILES" | while read -r f; do
            rm -f "$f" 2>/dev/null || true
        done
        log "Leftover files deleted."
    fi
fi

# --------------------------------------------
# 8. Remove any remaining directories
# --------------------------------------------
log "Searching for remaining Acunetix directories..."

FOUND_DIRS=$(find /etc /opt /usr /var /home -iname "*acunetix*" -type d 2>/dev/null || true)
if [[ -n "$FOUND_DIRS" ]]; then
    warn "Found leftover directories:"
    echo "$FOUND_DIRS"
    read -r -p "Delete these directories? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo "$FOUND_DIRS" | while read -r d; do
            rm -rf "$d" 2>/dev/null || true
        done
        log "Leftover directories deleted."
    fi
fi

# --------------------------------------------
# 9. Final cleanup
# --------------------------------------------
log "Reloading systemd daemon..."
systemctl daemon-reload 2>/dev/null || true

log "Cleaning up any remaining package manager traces..."
# If installed via package manager, try to remove
if command -v apt >/dev/null 2>&1; then
    apt-get remove --purge -y acunetix 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
fi

if command -v yum >/dev/null 2>&1; then
    yum remove -y acunetix 2>/dev/null || true
fi

# --------------------------------------------
# 10. Verification
# --------------------------------------------
echo
log "Deep removal complete."
warn "It is recommended to reboot the system to ensure all processes are cleared."
warn "After reboot, verify with:"
echo "  systemctl status acunetix 2>/dev/null"
echo "  id acunetix 2>/dev/null"
echo "  ls -la /home/acunetix 2>/dev/null"
echo "  find / -iname '*acunetix*' 2>/dev/null"

read -r -p "Reboot now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    reboot
fi