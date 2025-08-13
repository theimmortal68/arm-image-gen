#!/usr/bin/env bash
# Crowsnest install & wiring (Bookworm-safe, Pi/Armbian friendly)
# - Uses camera-streamer by default on non-Pi5, ustreamer on Pi5 (Bookworm note).
# - Adds Moonraker update_manager entry.
# - Uses common.sh helpers where appropriate.

set -x
set -e
export LC_ALL=C

source /common.sh
install_cleanup_trap

KS_USER="${KS_USER:-pi}"
CN_GIT_URL="https://github.com/mainsail-crew/crowsnest.git"
CN_DEST="/opt/crowsnest"
BIN_DST="/usr/local/bin/crowsnest"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6 || true)"
[ -n "$HOME_DIR" ] || { echo_red "User $KS_USER missing"; exit 1; }
CFG_DIR="$HOME_DIR/printer_data/config"
LOG_DIR="$HOME_DIR/printer_data/logs"

# Ensure user & access to /dev/video*
if ! id -u "$KS_USER" >/dev/null 2>&1; then
  useradd -m -G sudo,video,plugdev,dialout "$KS_USER"
fi
usermod -aG video "$KS_USER" || true

export DEBIAN_FRONTEND=noninteractive
apt-get update

# Only install packages that exist in apt (defensive)
is_in_apt git && apt-get install -y --no-install-recommends git || true
is_in_apt curl && apt-get install -y --no-install-recommends curl || true
is_in_apt ca-certificates && apt-get install -y --no-install-recommends ca-certificates || true
is_in_apt crudini && apt-get install -y --no-install-recommends crudini || true
is_in_apt ffmpeg && apt-get install -y --no-install-recommends ffmpeg || true
is_in_apt v4l-utils && apt-get install -y --no-install-recommends v4l-utils || true
# Try Pi camera helpers if available (no-op on Armbian if missing)
is_in_apt rpicam-apps-lite && apt-get install -y --no-install-recommends rpicam-apps-lite || true
is_in_apt libcamera-apps && apt-get install -y --no-install-recommends libcamera-apps || true

# Fetch/refresh crowsnest
if [ ! -d "$CN_DEST/.git" ]; then
  mkdir -p "$(dirname "$CN_DEST")"
  git clone --depth=1 "$CN_GIT_URL" "$CN_DEST"
else
  git -C "$CN_DEST" fetch --depth=1 origin || true
  git -C "$CN_DEST" reset --hard origin/master || true
fi
install -Dm0755 "$CN_DEST/crowsnest" "$BIN_DST"

# Default config
install -d "$CFG_DIR" "$LOG_DIR"
if [ ! -f "$CFG_DIR/crowsnest.conf" ]; then
  cat >"$CFG_DIR/crowsnest.conf" <<'EOF'
[crowsnest]
log_path: ~/printer_data/logs/crowsnest.log

[cam webcam]
# Backend is set below (Pi 5 => ustreamer, others => camera-streamer)
mode: auto
device: auto
enabled: true
EOF
  chown "$KS_USER:$KS_USER" "$CFG_DIR/crowsnest.conf"
fi

# Moonraker update_manager entry (idempotent)
MOON_CFG="$CFG_DIR/moonraker.conf"
touch "$MOON_CFG"
if ! grep -q "^\[update_manager client crowsnest\]" "$MOON_CFG"; then
  cat >>"$MOON_CFG" <<'EOF'

[update_manager client crowsnest]
type: git_repo
path: ~/crowsnest
origin: https://github.com/mainsail-crew/crowsnest.git
install_script: tools/pkglist.sh
managed_services: crowsnest
EOF
  chown "$KS_USER:$KS_USER" "$MOON_CFG" || true
fi

# systemd unit + enable (use helper so it’s safe under CustoPiZer policy)
cat >/etc/systemd/system/crowsnest.service <<EOF
[Unit]
Description=Crowsnest webcam service
After=network-online.target
Wants=network-online.target

[Service]
User=$KS_USER
Group=video
Environment=CROWSNEST_CONFIG=$CFG_DIR/crowsnest.conf
ExecStart=$BIN_DST -c \$CROWSNEST_CONFIG
Restart=always

[Install]
WantedBy=multi-user.target
EOF

install -d /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/crowsnest.service \
  /etc/systemd/system/multi-user.target.wants/crowsnest.service
systemctl_if_exists daemon-reload || true

# Backend choice:
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
if echo "$MODEL" | grep -q "Raspberry Pi 5"; then
  crudini --set "$CFG_DIR/crowsnest.conf" "cam webcam" mode "ustreamer" || true
else
  crudini --set "$CFG_DIR/crowsnest.conf" "cam webcam" mode "camera-streamer" || true
fi

# Ownerships
chown -R "$KS_USER:$KS_USER" "$HOME_DIR/printer_data" || true

echo_green "[crowsnest] installed and configured"
