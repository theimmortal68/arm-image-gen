#!/usr/bin/env bash
# 30-moonraker.sh — Install Moonraker in a CustoPiZer chroot
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# Base bootstrap
source /common.sh
install_cleanup_trap
# Optional helper library
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section() { echo; echo "=== $* ==="; }
echo_green() { echo "[OK] $*"; }
echo_yellow() { echo "[WARN] $*"; }
echo_red() { echo "[ERR] $*" >&2; }

# Fallbacks if helpers are not present
apt_update_once() { apt-get update; }
apt_install() { apt_update_once; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }
apt_clean_all() { rm -rf /var/lib/apt/lists/*; }

# Fix sudoers perms/ownership so sudo will run at all
fix_sudoers_sane() {
  install -d -m 0750 -o root -g root /etc/sudoers.d
  chown root:root /etc/sudoers.d
  # Some base images ship a README; make sure it's root:root 0440
  find /etc/sudoers.d -type f -exec chown root:root {} \; -exec chmod 0440 {} \; || true
}

# During build, allow pi to sudo without TTY/password for any command
ensure_sudo_nopasswd_all() {
  fix_sudoers_sane
  install -D -m 0440 /dev/stdin /etc/sudoers.d/999-custopizer-pi-all <<'EOF'
pi ALL=(ALL) NOPASSWD:ALL
EOF
}

# Chroot-safe systemctl shim: only calls the real one if PID 1 is systemd
create_systemctl_shim() {
  install -D -m 0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
if [ -x /bin/systemctl ] && [ -r /proc/1/comm ] && grep -qx 'systemd' /proc/1/comm 2>/dev/null; then
  exec /bin/systemctl "$@"
fi
# No systemd: pretend success for common ops
case "$1" in
  enable|disable|daemon-reload|is-enabled|start|stop|restart|reload|status) exit 0 ;;
  *) exit 0 ;;
esac
EOF
}
remove_systemctl_shim() { rm -f /usr/local/sbin/systemctl; }

# Run a command as the target user; re-source helpers inside the child shell
as_user() {
  local u="$1"; shift
  local cmd="$*"
  runuser -u "$u" -- bash -lc "set -euxo pipefail; [ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true; $cmd"
}

# Resolve target user/home (persisted by your 02-user.sh)
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

section "Install Moonraker prerequisites"
apt_install git curl build-essential libffi-dev libssl-dev \
            python3-venv python3-virtualenv python3-dev \
            packagekit wireless-tools sudo ca-certificates

section "Ensure ~/printer_data is present and owned by ${KS_USER}"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"
chown -R "${KS_USER}:${KS_USER}" "${HOME_DIR}/printer_data"

section "Fix sudoers and grant temporary NOPASSWD for build"
fix_sudoers_sane
ensure_sudo_nopasswd_all

section "Install chroot-safe systemctl shim"
create_systemctl_shim

section "Clone or refresh Moonraker (as ${KS_USER})"
as_user "${KS_USER}" '
  if [ ! -d "$HOME/moonraker/.git" ]; then
    git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME/moonraker"
  else
    git -C "$HOME/moonraker" fetch --depth=1 origin
    # Use whatever the default remote HEAD is
    def_branch="$(git -C "$HOME/moonraker" rev-parse --abbrev-ref origin/HEAD | sed "s@^origin/@@")" || def_branch=master
    git -C "$HOME/moonraker" reset --hard "origin/${def_branch}"
  fi
'

section "Run Moonraker installer (as ${KS_USER}, systemctl disabled)"
as_user "${KS_USER}" '
  cd "$HOME/moonraker"
  MOONRAKER_DISABLE_SYSTEMCTL=1 ./scripts/install-moonraker.sh -f -c "$HOME/printer_data/config/moonraker.conf"
'

# (Optional) Drop an Update Manager entry; Moonraker can manage itself, but harmless if present
# as_user "${KS_USER}" '
#   CONF_DIR="$HOME/printer_data/config/update-manager.d"; install -d "$CONF_DIR"
#   cat >"$CONF_DIR/moonraker.conf" <<EOF
# [update_manager moonraker]
# type: git_repo
# path: ~/moonraker
# origin: https://github.com/Arksine/moonraker.git
# primary_branch: master
# managed_services: moonraker
# EOF
# '

section "Cleanup shim (and optionally tighten sudoers)"
remove_systemctl_shim
# If you don't want NOPASSWD:ALL in the final image, remove it now or in 100-harden.sh:
rm -f /etc/sudoers.d/999-custopizer-pi-all || true

apt_clean_all
echo_green "[moonraker] installation complete (chroot-safe)."
