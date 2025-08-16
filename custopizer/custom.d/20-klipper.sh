#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# --- Detect target user/home ---
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[klipper] user $KS_USER missing"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo_green "[klipper] installing host-side dependencies"
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  git python3-venv python3-dev build-essential gcc g++ make libffi-dev \
  python3-numpy python3-matplotlib libatlas3-base libatlas-base-dev libgfortran5 \
  ca-certificates curl pkg-config
rm -rf /var/lib/apt/lists/*

# Group memberships for hardware access
for grp in dialout tty input video render gpio i2c spi; do
  getent group "$grp" >/dev/null 2>&1 && usermod -aG "$grp" "$KS_USER" || true
done

# Data folders per Moonraker layout
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  mkdir -p ~/printer_data/{config,logs,gcodes,systemd,comms}
  [ -e ~/printer_data/config/printer.cfg ] || : > ~/printer_data/config/printer.cfg
'

# Clone/refresh Kalico (Klipper fork)
if [ ! -d "$HOME_DIR/klipper/.git" ]; then
  echo_green "[klipper] cloning Kalico (bleeding-edge-v2)"
  runuser -u "$KS_USER" -- git clone --depth=1 --branch bleeding-edge-v2 \
    https://github.com/KalicoCrew/kalico.git "$HOME_DIR/klipper"
else
  echo_green "[klipper] refreshing Kalico (bleeding-edge-v2)"
  runuser -u "$KS_USER" -- bash -lc '
    set -eux
    cd ~/klipper
    if ! git remote get-url origin | grep -q "KalicoCrew/kalico"; then
      git remote set-url origin https://github.com/KalicoCrew/kalico.git
    fi
    git fetch --tags --prune origin
    git checkout -B bleeding-edge-v2 origin/bleeding-edge-v2
    git reset --hard origin/bleeding-edge-v2
  '
fi

# Python venv + requirements (latest numpy as requested)
if [ ! -d "$HOME_DIR/klippy-env" ]; then
  runuser -u "$KS_USER" -- python3 -m venv "$HOME_DIR/klippy-env"
fi
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  ~/klippy-env/bin/python -m pip install --upgrade pip setuptools wheel
  ~/klippy-env/bin/pip install -r ~/klipper/scripts/klippy-requirements.txt
  ~/klippy-env/bin/pip install --upgrade numpy
'

# Precompile Python & build C helper
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  cd ~/klipper
  ~/klippy-env/bin/python -m compileall -q -j 0 klippy
  ~/klippy-env/bin/python klippy/chelper/__init__.py
'

# Systemd unit
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

# Resource limits / hardening
install -d -m 0755 /etc/systemd/system/klipper.service.d
cat >/etc/systemd/system/klipper.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=65536
TasksMax=4096
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=2
NoNewPrivileges=yes
PrivateTmp=yes
EOF

# Logrotate
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

# Seed Moonraker-required config bits
PRNCFG="${HOME_DIR}/printer_data/config/printer.cfg"
append_if_missing() {
  sec="$1"
  if ! grep -Eq "^\[$(printf %s "$sec" | sed "s/[][\^$.*/]/\\&/g")\]" "$PRNCFG"; then
    printf "\n[%s]\n" "$sec" >> "$PRNCFG"
  fi
}
append_if_missing "pause_resume"
append_if_missing "display_status"
if ! grep -Eq "^\[virtual_sdcard\]" "$PRNCFG"; then
  cat >> "$PRNCFG" <<'EOF'

[virtual_sdcard]
path: ~/printer_data/gcodes
EOF
fi
chown "$KS_USER:$KS_USER" "$PRNCFG"

# Write Update Manager fragment instead of editing moonraker.conf
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
FRAG="${UMDIR}/klipper.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
cat > "${FRAG}" <<'EOF'
[update_manager klipper]
type: git_repo
path: ~/klipper
origin: https://github.com/KalicoCrew/kalico.git
primary_branch: bleeding-edge-v2
managed_services: klipper
EOF
chown "${KS_USER}:${KS_USER}" "${FRAG}"
chmod 0644 "${FRAG}"

# Enable queue & daemon-reload
if [ -w /etc/ks-enable-units.txt ]; then
  grep -qxF "klipper.service" /etc/ks-enable-units.txt || echo "klipper.service" >> /etc/ks-enable-units.txt
fi
systemctl_if_exists daemon-reload || true
systemctl_if_exists enable klipper.service || true

echo_green "[klipper] Kalico installed; compiled; service+limits+logrotate configured; UM fragment written"
