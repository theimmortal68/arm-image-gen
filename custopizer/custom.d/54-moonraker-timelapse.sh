#!/bin/bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Detect user / moonraker venv
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[timelapse] user $KS_USER missing"; exit 1; }

VENV="$HOME_DIR/moonraker-env"
if [ ! -x "$VENV/bin/pip" ]; then
  echo_red "[timelapse] moonraker venv not found at $VENV"
  exit 1
fi

# Prefer pip package if available; else fallback to git install
if "$VENV/bin/pip" install -U moonraker-timelapse; then
  echo_green "[timelapse] installed via pip"
else
  echo_red "[timelapse] pip package missing, trying git"
  if [ ! -d "$HOME_DIR/moonraker-timelapse/.git" ]; then
    sudo -u "$KS_USER" git clone --depth=1 https://github.com/mainsail-crew/moonraker-timelapse.git "$HOME_DIR/moonraker-timelapse"
  else
    sudo -u "$KS_USER" git -C "$HOME_DIR/moonraker-timelapse" fetch --depth=1 origin || true
    sudo -u "$KS_USER" git -C "$HOME_DIR/moonraker-timelapse" reset --hard origin/master || true
  fi
  "$VENV/bin/pip" install -U pip wheel setuptools
  "$VENV/bin/pip" install "$HOME_DIR/moonraker-timelapse" || { echo_red "[timelapse] git install failed"; exit 1; }
fi

echo_green "[timelapse] installed"
