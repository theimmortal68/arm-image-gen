#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Creating user and base dirs"
USER_NAME="${KS_USER:-pi}"
HOME_DIR="/home/$USER_NAME"
GROUPS="sudo,dialout,tty,plugdev,video,render,input,gpio,i2c,spi"

if ! id "$USER_NAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USER_NAME"
fi
usermod -a -G "$GROUPS" "$USER_NAME"

# Printer data layout
install -d -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/printer_data/config"
install -d -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/printer_data/logs"
install -d -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/printer_data/gcodes"

# SSH authorized_keys if provided
if [ -n "${KS_SSH_PUBKEY:-}" ]; then
  install -d -m 0700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"
  printf "%s\n" "$KS_SSH_PUBKEY" | install -D -m 0600 /dev/stdin "$HOME_DIR/.ssh/authorized_keys"
  chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.ssh/authorized_keys"
fi
