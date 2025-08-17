#!/usr/bin/env bash
# 54-sonar.sh — Install Sonar (WiFi keepalive) chroot-safe & noninteractive
# - Pre-creates ~/printer_data/config/sonar.conf (avoids interactive `make config`)
# - Runs `sudo make install` as the target user
# - Adds Moonraker Update Manager include in update-manager.d
# - Uses ks_helpers if available; otherwise provides minimal fallbacks

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
  # Allow passwordless sudo during image build; remove in a later hardening step if desired
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
wr_pi() {  # wr_pi MODE DEST  (reads content from stdin; chowns to KS_USER)
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
apt_install sudo git make curl ca-certificates

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

section "Ensure printer_data/config exists and create minimal sonar.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"

# Pre-create config so `make install` is happy (noninteractive)
SONAR_CFG="${HOME_DIR}/printer_data/config/sonar.conf"
if [ ! -s "${SONAR_CFG}" ]; then
  # Minimal but valid config (per README)
  # https://github.com/mainsail-crew/sonar (Config: ~/printer_data/config/sonar.conf)
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

section "Run install (noninteractive, TERM-safe)"
# Some Makefiles use tput/colors and expect TERM; set it to avoid errors
as_user "${KS_USER}" '
  cd "$HOME/sonar"
  export TERM=xterm-256color
  # With config already present, we can skip `make config`.
  sudo -En make install
'

# Optional but recommended: wire Sonar into Moonraker Update Manager via include file,
# without editing moonraker.conf directly.
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

# Enable at boot in a chroot-safe way (symlink into multi-user target)
if [ -f /etc/systemd/system/sonar.service ]; then
  install -d -m0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../sonar.service /etc/systemd/system/multi-user.target.wants/sonar.service
fi
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

section "Cleanup"
remove_systemctl_shim
apt_clean_all

echo "[sonar] install complete — config: ${SONAR_CFG}"
