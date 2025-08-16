#!/usr/bin/env bash
# 36-moonraker-timelapse.sh — Install moonraker-timelapse during Build & Customize (chroot-safe)
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Optional helpers
[ -r /common.sh ] && source /common.sh && install_cleanup_trap

### 0) System deps & sudo setup (avoid interactive sudo prompts) ###
apt-get update
apt-get install -y --no-install-recommends \
  sudo git curl ffmpeg build-essential ca-certificates
# (ffmpeg is required for encoding; build-essential helps if any native wheels are built)
rm -rf /var/lib/apt/lists/*

# Ensure sudoers.d is sane and pi can sudo non-interactively for installer operations
install -d -m 0750 -o root -g root /etc/sudoers.d
chown root:root /etc/sudoers.d
chmod 0750 /etc/sudoers.d
install -D -m 0440 /dev/stdin /etc/sudoers.d/010_pi-mrtimelapse <<'EOF'
pi ALL=(root) NOPASSWD:/usr/bin/apt,/usr/bin/apt-get,/usr/bin/systemctl,/usr/sbin/service,/usr/bin/journalctl
EOF

### 1) Clone or refresh repo as pi (ownership matters) ###
runuser -u pi -- bash -lc '
  set -eux
  if [ ! -d "$HOME/moonraker-timelapse/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/moonraker-timelapse.git "$HOME/moonraker-timelapse"
  else
    git -C "$HOME/moonraker-timelapse" fetch --depth=1 origin
    git -C "$HOME/moonraker-timelapse" reset --hard origin/master
  fi
'

### 2) systemctl shim inside chroot (so installer doesn’t fail trying to touch services) ###
install -D -m 0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
if command -v /bin/systemctl >/dev/null 2>&1 && /bin/systemctl --version >/dev/null 2>&1; then
  exec /bin/systemctl "$@"
fi
# Pretend success in chroot
case "$1" in
  enable|disable|daemon-reload|is-enabled|start|stop|restart|reload) exit 0 ;;
  *) exit 0 ;;
esac
EOF

### 3) Run installer as *pi* (NOT root) ###
runuser -u pi -- bash -lc '
  set -eux
  cd "$HOME/moonraker-timelapse"
  # Run exactly as user; the installer will sudo internally when needed
  make install
'

### 4) Enable at boot on the device (best-effort) ###
if [ -f /etc/systemd/system/moonraker-timelapse.service ]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../moonraker-timelapse.service /etc/systemd/system/multi-user.target.wants/moonraker-timelapse.service
fi

### 5) Clean up shim so the real systemctl is used on-device ###
rm -f /usr/local/sbin/systemctl

echo "[timelapse] Installed. Verify config under /home/pi/printer_data/config after first boot."
