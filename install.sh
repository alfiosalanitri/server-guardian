#!/bin/bash
# Installs server-guardian.
# Interactively writes the .env config file, then uses a systemd timer if
# systemd is the running init system, otherwise falls back to a root
# crontab entry (every minute).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
ENV_FILE="$INSTALL_DIR/.env"
LEGACY_CONFIG_FILE="$INSTALL_DIR/.config"
CRON_ENTRY="* * * * * cd $INSTALL_DIR && $INSTALL_DIR/guardian.sh > /dev/null 2>&1"

info()    { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warning() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[x]${NC} %s\n" "$*"; exit 1; }

[ "$EUID" -ne 0 ] && error "Run as root: sudo make install"

# ask VARNAME "question" ["default"]
# No default -> keeps asking until a non-empty value is entered.
ask() {
  local __resultvar=$1 __question=$2 __default=${3-} __input=""
  if [ -n "$__default" ]; then
    read -r -p "$__question [$__default]: " __input
    __input="${__input:-$__default}"
  else
    while [ -z "$__input" ]; do
      read -r -p "$__question: " __input
    done
  fi
  printf -v "$__resultvar" '%s' "$__input"
}

# ask_yn VARNAME "question" "y|n" -> sets VARNAME to 1 or 0
ask_yn() {
  local __resultvar=$1 __question=$2 __default=$3 __input __hint="y/N"
  [ "$__default" = "y" ] && __hint="Y/n"
  read -r -p "$__question [$__hint]: " __input
  __input="${__input:-$__default}"
  case "$__input" in
    y|Y|yes|YES) printf -v "$__resultvar" '1' ;;
    *)           printf -v "$__resultvar" '0' ;;
  esac
}

configure() {
  echo ""
  info "Configuring server-guardian — answers are saved to $ENV_FILE"
  echo ""

  ask telegram_bot_token "Telegram bot token"
  ask telegram_user_chat_id "Telegram chat id"
  ask send_alert_every_minutes "Minutes between repeated alerts" "60"

  ask_yn watch_cpu "Monitor CPU load?" "y"
  if [ "$watch_cpu" = "1" ]; then
    ask cpu_warning_level "CPU sensitivity (low, medium, high)" "medium"
  else
    cpu_warning_level="medium"
  fi

  ask_yn watch_ram "Monitor RAM usage?" "y"
  if [ "$watch_ram" = "1" ]; then
    ask memory_perc_limit "RAM usage percentage limit" "70"
  else
    memory_perc_limit="70"
  fi

  ask_yn watch_services "Monitor failed systemd services?" "y"

  ask_yn watch_hard_disk "Monitor disk space?" "y"
  if [ "$watch_hard_disk" = "1" ]; then
    ask disk_space_perc_limit "Disk usage percentage limit" "80"
  else
    disk_space_perc_limit="80"
  fi

  ask_yn watch_supervisor "Monitor supervisor (supervisorctl) failed processes?" "n"

  cat > "$ENV_FILE" <<EOF
telegram_bot_token=$telegram_bot_token
telegram_user_chat_id=$telegram_user_chat_id
send_alert_every_minutes=$send_alert_every_minutes
memory_perc_limit=$memory_perc_limit
disk_space_perc_limit=$disk_space_perc_limit
cpu_warning_level=$cpu_warning_level
watch_cpu=$watch_cpu
watch_ram=$watch_ram
watch_services=$watch_services
watch_hard_disk=$watch_hard_disk
watch_supervisor=$watch_supervisor
EOF
  chmod 600 "$ENV_FILE"
  echo ""
  info ".env written"
}

info "Installing server-guardian from $INSTALL_DIR"

# Migrate pre-.env installs: keep working for anyone who cloned the repo
# and configured .config before the .env rename.
if [ ! -f "$ENV_FILE" ] && [ -f "$LEGACY_CONFIG_FILE" ]; then
  mv "$LEGACY_CONFIG_FILE" "$ENV_FILE"
  warning "Migrated legacy .config to .env"
fi

if [ -f "$ENV_FILE" ]; then
  reconfigure=0
  ask_yn reconfigure "$ENV_FILE already exists. Reconfigure it?" "n"
  [ "$reconfigure" = "1" ] && configure
else
  configure
fi

# Ownership and permissions
chown -R root:root "$INSTALL_DIR"
chmod 754 "$INSTALL_DIR/guardian.sh"
touch "$INSTALL_DIR/send-alert.txt" "$INSTALL_DIR/top-report.txt"
chmod 640 "$INSTALL_DIR/send-alert.txt"
chmod 644 "$INSTALL_DIR/top-report.txt"
chmod 600 "$ENV_FILE"
info "Permissions set"

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
printf "  Config file  : %s\n" "$ENV_FILE"
printf "  Test the bot : sudo %s/guardian.sh --test\n" "$INSTALL_DIR"
printf "  Check status : %s\n" "$SCHEDULER_STATUS"
