#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

# Standard project header
source /common.sh; install_cleanup_trap

# ---- Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[moonraker] user $KS_USER missing"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# ---- Minimal prerequisites; installer handles the rest
apt-get update
apt-get install -y --no-install-recommends \
  git curl wget ca-certificates python3-venv python3-dev build-essential libffi-dev

# ---- Ensure Moonraker data path exists (docs layout: ~/printer_data/**)
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  mkdir -p ~/printer_data/{config,logs,gcodes,systemd,comms}
  [ -e ~/printer_data/config/moonraker.conf ] || : > ~/printer_data/config/moonraker.conf
'

# ---- Install Moonraker from source (doc-preferred)
if [ ! -d "$HOME_DIR/moonraker/.git" ]; then
  runuser -u "$KS_USER" -- git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME_DIR/moonraker"
else
  runuser -u "$KS_USER" -- bash -lc 'cd ~/moonraker && git fetch --tags --prune && git reset --hard @{u} || true'
fi

# Use installer; set config path explicitly. Skip systemctl during image build.
bash -lc "
  set -eux
  MOONRAKER_DISABLE_SYSTEMCTL=1 \
  ${HOME_DIR}/moonraker/scripts/install-moonraker.sh \
    -f -c ${HOME_DIR}/printer_data/config/moonraker.conf
"

# ---- Ensure include-based layout for Update Manager fragments
MOON_CFG="${HOME_DIR}/printer_data/config/moonraker.conf"
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
# Add include at END of moonraker.conf so fragments override earlier blocks
if ! grep -qE '^\[include[[:space:]]+update-manager\.d/\*\.conf\]' "${MOON_CFG}"; then
  printf "\n[include update-manager.d/*.conf]\n" >> "${MOON_CFG}"
  chown "${KS_USER}:${KS_USER}" "${MOON_CFG}"
fi

# ---- Make sure the user is in the admin group used by polkit rules
getent group moonraker-admin >/dev/null 2>&1 && usermod -aG moonraker-admin "$KS_USER" || true

# ---- Systemd override with modest resource limits
install -d -m 0755 /etc/systemd/system/moonraker.service.d
cat >/etc/systemd/system/moonraker.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=65536
TasksMax=4096
Nice=-2
IOSchedulingClass=best-effort
IOSchedulingPriority=2
NoNewPrivileges=yes
PrivateTmp=yes
EOF

# ---- Logrotate for moonraker.log
install -D -m 0644 /dev/null /etc/logrotate.d/moonraker
cat >/etc/logrotate.d/moonraker <<EOF
${HOME_DIR}/printer_data/logs/moonraker.log {
    daily
    rotate 7
    size 25M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

# ---- Seed a minimal, safe moonraker.conf if empty
if [ ! -s "$MOON_CFG" ]; then
  install -D -o "$KS_USER" -g "$KS_USER" -m 0644 /dev/null "$MOON_CFG"
  cat >"$MOON_CFG" <<'EOF'
# Minimal Moonraker configuration (seeded by image)
# See: https://moonraker.readthedocs.io/en/latest/configuration/

[server]
host: 0.0.0.0
port: 7125
klippy_uds_address: ~/printer_data/comms/klippy.sock

[authorization]
trusted_clients:
  127.0.0.1
  ::1
  10.0.0.0/8
  172.16.0.0/12
  192.168.0.0/16
  FE80::/10
  FD00::/8
cors_domains:
  https://my.mainsail.xyz
  http://my.mainsail.xyz
  https://app.fluidd.xyz
  http://app.fluidd.xyz
  http://*.local
  http://*.lan

[history]
[octoprint_compat]

# Update Manager fragments are included at the end:
[include update-manager.d/*.conf]
EOF
  chown "$KS_USER:$KS_USER" "$MOON_CFG"
fi

# ---- Queue enablement; try enabling now (safe in chroot)
if [ -w /etc/ks-enable-units.txt ]; then
  grep -qxF "moonraker.service" /etc/ks-enable-units.txt || echo "moonraker.service" >> /etc/ks-enable-units.txt
fi
systemctl_if_exists daemon-reload || true
systemctl_if_exists enable moonraker.service || true

echo_green "[moonraker] installed; include-based Update Manager enabled; override+logrotate applied"
