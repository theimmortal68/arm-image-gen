#!/usr/bin/env bash
# 37-sonar.sh — Install Sonar during Build & Customize (no TTY, no moonraker.conf edits)
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Optional helpers
[ -r /common.sh ] && source /common.sh && install_cleanup_trap

### 0) Minimal deps & sudo (NOPASSWD so installer can run non-interactively)
apt-get update
apt-get install -y --no-install-recommends sudo git ca-certificates
rm -rf /var/lib/apt/lists/*

# Ensure sudoers.d exists & sane; allow pi common ops the installer needs
install -d -m 0750 -o root -g root /etc/sudoers.d
install -D -m 0440 /dev/stdin /etc/sudoers.d/010_pi-sonar <<'EOF'
pi ALL=(root) NOPASSWD:/usr/bin/apt,/usr/bin/apt-get,/usr/bin/systemctl,/usr/sbin/service,/usr/bin/journalctl
EOF

### 1) Clone/refresh as pi
runuser -u pi -- bash -lc '
  set -euo pipefail
  if [ ! -d "$HOME/sonar/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/sonar.git "$HOME/sonar"
  else
    git -C "$HOME/sonar" fetch --depth=1 origin
    git -C "$HOME/sonar" reset --hard origin/main
  fi
'

### 2) systemctl shim inside chroot (so service steps don’t fail)
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

### 3) Install as *pi* with sudo (do NOT run as root; skip `make config`)
runuser -u pi -- bash -lc '
  set -euo pipefail
  cd "$HOME/sonar"
  sudo -En make install
'

### 4) Create update-manager include (no moonraker.conf edits)
runuser -u pi -- bash -lc '
  set -euo pipefail
  CONF_DIR="$HOME/printer_data/config"
  UM_DIR="$CONF_DIR/update-manager.d"
  install -d "$UM_DIR"
  install -D -m 0644 /dev/stdin "$UM_DIR/sonar.conf" <<'"EOF"'
# --- Sonar (included via update-manager.d) ---
[update_manager sonar]
type: git_repo
path: ~/sonar
origin: https://github.com/mainsail-crew/sonar.git
primary_branch: main
managed_services: sonar
install_script: tools/install.sh
"EOF"
'

### 5) Seed optional runtime config (separate heredoc to avoid quoting mixups)
runuser -u pi -- bash -lc '
  set -euo pipefail
  CONF_DIR="$HOME/printer_data/config"
  SONAR_CFG="$CONF_DIR/sonar.conf"
  if [ ! -f "$SONAR_CFG" ]; then
    install -D -m 0644 /dev/stdin "$SONAR_CFG" <<'"EOF"'
[sonar]
# enable: true
# persistent_log: false
# target: auto
# count: 3
# interval: 60
# restart_threshold: 10
"EOF"
  fi
'

### 6) Enable at boot on target (best-effort)
if [ -f /etc/systemd/system/sonar.service ]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../sonar.service /etc/systemd/system/multi-user.target.wants/sonar.service
fi

### 7) Remove shim so the real systemctl is used on-device
rm -f /usr/local/sbin/systemctl

echo "[sonar] Installed. Update-manager config dropped at ~pi/printer_data/config/update-manager.d/sonar.conf."
