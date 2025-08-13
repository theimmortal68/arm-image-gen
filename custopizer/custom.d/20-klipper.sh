#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# retry polyfill: usage → retry <attempts> <delay> <cmd...>
type retry >/dev/null 2>&1 || retry() {
  local tries="$1"; local delay="$2"; shift 2
  local n=0
  until "$@"; do
    n=$((n+1))
    [ "$n" -ge "$tries" ] && return 1
    sleep "$delay"
  done
}

KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "User $KS_USER missing"; exit 1; }

retry 4 2 apt-get update
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

# Default printer.cfg if missing
if [ ! -f "$HOME_DIR/printer_data/config/printer.cfg" ]; then
  cat >"$HOME_DIR/printer_data/config/printer.cfg" <<'EOF'
# Minimal Klipper config placeholder
# Add your MCU and kinematics here
[include mainsail.cfg]
EOF
  chown "$KS_USER:$KS_USER" "$HOME_DIR/printer_data/config/printer.cfg"
fi

# Systemd service
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

install -d /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/klipper.service /etc/systemd/system/multi-user.target.wants/klipper.service
systemctl_if_exists daemon-reload || true

echo_green "[klipper] installed"
