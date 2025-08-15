#!/usr/bin/env bash
set -Eeuo pipefail
set -x
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

# /files is bind-mounted by CustoPiZer. Only copy what’s present, and gate Pi-only bits.
has_pi_repo() {
  grep -q 'archive\.raspberrypi\.com' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null
}
is_pi_image() {
  [ -e /etc/default/raspberrypi-kernel ] && return 0
  grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null && return 0
  return 1
}

# ---- APT pins (only if the Pi repo is active) ----
if [ -d /files/etc/apt/preferences.d ]; then
  if has_pi_repo; then
    install -d /etc/apt/preferences.d
    cp -a /files/etc/apt/preferences.d/* /etc/apt/preferences.d/ || true
    echo "[files] installed APT pins (raspberrypi.com detected)"
  else
    echo "[files] skipping APT pins (raspberrypi.com not in sources)"
  fi
fi

# ---- Udev rules ----
if [ -d /files/etc/udev/rules.d ]; then
  install -d /etc/udev/rules.d
  cp -a /files/etc/udev/rules.d/* /etc/udev/rules.d/ || true
  echo "[files] installed udev rules"
fi

# ---- Logrotate snippets ----
if [ -d /files/etc/logrotate.d ]; then
  install -d /etc/logrotate.d
  cp -a /files/etc/logrotate.d/* /etc/logrotate.d/ || true
  echo "[files] installed logrotate configs"
fi

# ---- Systemd unit files (enable later in 99-enable-units) ----
if [ -d /files/etc/systemd/system ]; then
  install -d /etc/systemd/system
  cp -a /files/etc/systemd/system/* /etc/systemd/system/ || true
  echo "[files] installed systemd units"
fi

# ---- Boot firmware append (Pi only) ----
if [ -f /files/boot/firmware/config.txt.append ] \
   && [ -f /boot/firmware/config.txt ] \
   && is_pi_image; then
  cat /files/boot/firmware/config.txt.append >> /boot/firmware/config.txt
  echo "[files] appended to /boot/firmware/config.txt"
else
  echo "[files] skipping /boot/firmware/config.txt append (non-Pi or file missing)"
fi

# ---- Any other static payloads you’ve staged ----
# Examples (copy if present; harmless no-ops otherwise)
for d in etc/default etc/sysctl.d usr/local/bin usr/local/lib; do
  if [ -d "/files/$d" ]; then
    install -d "/$d"
    cp -a "/files/$d/"* "/$d/" || true
    echo "[files] installed /$d payloads"
  fi
done

echo "[files] stage complete"
