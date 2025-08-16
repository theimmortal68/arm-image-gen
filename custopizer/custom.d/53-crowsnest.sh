#!/usr/bin/env bash
# 35-crowsnest.sh — Install Crowsnest during Build & Customize (chroot-safe)
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Optional helpers (won't error if absent)
[ -r /common.sh ] && source /common.sh && install_cleanup_trap

### 1) Ensure sudo + toolchain and fix sudoers ###
apt-get update
apt-get install -y --no-install-recommends sudo git build-essential curl ca-certificates pkg-config
# Make sure sudoers.d exists and is sane
install -d -m 0750 -o root -g root /etc/sudoers.d
chown root:root /etc/sudoers.d
chmod 0750 /etc/sudoers.d
# Give pi passwordless sudo for only what the installer typically needs
install -D -m 0440 /dev/stdin /etc/sudoers.d/010_pi-crowsnest <<'EOF'
pi ALL=(root) NOPASSWD:/usr/bin/apt,/usr/bin/apt-get,/usr/bin/systemctl,/usr/sbin/service,/usr/bin/journalctl
EOF
rm -rf /var/lib/apt/lists/*

### 2) Clone/refresh Crowsnest as pi ###
runuser -u pi -- bash -lc '
  set -eux
  if [ ! -d "$HOME/crowsnest/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git "$HOME/crowsnest"
  else
    git -C "$HOME/crowsnest" fetch --depth=1 origin
    git -C "$HOME/crowsnest" reset --hard origin/master
  fi
'

### 3) Temp systemctl shim for chroot (prevents failures) ###
# If systemd isn’t active in the chroot, installers that call systemctl may fail.
# This shim lets those calls succeed without actually starting services.
install -D -m 0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
if command -v /bin/systemctl >/dev/null 2>&1 && /bin/systemctl --version >/dev/null 2>&1; then
  exec /bin/systemctl "$@"
fi
case "$1" in
  enable|disable|daemon-reload|is-enabled|start|stop|restart|reload) exit 0 ;;
  *) exit 0 ;;
esac
EOF

### 4) Run the official installer as pi (non-interactive answers: No/No) ###
# - First "n": don't auto-edit moonraker.conf in the image
# - Second "n": don't reboot inside chroot
runuser -u pi -- bash -lc '
  set -eux
  cd "$HOME/crowsnest"
  printf "n\nn\n" | sudo -En make install
'

### 5) Enable at boot on the target (create wants symlink if unit exists) ###
if [ -f /etc/systemd/system/crowsnest.service ]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../crowsnest.service /etc/systemd/system/multi-user.target.wants/crowsnest.service
fi

### 6) Clean up shim so real systemctl works on-device ###
rm -f /usr/local/sbin/systemctl

echo "[crowsnest] Installed. Adjust /home/pi/printer_data/config/crowsnest.conf after first boot."
