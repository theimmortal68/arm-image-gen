#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "User $KS_USER missing"; exit 1; }

retry 4 2 apt-get update
is_in_apt git && apt-get install -y --no-install-recommends git || true

# Clone/update moonraker-timelapse
if [ ! -d "$HOME_DIR/moonraker-timelapse/.git" ]; then
  sudo -u "$KS_USER" git clone --depth=1 https://github.com/mainsail-crew/moonraker-timelapse.git "$HOME_DIR/moonraker-timelapse"
else
  sudo -u "$KS_USER" git -C "$HOME_DIR/moonraker-timelapse" fetch --depth=1 origin || true
  sudo -u "$KS_USER" git -C "$HOME_DIR/moonraker-timelapse" reset --hard origin/master || true
fi

# Add update_manager entry
MOON_CFG="$HOME_DIR/printer_data/config/moonraker.conf"
touch "$MOON_CFG"; chown "$KS_USER:$KS_USER" "$MOON_CFG"
if ! grep -q "^\[update_manager client timelapse\]" "$MOON_CFG"; then
  cat >>"$MOON_CFG" <<'EOF'

[update_manager client timelapse]
type: git_repo
path: ~/moonraker-timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
managed_services: moonraker
EOF
fi

echo_green "[timelapse] installed (managed via Moonraker updater)"
