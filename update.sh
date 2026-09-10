#!/bin/bash
# Updates an installed server-guardian to the latest GitHub release.
# Downloads the release tarball, then replaces the script files in place.
# .env, systemd/guardian.service and the runtime state files
# (send-alert.txt, top-report.txt) are never part of the release archive,
# so they are left untouched.

set -euo pipefail

REPO="alfiosalanitri/server-guardian"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warning() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[x]${NC} %s\n" "$*"; exit 1; }

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INSTALL_DIR"

[ "$EUID" -ne 0 ] && error "Run as root: sudo make update"
command -v curl >/dev/null || error "curl is required."
command -v tar  >/dev/null || error "tar is required."

current_version="v0.0.0"
[ -f VERSION ] && current_version="v$(cat VERSION)"

info "Current version: $current_version"
info "Checking latest release on GitHub..."

latest_tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
[ -n "$latest_tag" ] || error "Could not determine the latest release from GitHub."

info "Latest version : $latest_tag"

if [ "$current_version" = "$latest_tag" ]; then
  info "Already up to date."
  exit 0
fi

read -r -p "Update $current_version -> $latest_tag? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { warning "Aborted, nothing changed."; exit 0; }

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

info "Downloading $latest_tag..."
curl -fsSL -o "$tmp_dir/server-guardian.tar.gz" \
  "https://github.com/$REPO/releases/download/$latest_tag/server-guardian.tar.gz"

tar -xzf "$tmp_dir/server-guardian.tar.gz" -C "$tmp_dir"
src_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name 'server-guardian-*')
[ -n "$src_dir" ] || error "Unexpected archive layout."

info "Installing updated files..."
cp -f "$src_dir/guardian.sh" "$src_dir/install.sh" "$src_dir/update.sh" \
      "$src_dir/Makefile" "$src_dir/README.md" "$src_dir/LICENSE" \
      "$src_dir/.env.demo" "$src_dir/VERSION" "$INSTALL_DIR/"
mkdir -p "$INSTALL_DIR/systemd"
cp -f "$src_dir/systemd/guardian.timer" "$INSTALL_DIR/systemd/"

chown root:root "$INSTALL_DIR"/*.sh "$INSTALL_DIR/Makefile" "$INSTALL_DIR/systemd/guardian.timer"
chmod 754 "$INSTALL_DIR/guardian.sh"
chmod 755 "$INSTALL_DIR/install.sh" "$INSTALL_DIR/update.sh"

if [ -d /run/systemd/system ] && [ -f /etc/systemd/system/guardian.timer ]; then
  systemctl daemon-reload
  info "systemd reloaded"
fi

info "Updated $current_version -> $latest_tag."
