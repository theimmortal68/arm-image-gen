#!/bin/bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Detect user
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[moonraker] user $KS_USER missing"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
is_in_apt git && ! is_installed git && apt-get update && apt-get install -y --no-install-recommends git ca-certificates || true
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

# moonraker.conf basics
MOON_CFG="$HOME_DIR/printer_data/config/moonraker.conf"
install -d "$(dirname "$MOON_CFG")"
touch "$MOON_CFG"; chown "$KS_USER:$KS_USER" "$MOON_CFG"
grep -q '^\[server\]' "$MOON_CFG" || cat >>"$MOON_CFG" <<'EOF'

[server]
host: 0.0.0.0
port: 7125
EOF
grep -q '^\[authorization\]' "$MOON_CFG" || echo -e "\n[authorization]\nenabled: true\n" >>"$MOON_CFG"
grep -q '^\[octoprint_compat\]' "$MOON_CFG" || echo -e "\n[octoprint_compat]\n" >>"$MOON_CFG"

# Update manager entries
if ! grep -q "^\[update_manager klipper\]" "$MOON_CFG"; then
  cat >>"$MOON_CFG" <<'EOF'

[update_manager klipper]
type: git_repo
path: ~/klipper
origin: https://github.com/Klipper3d/klipper.git
managed_services: klipper
EOF
fi

# (Optional) plugin entries to allow in-UI install/update
if ! grep -q "^\[update_manager moonraker-timelapse\]" "$MOON_CFG"; then
  cat >>"$MOON_CFG" <<'EOF'

[update_manager moonraker-timelapse]
type: git_repo
path: ~/moonraker-timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
managed_services: moonraker
primary_branch: master
EOF
fi

if ! grep -q "^\[update_manager sonar\]" "$MOON_CFG"; then
  cat >>"$MOON_CFG" <<'EOF'

[update_manager sonar]
type: git_repo
path: ~/sonar
origin: https://github.com/mainsail-crew/sonar.git
managed_services: moonraker
primary_branch: master
EOF
fi

# Service
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
ln -sf /etc/systemd/system/moonraker.service /etc/systemd/system/multi-user.target.wants/moonraker.service || true
systemctl_if_exists daemon-reload || true
echo_green "[moonraker] installed"
