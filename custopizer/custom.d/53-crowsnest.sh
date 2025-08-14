#!/bin/bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

export DEBIAN_FRONTEND=noninteractive

# Ensure basic deps (best-effort; ignore if some not available)
apt-get update
apt-get install -y --no-install-recommends git curl jq v4l-utils ffmpeg ustreamer python3

# Install Crowsnest from upstream git
CN_DIR="/opt/crowsnest"
if [ ! -d "$CN_DIR/.git" ]; then
  git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git "$CN_DIR"
else
  git -C "$CN_DIR" fetch --depth=1 origin
  git -C "$CN_DIR" reset --hard origin/$(git -C "$CN_DIR" rev-parse --abbrev-ref HEAD)
fi

# Install entrypoint wrapper into PATH
ENTRY="/usr/local/bin/crowsnest"
if [ -x "$CN_DIR/crowsnest" ]; then
  install -Dm0755 "$CN_DIR/crowsnest" "$ENTRY"
elif [ -f "$CN_DIR/crowsnest.py" ]; then
  cat >"$ENTRY" <<'EOF'
#!/usr/bin/env bash
exec python3 -u /opt/crowsnest/crowsnest.py "$@"
EOF
  chmod 0755 "$ENTRY"
else
  echo_red "[crowsnest] could not find upstream entrypoint"
  ls -la "$CN_DIR" || true
  exit 1
fi
ln -sf "$ENTRY" /usr/local/bin/crowsnest

# Default config (only if absent)
install -d /etc
if [ ! -f /etc/crowsnest.conf ]; then
  cat >/etc/crowsnest.conf <<'EOF'
# Minimal example; adjust in your per-device layer
[global]
log_level = info
[streamer]
type = camera-streamer
device = auto
EOF
fi

install -d /var/log/crowsnest

# --- Camera runtime sanity (soft checks; don't fail chroot build) ---
if command -v camera-streamer >/dev/null 2>&1; then
  echo_green "[crowsnest] camera-streamer present: $(camera-streamer --version 2>/dev/null | head -n1 || echo unknown)"
  ldd "$(command -v camera-streamer)" | awk '/=>/ {print "[ldd] " $0}' || true
else
  echo_red "[crowsnest] WARN: camera-streamer not found in PATH (OK if using ustreamer-only config)"
fi
v4l2-ctl --version 2>/dev/null || echo_red "[crowsnest] WARN: v4l-utils missing or not runnable (OK in chroot)"

# Systemd unit (enable via symlink; do not start in chroot)
cat >/etc/systemd/system/crowsnest.service <<'EOF'
[Unit]
Description=Crowsnest Camera Service
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/crowsnest -c /etc/crowsnest.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/crowsnest.service /etc/systemd/system/multi-user.target.wants/crowsnest.service || true

# Soft reload if systemd is usable (okay if it isn't in chroot)
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi

echo_green "[crowsnest] installed"
