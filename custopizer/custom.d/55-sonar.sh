#!/bin/bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Detect user / moonraker venv
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[sonar] user $KS_USER missing"; exit 1; }

VENV="$HOME_DIR/moonraker-env"
if [ ! -x "$VENV/bin/pip" ]; then
  echo_red "[sonar] moonraker venv not found at $VENV"
  exit 1
fi

# Try pip first; fallback to git
if "$VENV/bin/pip" install -U sonar 2>/tmp/sonar.err; then
  echo_green "[sonar] installed via pip"
else
  echo_red "[sonar] pip package not available, trying git"
  if [ ! -d "$HOME_DIR/sonar/.git" ]; then
    sudo -u "$KS_USER" git clone --depth=1 https://github.com/mainsail-crew/sonar.git "$HOME_DIR/sonar"
  else
    sudo -u "$KS_USER" git -C "$HOME_DIR/sonar" fetch --depth=1 origin || true
    sudo -u "$KS_USER" git -C "$HOME_DIR/sonar" reset --hard origin/master || true
  fi
  "$VENV/bin/pip" install -U pip wheel setuptools
  "$VENV/bin/pip" install "$HOME_DIR/sonar" || { echo_red "[sonar] git install failed"; cat /tmp/sonar.err || true; exit 1; }
fi

echo_green "[sonar] installed"
