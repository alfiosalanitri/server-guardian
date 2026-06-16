#!/bin/bash
# Installs server-guardian.
# Uses a systemd timer if systemd is the running init system,
# otherwise falls back to a root crontab entry (every minute).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
CRON_ENTRY="* * * * * cd $INSTALL_DIR && $INSTALL_DIR/guardian.sh > /dev/null 2>&1"

info()    { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warning() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[x]${NC} %s\n" "$*"; exit 1; }

[ "$EUID" -ne 0 ] && error "Run as root: sudo bash install.sh"

info "Installing server-guardian from $INSTALL_DIR"

# Ownership and permissions
chown -R root:root "$INSTALL_DIR"
chmod 754 "$INSTALL_DIR/guardian.sh"
touch "$INSTALL_DIR/send-alert.txt" "$INSTALL_DIR/top-report.txt"
chmod 640 "$INSTALL_DIR/send-alert.txt"
chmod 644 "$INSTALL_DIR/top-report.txt"
info "Permissions set"

# Create config from demo if missing
if [ ! -f "$INSTALL_DIR/.config" ]; then
  cp "$INSTALL_DIR/.config.demo" "$INSTALL_DIR/.config"
  warning ".config created from .config.demo — edit it with your Telegram credentials before use"
fi
chmod 600 "$INSTALL_DIR/.config"

# Install the scheduler
if [ -d /run/systemd/system ]; then

  # --- systemd ---
  mkdir -p "$INSTALL_DIR/systemd"
  cat > "$INSTALL_DIR/systemd/guardian.service" <<EOF
[Unit]
Description=Server Guardian - monitor CPU, RAM, services and disk
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/guardian.sh
StandardOutput=null
StandardError=null
EOF
  info "Generated systemd/guardian.service"

  ln -sf "$INSTALL_DIR/systemd/guardian.service" "$SYSTEMD_SYSTEM_DIR/guardian.service"
  ln -sf "$INSTALL_DIR/systemd/guardian.timer"   "$SYSTEMD_SYSTEM_DIR/guardian.timer"
  info "Symlinked units to $SYSTEMD_SYSTEM_DIR"

  systemctl daemon-reload
  systemctl enable --now guardian.timer
  info "Timer enabled and started"

  SCHEDULER_STATUS="systemctl status guardian.timer"

else

  # --- crontab fallback ---
  ( crontab -l 2>/dev/null | grep -v "guardian.sh"; echo "$CRON_ENTRY" ) | crontab -
  info "Cron job added to root crontab (every minute)"

  SCHEDULER_STATUS="crontab -l"

fi

printf "\n"
info "Installation complete."
printf "  Config file  : %s/.config\n"    "$INSTALL_DIR"
printf "  Test the bot : sudo %s/guardian.sh --test\n" "$INSTALL_DIR"
printf "  Check status : %s\n" "$SCHEDULER_STATUS"
