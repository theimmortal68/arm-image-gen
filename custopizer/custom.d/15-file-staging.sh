#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

[ -d /files ] || { echo "[files] no /files mount; nothing to stage"; exit 0; }

# 1) Enable-units list (used by 99-enable-units.sh)
if [ -f /files/etc/ks-enable-units.txt ]; then
  install -Dm0644 /files/etc/ks-enable-units.txt /etc/ks-enable-units.txt
  echo "[files] installed /etc/ks-enable-units.txt"
fi

# 2) Crowsnest config (optional)
if [ -f /files/etc/crowsnest.conf ]; then
  install -Dm0644 /files/etc/crowsnest.conf /etc/crowsnest.conf
  echo "[files] installed /etc/crowsnest.conf"
fi

# 3) Nginx site (optional)
if [ -f /files/etc/nginx/sites-available/mainsail ]; then
  install -Dm0644 /files/etc/nginx/sites-available/mainsail /etc/nginx/sites-available/mainsail
  install -d /etc/nginx/sites-enabled
  ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
  echo "[files] installed nginx site mainsail"
fi

# 4) Append to /boot/firmware/config.txt (optional)
if [ -f /files/boot/firmware/config.txt.append ]; then
  install -d /boot/firmware
  cat /files/boot/firmware/config.txt.append >> /boot/firmware/config.txt
  echo "[files] appended to /boot/firmware/config.txt"
fi

# 5) User SSH keys (optional)
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
if [ -n "${KS_USER:-}" ] && [ -f "/files/home/${KS_USER}/.ssh/authorized_keys" ]; then
  install -d -m 0700 -o "$KS_USER" -g "$KS_USER" "/home/${KS_USER}/.ssh"
  install -m 0600 -o "$KS_USER" -g "$KS_USER" "/files/home/${KS_USER}/.ssh/authorized_keys" "/home/${KS_USER}/.ssh/authorized_keys"
  echo "[files] installed authorized_keys for ${KS_USER}"
fi

echo "[files] staging complete"
