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
is_in_apt git && apt-get install -y --no-install-recommends git || true

if [ ! -d "$HOME_DIR/sonar/.git" ]; then
  sudo -u "$KS_USER" git clone --depth=1 https://github.com/mainsail-crew/sonar.git "$HOME_DIR/sonar"
else
  sudo -u "$KS_USER" git -C "$HOME_DIR/sonar" fetch --depth=1 origin || true
  sudo -u "$KS_USER" git -C "$HOME_DIR/sonar" reset --hard origin/master || true
fi

# Add update_manager entry
MOON_CFG="$HOME_DIR/printer_data/config/moonraker.conf"
touch "$MOON_CFG"; chown "$KS_USER:$KS_USER" "$MOON_CFG"
if ! grep -q "^\[update_manager client sonar\]" "$MOON_CFG"; then
  cat >>"$MOON_CFG" <<'EOF'

[update_manager client sonar]
type: git_repo
path: ~/sonar
origin: https://github.com/mainsail-crew/sonar.git
managed_services: moonraker
EOF
fi

echo_green "[sonar] installed (managed via Moonraker updater)"
