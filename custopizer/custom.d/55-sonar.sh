#!/usr/bin/env bash
# 54-sonar.sh — Manual, noninteractive Sonar install for CI/chroot
# - Clones mainsail-crew/sonar
# - Ensures ~/printer_data/config/sonar.conf exists (minimal defaults)
# - Installs a launcher at /usr/local/bin/sonar
# - Creates/“enables” a systemd service in a chroot-safe way
# - Adds a Moonraker Update Manager include (update-manager.d/sonar.conf)
# - Uses ks_helpers if present; otherwise ships safe fallbacks

set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# Core helpers (CustoPiZer)
source /common.sh
install_cleanup_trap

# Optional repo-specific helpers
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true

# ---------- Fallback helpers if ks_helpers.sh isn't present ----------
section() { echo; echo "=== $* ==="; } || true
apt_update_once() { apt-get update; }
apt_install() { apt_update_once; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }
apt_clean_all() { rm -rf /var/lib/apt/lists/*; }
fix_sudoers_sane() {
  install -d -m0750 -o root -g root /etc/sudoers.d
  chown root:root /etc/sudoers.d
  find /etc/sudoers.d -type f -exec chown root:root {} \; -exec chmod 0440 {} \; || true
}
ensure_sudo_nopasswd_all() {
  fix_sudoers_sane
  # Allow passwordless sudo during image build; remove in a final hardening step if desired
  install -D -m0440 /dev/stdin /etc/sudoers.d/999-custopizer-pi-all <<<'pi ALL=(ALL) NOPASSWD:ALL'
}
create_systemctl_shim() {
  install -D -m0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
# Chroot-safe systemctl shim: succeed for common subcommands when not PID 1=systemd
if [ -x /bin/systemctl ] && [ -r /proc/1/comm ] && grep -qx 'systemd' /proc/1/comm 2>/dev/null; then
  exec /bin/systemctl "$@"
fi
case "$1" in
  enable|disable|daemon-reload|is-enabled|start|stop|restart|reload|status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
}
remove_systemctl_shim() { rm -f /usr/local/sbin/systemctl; }
wr_pi() {  # wr_pi MODE DEST  (reads stdin; chowns to KS_USER)
  local mode="$1" dst="$2"
  install -D -m "$mode" /dev/stdin "$dst"
  chown "${KS_USER:-pi}:${KS_USER:-pi}" "$dst" || true
}
as_user() { local u="$1"; shift; runuser -u "$u" -- bash -lc "set -euxo pipefail; [ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true; $*"; }
# --------------------------------------------------------------------

# Resolve target user/home (from earlier 02-user or defaults)
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

section "Install prerequisites"
# python3 for sonar.py, iputils-ping for ping, git to clone
apt_install sudo git python3 iputils-ping curl ca-certificates

section "Prepare sudo & chroot-safe systemctl"
ensure_sudo_nopasswd_all
create_systemctl_shim

section "Clone/refresh Sonar repo"
as_user "${KS_USER}" '
  if [ ! -d "$HOME/sonar/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/sonar.git "$HOME/sonar"
  else
    git -C "$HOME/sonar" fetch --depth=1 origin
    git -C "$HOME/sonar" reset --hard origin/main || git -C "$HOME/sonar" reset --hard origin/master
  fi
'

section "Create minimal ~/printer_data/config/sonar.conf (if missing)"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"
SONAR_CFG="${HOME_DIR}/printer_data/config/sonar.conf"
if [ ! -s "${SONAR_CFG}" ]; then
  cat <<'EOF' | wr_pi 0644 "${SONAR_CFG}"
[sonar]
enable: true
persistent_log: false
target: auto
count: 3
interval: 60
restart_threshold: 10
EOF
fi

section "Install launcher and service (manual, Makefile-free)"
# Launcher that prefers repo wrapper if present; else python entrypoint
cat >/usr/local/bin/sonar <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HOME_DIR="${HOME_DIR:-$HOME}"
if [ -x "${HOME_DIR}/sonar/sonar" ]; then
  exec "${HOME_DIR}/sonar/sonar" "$@"
elif [ -f "${HOME_DIR}/sonar/sonar.py" ]; then
  exec /usr/bin/env python3 "${HOME_DIR}/sonar/sonar.py" "$@"
else
  echo "Sonar not found in ${HOME_DIR}/sonar" >&2
  exit 1
fi
EOF
chmod 0755 /usr/local/bin/sonar

# Service file (runs as KS_USER, points at launcher)
cat >/etc/systemd/system/sonar.service <<EOF
[Unit]
Description=Sonar WiFi Keepalive
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${KS_USER}
Group=${KS_USER}
WorkingDirectory=${HOME_DIR}
Environment=HOME_DIR=${HOME_DIR}
ExecStart=/usr/local/bin/sonar
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# “Enable” in chroot by creating the wants/ symlink; reload if systemd is active
install -d -m0755 /etc/systemd/system/multi-user.target.wants
ln -sf ../sonar.service /etc/systemd/system/multi-user.target.wants/sonar.service
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

section "Add Moonraker Update Manager include for Sonar"
UM_DIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" "${UM_DIR}"
UM_SNIPPET="${UM_DIR}/sonar.conf"
if [ ! -s "${UM_SNIPPET}" ]; then
  cat <<'EOF' | wr_pi 0644 "${UM_SNIPPET}"
[update_manager sonar]
type: git_repo
path: ~/sonar
origin: https://github.com/mainsail-crew/sonar.git
primary_branch: main
managed_services: sonar
install_script: tools/install.sh
EOF
fi

section "Cleanup"
remove_systemctl_shim
apt_clean_all

echo "[sonar] manual install complete — config: ${SONAR_CFG} — service installed"
