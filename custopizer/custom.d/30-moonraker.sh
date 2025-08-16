#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

# Standard project header
source /common.sh; install_cleanup_trap

# ---- Target user/home (same convention as your other scripts)
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[moonraker] user $KS_USER missing"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# ---- Minimal prerequisites; installer handles the rest
apt-get update
apt-get install -y --no-install-recommends \
  git curl wget ca-certificates python3-venv python3-dev build-essential libffi-dev

# ---- Ensure Moonraker data path exists (matches docs: ~/printer_data/**)
runuser -u "$KS_USER" -- bash -lc '
  set -eux
  mkdir -p ~/printer_data/{config,logs,gcodes,systemd,comms}
  # create empty config if missing; installer can also create it
  [ -e ~/printer_data/config/moonraker.conf ] || : > ~/printer_data/config/moonraker.conf
'

# ---- Install Moonraker "from source" (doc-preferred for bleeding edge / extensions)
#      cd ~ ; git clone https://github.com/Arksine/moonraker.git ; ~/moonraker/scripts/install-moonraker.sh
if [ ! -d "$HOME_DIR/moonraker/.git" ]; then
  runuser -u "$KS_USER" -- git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME_DIR/moonraker"
else
  runuser -u "$KS_USER" -- bash -lc 'cd ~/moonraker && git fetch --tags --prune && git reset --hard @{u} || true'
fi

# In image build/chroot we don’t want systemctl actions; ask installer to skip them (-z).
# Also install Python speedups (-s) per docs.
bash -lc "
  set -eux
  MOONRAKER_DISABLE_SYSTEMCTL=1 \
  ${HOME_DIR}/moonraker/scripts/install-moonraker.sh -z -s
"

# ---- Make sure the user is in the admin group used by polkit rules
getent group moonraker-admin >/dev/null 2>&1 && usermod -aG moonraker-admin "$KS_USER" || true

# ---- Systemd override with modest resource limits (keeps serial responsive)
install -d -m 0755 /etc/systemd/system/moonraker.service.d
cat >/etc/systemd/system/moonraker.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=65536
TasksMax=4096
Nice=-2
IOSchedulingClass=best-effort
IOSchedulingPriority=2

# Keep hardening modest; Moonraker needs device/network access
NoNewPrivileges=yes
PrivateTmp=yes
EOF

# ---- Logrotate for moonraker.log (align with ~/printer_data layout)
install -D -m 0644 /dev/null /etc/logrotate.d/moonraker
cat >/etc/logrotate.d/moonraker <<EOF
${HOME_DIR}/printer_data/logs/moonraker.log {
    daily
    rotate 7
    size 25M
    missingok
    notifempty
