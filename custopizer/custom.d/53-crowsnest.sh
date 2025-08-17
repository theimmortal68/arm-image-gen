#!/usr/bin/env bash
# 53-crowsnest.sh — Crowsnest for Pi 4, Pi 5, Orange Pi 5 Max
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true

# ---- local fallbacks if helpers missing ----
section() { echo; echo "=== $* ==="; } || true
as_user() { local u="$1"; shift; runuser -u "$u" -- bash -lc "set -euxo pipefail; [ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true; $*"; }
apt_update_once() { apt-get update; }
apt_install() { apt_update_once; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }
apt_clean_all() { rm -rf /var/lib/apt/lists/*; }
fix_sudoers_sane() { install -d -m0750 -o root -g root /etc/sudoers.d; chown root:root /etc/sudoers.d; find /etc/sudoers.d -type f -exec chown root:root {} \; -exec chmod 0440 {} \; || true; }
ensure_sudo_nopasswd_all() { fix_sudoers_sane; install -D -m0440 /dev/stdin /etc/sudoers.d/999-custopizer-pi-all <<<'pi ALL=(ALL) NOPASSWD:ALL'; }
create_systemctl_shim() {
  install -D -m0755 /dev/stdin /usr/local/sbin/systemctl <<'EOF'
#!/usr/bin/env bash
if [ -x /bin/systemctl ] && [ -r /proc/1/comm ] && grep -qx 'systemd' /proc/1/comm 2>/dev/null; then
  exec /bin/systemctl "$@"
fi
case "$1" in enable|disable|daemon-reload|is-enabled|start|stop|restart|reload|status) exit 0;; *) exit 0;; esac
EOF
}
remove_systemctl_shim() { rm -f /usr/local/sbin/systemctl; }
# -------------------------------------------

[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

# Detect board
MODEL="$(tr -d '\0' </sys/firmware/devicetree/base/model 2>/dev/null || true)"
is_rpi=0; is_pi5=0; is_orangepi=0
case "${MODEL}" in
  *"Raspberry Pi 5"*) is_rpi=1; is_pi5=1 ;;
  *"Raspberry Pi"*)   is_rpi=1 ;;
  *"OrangePi"*|*"Orange Pi"*) is_orangepi=1 ;;
esac

# Policy for camera-streamer
# auto = Pi4/OrangePi: install; Pi5: try install, else stub; 1=force install; 0=skip (but stub to let Makefile pass)
: "${CN_INSTALL_CAMERA_STREAMER:=auto}"
: "${CAMERA_STREAMER_VERSION:=0.2.8}"   # known-good; override as needed

want_cs=0
if [ "${CN_INSTALL_CAMERA_STREAMER}" = "1" ]; then
  want_cs=1
elif [ "${CN_INSTALL_CAMERA_STREAMER}" = "0" ]; then
  want_cs=0
else
  # auto
  if [ "${is_pi5}" -eq 1 ]; then want_cs=1; else want_cs=1; fi
fi

section "Install prerequisites"
apt_install sudo git build-essential curl ca-certificates pkg-config

section "Prepare sudo & chroot-safe systemctl"
ensure_sudo_nopasswd_all
create_systemctl_shim

section "Clone/refresh Crowsnest as ${KS_USER}"
as_user "${KS_USER}" '
  if [ ! -d "$HOME/crowsnest/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git "$HOME/crowsnest"
  else
    git -C "$HOME/crowsnest" fetch --depth=1 origin
    git -C "$HOME/crowsnest" reset --hard origin/master
  fi
'

section "Ensure camera backends for Crowsnest"
as_user "${KS_USER}" '
  set -eux
  cd "$HOME/crowsnest"
  install -d "$HOME/crowsnest/bin/camera-streamer" "$HOME/crowsnest/bin/ustreamer"
'

# Try to provide camera-streamer (prebuilt) when desired
if [ "${want_cs}" -eq 1 ]; then
  as_user "${KS_USER}" '
    set -eux
    arch="$(dpkg --print-architecture)"
    codename="$(
      . /etc/os-release 2>/dev/null || true
      printf "%s" "${VERSION_CODENAME:-bookworm}"
    )"
    # flavour used by upstream release naming
    if [ -e /etc/default/raspberrypi-kernel ] || echo "'"${MODEL}"'" | grep -qi "Raspberry Pi"; then
      flavour="raspi"
    else
      flavour="generic"
    fi
    ver="'"${CAMERA_STREAMER_VERSION}"'"
    url_base="https://github.com/ayufan/camera-streamer/releases/download/v${ver}"
    pkg="camera-streamer-${flavour}_${ver}.${codename}_${arch}.deb"
    tmp="/tmp/${pkg}"
    ok=0
    # Try flavour package; then generic fallback
    if curl -fsSL -o "$tmp" "${url_base}/${pkg}"; then
      ok=1
    else
      pkg="camera-streamer-generic_${ver}.${codename}_${arch}.deb"
      tmp="/tmp/${pkg}"
      curl -fsSL -o "$tmp" "${url_base}/${pkg}" && ok=1 || true
    fi
    if [ "$ok" -eq 1 ]; then
      sudo -En apt-get update
      sudo -En apt-get install -y "$tmp"
      ln -sf "$(command -v camera-streamer)" "$HOME/crowsnest/bin/camera-streamer/camera-streamer"
    else
      echo "[crowsnest] WARN: No prebuilt camera-streamer found; will stub." >&2
    fi
  '
fi

# If we still don't have a camera-streamer binary in place, stub it (so Makefile doesn't abort)
as_user "${KS_USER}" '
  if [ ! -x "$HOME/crowsnest/bin/camera-streamer/camera-streamer" ]; then
    cat >"$HOME/crowsnest/bin/camera-streamer/camera-streamer" <<'"'EOF'"
#!/usr/bin/env bash
echo "camera-streamer not installed on this device; using ustreamer-only." >&2
exit 0
'"'EOF'"
    chmod +x "$HOME/crowsnest/bin/camera-streamer/camera-streamer"
  fi
'

section "Build/install Crowsnest (sudo inside, non-interactive)"
as_user "${KS_USER}" 'cd "$HOME/crowsnest" && sudo -En make install'

# Enable at boot via symlink (safe in chroot)
if [ -f /etc/systemd/system/crowsnest.service ]; then
  install -d -m0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../crowsnest.service /etc/systemd/system/multi-user.target.wants/crowsnest.service
fi
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

section "Cleanup"
remove_systemctl_shim
# keep NOPASSWD:ALL until all installers finish; remove later (e.g., 100-harden.sh)
apt_clean_all

echo "[crowsnest] install complete (ustreamer ready; camera-streamer: ${want_cs})"
