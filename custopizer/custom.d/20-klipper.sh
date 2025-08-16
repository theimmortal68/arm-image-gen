#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

# Keep the project’s standard header
source /common.sh; install_cleanup_trap

# --- Detect target user/home ---
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[klipper] user $KS_USER missing"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo_green "[klipper] installing host-side dependencies"

# Build/Python toolchain + numeric stack (your request) + helpers
check_install_pkgs \
  git python3-venv python3-dev build-essential gcc g++ make libffi-dev \
  python3-numpy python3-matplotlib libatlas3-base libatlas-base-dev libgfortran5 \
  ca-certificates curl pkg-config

# Make sure the runtime groups are set (serial/GPIO/I2C/SPI/video/render)
for grp in dialout tty input video render gpio i2c spi; do
  getent group "$grp" >/dev/null 2>&1 && usermod -aG "$grp" "$KS_USER" || true
done

# --- Create data folders per Moonraker layout ---
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  mkdir -p ~/printer_data/{config,logs,gcodes,systemd,comms}
  [ -e ~/printer_data/config/printer.cfg ] || : > ~/printer_data/config/printer.cfg
'

# --- Clone/refresh Kalico (Klipper fork) ---
# Repo/branch requested: KalicoCrew/kalico, bleeding-edge-v2
if [ ! -d "$HOME_DIR/klipper/.git" ]; then
  echo_green "[klipper] cloning Kalico (bleeding-edge-v2)"
  runuser -u "$KS_USER" -- git clone --depth=1 --branch bleeding-edge-v2 \
    https://github.com/KalicoCrew/kalico.git "$HOME_DIR/klipper"
else
  echo_green "[klipper] refreshing Kalico (bleeding-edge-v2)"
  runuser -u "$KS_USER" -- bash -lc '
    set -eux
    cd ~/klipper
    # ensure origin points to Kalico
    if ! git remote get-url origin | grep -q "KalicoCrew/kalico"; then
      git remote set-url origin https://github.com/KalicoCrew/kalico.git
    fi
    git fetch --tags --prune origin
    git checkout -B bleeding-edge-v2 origin/bleeding-edge-v2
    git reset --hard origin/bleeding-edge-v2
  '
fi

# --- Python venv for Klipper ---
if [ ! -d "$HOME_DIR/klippy-env" ]; then
  runuser -u "$KS_USER" -- python3 -m venv "$HOME_DIR/klippy-env"
fi

# Upgrade pip/setuptools/wheel and install requirements + latest numpy
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  ~/klippy-env/bin/python -m pip install --upgrade pip setuptools wheel
  # kalico uses the same requirements file path as klipper
  ~/klippy-env/bin/pip install -r ~/klipper/scripts/klippy-requirements.txt
  ~/klippy-env/bin/pip install --upgrade numpy
'

# --- Precompile Python and build the C helper for performance ---
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  cd ~/klipper
  ~/klippy-env/bin/python -m compileall -q -j 0 klippy
  ~/klippy-env/bin/python klippy/chelper/__init__.py
'

# --- Seed Moonraker-required Klipper config bits if missing ---
PRNCFG="${HOME_DIR}/printer_data/config/printer.cfg"
# Add bare sections only if not already present
append_if_missing() {
  sec="$1"
  if ! grep -Eq "^\[$(printf %s "$sec" | sed "s/[][\^$.*/]/\\&/g")\]" "$PRNCFG"; then
    printf "\n[%s]\n" "$sec" >> "$PRNCFG"
  fi
}
# Required by Moonraker for full functionality:
#   [pause_resume], [display_status], [virtual_sdcard] with path to ~/printer_data/gcodes
append_if_missing "pause_resume"
append_if_missing "display_status"
if ! grep -Eq "^\[virtual_sdcard\]" "$PRNCFG"; then
  cat >> "$PRNCFG" <<'EOF'

[virtual_sdcard]
path: ~/printer_data/gcodes
EOF
fi
chown "$KS_USER:$KS_USER" "$PRNCFG"

# --- Systemd unit for Klipper (points to data_path log + socket) ---
install -d -m 0755 /etc/systemd/system
cat >/etc/systemd/system/klipper.service <<EOF
[Unit]
Description=Kalico (Klipper fork) Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${KS_USER}
ExecStartPre=/usr/bin/env bash -lc 'rm -f ${HOME_DIR}/printer_data/comms/klippy.sock || true'
ExecStart=${HOME_DIR}/klippy-env/bin/python ${HOME_DIR}/klipper/klippy/klippy.py \
  -l ${HOME_DIR}/printer_data/logs/klippy.log \
  -a ${HOME_DIR}/printer_data/comms/klippy.sock \
  ${HOME_DIR}/printer_data/config/printer.cfg
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# --- Resource limits / hardening (conservative) ---
install -d -m 0755 /etc/systemd/system/klipper.service.d
cat >/etc/systemd/system/klipper.service.d/override.conf <<'EOF'
[Service]
# Reliability & resource ceilings
LimitNOFILE=65536
TasksMax=4096
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=2

# Keep hardening modest to avoid blocking serial/gpio access
NoNewPrivileges=yes
PrivateTmp=yes
EOF

# --- Logrotate for klippy.log ---
install -D -m 0644 /dev/null /etc/logrotate.d/klippy
cat >/etc/logrotate.d/klippy <<EOF
${HOME_DIR}/printer_data/logs/klippy.log {
    daily
    rotate 7
    size 50M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

# Queue for enabling later and try enabling now (safe in chroot)
if [ -w /etc/ks-enable-units.txt ]; then
  grep -qxF "klipper.service" /etc/ks-enable-units.txt || echo "klipper.service" >> /etc/ks-enable-units.txt
fi
systemctl_if_exists daemon-reload || true
systemctl_if_exists enable klipper.service || true

# --- Moonraker Update Manager entry ---
MOON_CFG="${HOME_DIR}/printer_data/config/moonraker.conf"
if [ -e "$MOON_CFG" ]; then
  # Replace any existing "klipper" block with our Kalico settings
  TMP="$(mktemp)"
  awk '
    BEGIN{skip=0}
    /^\[update_manager[[:space:]]+klipper\]/{skip=1; next}
    skip && /^\[/{skip=0}
    !skip{print}
  ' "$MOON_CFG" > "$TMP"
  printf "\n" >> "$TMP"
  cat >> "$TMP" <<EOF
[update_manager klipper]
type: git_repo
path: ~/klipper
origin: https://github.com/KalicoCrew/kalico.git
primary_branch: bleeding-edge-v2
managed_services: klipper
EOF
  install -m 0644 -o "$KS_USER" -g "$KS_USER" "$TMP" "$MOON_CFG"
  rm -f "$TMP"
fi

echo_green "[klipper] Kalico installed, compiled, configured; systemd+logrotate ready"
