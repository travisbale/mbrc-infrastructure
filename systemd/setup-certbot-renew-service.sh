#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="$HOME/.config/systemd/user"

mkdir -p "$SYSTEMD_DIR"
ln -sf "$SCRIPT_DIR/certbot-renew.service" "$SYSTEMD_DIR/certbot-renew.service"
ln -sf "$SCRIPT_DIR/certbot-renew.timer" "$SYSTEMD_DIR/certbot-renew.timer"

systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable --now certbot-renew.timer
