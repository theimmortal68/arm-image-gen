#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

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
is_in_apt python3-venv || { echo_red "[moonraker] python3-venv missing"; exit 1; }

# Clone/update Moonraker
if [ ! -d "$HOME_DIR/moonraker/.git" ]; then
  sudo -u "$KS_USER" git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME_DIR/moonraker"
else
  sudo -u "$KS_USER" git -C "$HOME_DIR/moonraker" fetch --depth=1 origin || true
  sudo -u "$KS_USER" git -C "$HOME_DIR/moonraker" reset --hard origin/master || true
fi

# venv
if [ ! -d "$HOME_DIR/moonraker-env" ]; then
  sudo -u "$KS_USER" python3 -m venv "$HOME_DIR/moonraker-env"
fi
sudo -u "$KS_USER" "$HOME_DIR/moonraker-env/bin/pip" install -U pip wheel setuptools
sudo -u "$KS_USER" "$HOME_DIR/moonraker-env/bin/pip" install -r "$HOME_DIR/moonraker/scripts/moonraker-requirements.txt"

# Minimal moonraker.conf (append-only if file exists)
MOON_CFG="$HOME_DIR/printer_data/config/moonraker.conf"
touch "$MOON_CFG"
chown "$KS_USER:$KS_USER" "$MOON_CFG"

# Ensure core sections exist
grep -q '^\[server\]' "$MOON_CFG" || cat >>"$MOON_CFG" <<'EOF'

[server]
host: 0.0.0.0
port: 7125
EOF

grep -q '^\[authorization\]' "$MOON_CFG" || cat >>"$MOON_CFG" <<'EOF'

[authorization]
enabled: true
EOF

grep -q '^\[octoprint_compat\]' "$MOON_CFG" || echo -e "\n[octoprint_compat]\n" >>"$MOON_CFG"

# Update manager entries
add_um() {
  local header="$1"; shift
  if ! grep -q "^\[$header\]" "$MOON_CFG"; then
    echo >>"$MOON_CFG"
    echo "[$header]" >>"$MOON_CFG"
    cat >>"$MOON_CFG"
  fi
}

add_um "update_manager mainsail" <<'EOF'
type: web
repo: mainsail-crew/mainsail
path: ~/mainsail
EOF

add_um "update_manager klipper" <<'EOF'
type: git_repo
path: ~/klipper
origin: https://github.com/Klipper3d/klipper.git
managed_services: klipper
EOF

# crowsnest updater is also added in 53-crowsnest.sh; keep it idempotent.

# Systemd service
cat >/etc/systemd/system/moonraker.service <<EOF
[Unit]
Description=Moonraker API Server
After=network-online.target klipper.service
Wants=network-online.target

[Service]
User=$KS_USER
ExecStart=$HOME_DIR/moonraker-env/bin/python $HOME_DIR/moonraker/moonraker/moonraker.py -c $MOON_CFG
Restart=always

[Install]
WantedBy=multi-user.target
EOF

install -d /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/moonraker.service /etc/systemd/system/multi-user.target.wants/moonraker.service
systemctl_if_exists daemon-reload || true

echo_green "[moonraker] installed"
