#!/bin/bash
# Installs server-guardian as a systemd timer that runs every minute.
# Symlinks the service and timer units into /etc/systemd/system/ so updates
# to the repo are picked up without re-running the installer.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"

info()    { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warning() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[x]${NC} %s\n" "$*"; exit 1; }

[ "$EUID" -ne 0 ] && error "Run as root: sudo bash install.sh"

info "Installing server-guardian from $INSTALL_DIR"

# Ownership and permissions
chown -R root:root "$INSTALL_DIR"
chmod 754 "$INSTALL_DIR/guardian.sh"
chmod 640 "$INSTALL_DIR/send-alert.txt"
chmod 644 "$INSTALL_DIR/top-report.txt"
info "Permissions set"

# Create config from demo if missing
if [ ! -f "$INSTALL_DIR/.config" ]; then
  cp "$INSTALL_DIR/.config.demo" "$INSTALL_DIR/.config"
  warning ".config created from .config.demo — edit it with your Telegram credentials before use"
fi
chmod 600 "$INSTALL_DIR/.config"

# Generate the service file (contains the absolute install path, so not committed)
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

# Symlink both units into /etc/systemd/system/
ln -sf "$INSTALL_DIR/systemd/guardian.service" "$SYSTEMD_SYSTEM_DIR/guardian.service"
ln -sf "$INSTALL_DIR/systemd/guardian.timer"   "$SYSTEMD_SYSTEM_DIR/guardian.timer"
info "Symlinked units to $SYSTEMD_SYSTEM_DIR"

# Enable and start
systemctl daemon-reload
systemctl enable --now guardian.timer
info "Timer enabled and started"

printf "\n"
info "Installation complete."
printf "  Config file : %s/.config\n"    "$INSTALL_DIR"
printf "  Test the bot: sudo %s/guardian.sh --test\n" "$INSTALL_DIR"
printf "  Timer status: systemctl status guardian.timer\n"
