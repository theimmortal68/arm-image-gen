#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true

# ----- local fallbacks if helpers are missing -----
fix_sudoers_sane() {
  install -d -m 0750 -o root -g root /etc/sudoers.d
  chown root:root /etc/sudoers.d
  find /etc/sudoers.d -type f -exec chown root:root {} \; -exec chmod 0440 {} \; || true
}
ensure_sudo_nopasswd_all() {
  fix_sudoers_sane
  install -D -m 0440 /dev/stdin /etc/sudoers.d/999-custopizer-pi-all <<'EOF'
pi ALL=(ALL) NOPASSWD:ALL
EOF
}
create_systemctl_shim() {
  install -D -m 0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
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
as_user() {
  local u="$1"; shift; local cmd="$*"
  runuser -u "$u" -- bash -lc "set -euxo pipefail; [ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true; $cmd"
}
apt_update_once() { apt-get update; }
apt_install() { apt_update_once; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }
apt_clean_all() { rm -rf /var/lib/apt/lists/*; }
# -----------------------------------------------

section() { echo; echo "=== $* ==="; } || true
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"

section "Install Crowsnest prerequisites"
apt_install sudo git build-essential curl ca-certificates pkg-config

section "Prepare sudo & chroot-safe systemctl"
fix_sudoers_sane
ensure_sudo_nopasswd_all      # TEMP during build
create_systemctl_shim

section "Clone/refresh crowsnest as ${KS_USER}"
as_user "${KS_USER}" '
  if [ ! -d "$HOME/crowsnest/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git "$HOME/crowsnest"
  else
    git -C "$HOME/crowsnest" fetch --depth=1 origin
    git -C "$HOME/crowsnest" reset --hard origin/master
  fi
'

section "Run installer (sudo inside, non-interactive)"
as_user "${KS_USER}" 'cd "$HOME/crowsnest" && sudo -En make install'

# Enable at boot by symlink (safe in chroot)
if [ -f /etc/systemd/system/crowsnest.service ]; then
  install -d -m 0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../crowsnest.service /etc/systemd/system/multi-user.target.wants/crowsnest.service
fi
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

section "Cleanup"
remove_systemctl_shim
# keep NOPASSWD:ALL until all installers are done (timelapse, etc).
# remove in your finalizer (e.g. 100-harden.sh), or uncomment next line to remove now:
# rm -f /etc/sudoers.d/999-custopizer-pi-all || true
apt_clean_all

echo "[crowsnest] installed."
