#!/usr/bin/env bash
# 36-moonraker-timelapse.sh — Install moonraker-timelapse without touching moonraker.conf
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Optional helpers
[ -r /common.sh ] && source /common.sh && install_cleanup_trap

### 0) System deps & sudo (avoid interactive sudo prompts) ###
apt-get update
apt-get install -y --no-install-recommends sudo git ffmpeg build-essential ca-certificates
rm -rf /var/lib/apt/lists/*

# Ensure sudoers.d exists and is sane; allow pi to sudo non-interactively for installer ops
install -d -m 0750 -o root -g root /etc/sudoers.d
chown root:root /etc/sudoers.d
chmod 0750 /etc/sudoers.d
install -D -m 0440 /dev/stdin /etc/sudoers.d/010_pi-mrtimelapse <<'EOF'
pi ALL=(root) NOPASSWD:/usr/bin/apt,/usr/bin/apt-get,/usr/bin/systemctl,/usr/sbin/service,/usr/bin/journalctl
EOF

### 1) Clone or refresh as pi (ownership matters) ###
runuser -u pi -- bash -lc '
  set -eux
  if [ ! -d "$HOME/moonraker-timelapse/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/moonraker-timelapse.git "$HOME/moonraker-timelapse"
  else
    git -C "$HOME/moonraker-timelapse" fetch --depth=1 origin
    git -C "$HOME/moonraker-timelapse" reset --hard origin/main
  fi
'

### 2) systemctl shim inside chroot (pretend success so installers don’t fail) ###
install -D -m 0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
if command -v /bin/systemctl >/dev/null 2>&1 && /bin/systemctl --version >/dev/null 2>&1; then
  exec /bin/systemctl "$@"
fi
# No systemd in chroot: report success for common ops
case "$1" in
  enable|disable|daemon-reload|is-enabled|start|stop|restart|reload) exit 0 ;;
  *) exit 0 ;;
esac
EOF

### 3) Run installer as *pi* (NOT root) and decline any config edits ###
# The installer may prompt to modify configs; answer "no" to avoid touching moonraker.conf.
runuser -u pi -- bash -lc '
  set -eux
  cd "$HOME/moonraker-timelapse"
  printf "n\nn\nn\n" | make install
'

### 4) Create update-manager.d include instead of editing moonraker.conf ###
# Assumes moonraker.conf already contains:  [include update-manager.d/*.conf]
runuser -u pi -- bash -lc '
  set -eux
  CONF_DIR="$HOME/printer_data/config"
  UM_DIR="$CONF_DIR/update-manager.d"
  install -d "$UM_DIR"

  # Drop timelapse configuration into update-manager.d
  install -D -m 0644 /dev/stdin "$UM_DIR/timelapse.conf" <<'"EOF"'
# --- Moonraker Timelapse component (included via update-manager.d) ---
[timelapse]
# Configure options here if desired (defaults are fine to start)

# Make Timelapse manageable via Moonraker Software Updates
[update_manager timelapse]
type: git_repo
path: ~/moonraker-timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
primary_branch: main
managed_services: klipper
"EOF"
'

### 5) Provide Klipper macros and include them from printer.cfg ###
runuser -u pi -- bash -lc '
  set -eux
  CONF_DIR="$HOME/printer_data/config"
  PRN="$CONF_DIR/printer.cfg"
  SRC="$HOME/moonraker-timelapse/klipper_macro/timelapse.cfg"
  DST="$CONF_DIR/timelapse.cfg"

  install -d "$CONF_DIR"
  [ -f "$PRN" ] || printf "# Autocreated printer.cfg\n" > "$PRN"

  if [ -f "$SRC" ] && [ ! -f "$DST" ]; then
    cp "$SRC" "$DST"
  fi

  # Ensure printer.cfg includes timelapse.cfg (idempotent)
  grep -Eq "^\[include[[:space:]]+timelapse\.cfg\]" "$PRN" || \
    printf "\n[include timelapse.cfg]\n" >> "$PRN"
'

### 6) Enable service at boot on-device (best-effort) ###
if [ -f /etc/systemd/system/moonraker-timelapse.service ]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../moonraker-timelapse.service /etc/systemd/system/multi-user.target.wants/moonraker-timelapse.service
fi

### 7) Clean up shim so the real systemctl is used on the device ###
rm -f /usr/local/sbin/systemctl

echo "[timelapse] Installed. Config provided via update-manager.d/timelapse.conf (no direct edits to moonraker.conf)."
