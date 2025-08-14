#!/bin/bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Detect user
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[klipper] user $KS_USER missing"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# Safety nets for git & python venv (should already be present from base layer)
is_in_apt git && ! is_installed git && apt-get update && apt-get install -y --no-install-recommends git ca-certificates || true
is_in_apt python3-venv || { echo_red "[klipper] python3-venv missing"; exit 1; }

# Clone/update Klipper
if [ ! -d "$HOME_DIR/klipper/.git" ]; then
  sudo -u "$KS_USER" git clone --depth=1 https://github.com/Klipper3d/klipper.git "$HOME_DIR/klipper"
else
  sudo -u "$KS_USER" git -C "$HOME_DIR/klipper" fetch --depth=1 origin || true
  sudo -u "$KS_USER" git -C "$HOME_DIR/klipper" reset --hard origin/master || true
fi

# Python venv
if [ ! -d "$HOME_DIR/klippy-env" ]; then
  sudo -u "$KS_USER" python3 -m venv "$HOME_DIR/klippy-env"
fi
sudo -u "$KS_USER" "$HOME_DIR/klippy-env/bin/pip" install -U pip wheel setuptools
sudo -u "$KS_USER" "$HOME_DIR/klippy-env/bin/pip" install -r "$HOME_DIR/klipper/scripts/klippy-requirements.txt"

# Default config
install -d -o "$KS_USER" -g "$KS_USER" "$HOME_DIR/printer_data/config" "$HOME_DIR/printer_data/logs"
if [ ! -f "$HOME_DIR/printer_data/config/printer.cfg" ]; then
  cat >"$HOME_DIR/printer_data/config/printer.cfg" <<'EOF'
[include mainsail.cfg]
EOF
  chown "$KS_USER:$KS_USER" "$HOME_DIR/printer_data/config/printer.cfg"
fi

# Service
cat >/etc/systemd/system/klipper.service <<EOF
[Unit]
Description=Klipper 3D printer firmware
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=$KS_USER
ExecStart=$HOME_DIR/klippy-env/bin/python $HOME_DIR/klipper/klippy/klippy.py -l $HOME_DIR/printer_data/logs/klippy.log -a /tmp/klippy_uds $HOME_DIR/printer_data/config/printer.cfg
Restart=always
[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/klipper.service /etc/systemd/system/multi-user.target.wants/klipper.service || true
systemctl_if_exists daemon-reload || true
echo_green "[klipper] installed"
