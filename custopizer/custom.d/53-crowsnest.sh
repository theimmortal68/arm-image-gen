#!/bin/bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

export DEBIAN_FRONTEND=noninteractive

# Ensure basic deps (most from base layer; these are belt & suspenders)
for p in git curl jq v4l-utils ffmpeg ustreamer; do
  is_in_apt "$p" && ! is_installed "$p" && apt-get update && apt-get install -y --no-install-recommends "$p" || true
done

# Install Crowsnest from upstream git
CN_DIR="/opt/crowsnest"
if [ ! -d "$CN_DIR/.git" ]; then
  git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git "$CN_DIR"
else
  git -C "$CN_DIR" fetch --depth=1 origin || true
  git -C "$CN_DIR" reset --hard origin/master || true
fi

# Detect runnable entry
ENTRY=""
for cand in "$CN_DIR/crowsnest" "$CN_DIR/crowsnest.sh" "$CN_DIR/crowsnest.py"; do
  if [ -f "$cand" ]; then ENTRY="$cand"; break; fi
done
[ -n "$ENTRY" ] || { echo_red "[crowsnest] could not find entry script in $CN_DIR"; ls -l "$CN_DIR" || true; exit 1; }
chmod +x "$ENTRY"
ln -sf "$ENTRY" /usr/local/bin/crowsnest

# Default config
install -d /etc
if [ ! -s /etc/crowsnest.conf ]; then
  cat >/etc/crowsnest.conf <<'EOF'
# Minimal Crowsnest configuration
[global]
log_path: /var/log/crowsnest
# Example cameras (adjust device paths / resolution as needed)
#[cam rpi-libcamera]
#mode: camera-streamer
#device: /base/soc/i2c0mux/i2c@1/imx708@1a
#resolution: 1280x720
#max_fps: 30
#port: 8080
[cam uvc]
mode: ustreamer
device: /dev/video0
resolution: 1280x720
max_fps: 30
port: 8081
EOF
fi
install -d /var/log/crowsnest

# Systemd service
cat >/etc/systemd/system/crowsnest.service <<'EOF'
[Unit]
Description=Crowsnest Camera Manager
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/crowsnest -c /etc/crowsnest.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/crowsnest.service /etc/systemd/system/multi-user.target.wants/crowsnest.service || true
systemctl_if_exists daemon-reload || true
echo_green "[crowsnest] installed"
