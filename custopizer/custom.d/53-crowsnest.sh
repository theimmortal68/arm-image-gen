#!/usr/bin/env bash
# 53-crowsnest.sh — Install Crowsnest for Pi 4 / Pi 5 / Orange Pi 5 Max (chroot-safe + robust fallback)
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
# Optional helpers
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true

# ---------- Fallback helpers if ks_helpers.sh isn't present ----------
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
wr_pi() { local mode="$1" dst="$2"; install -D -m "$mode" /dev/stdin "$dst"; chown "${KS_USER:-pi}:${KS_USER:-pi}" "$dst" || true; }
# --------------------------------------------------------------------

# Resolve target user/home (from 02-user.sh persistence if present)
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

# Board detection (best-effort)
MODEL="$(tr -d '\0' </sys/firmware/devicetree/base/model 2>/dev/null || true)"
is_rpi=0; is_pi5=0; is_orangepi=0
case "${MODEL}" in
  *"Raspberry Pi 5"*) is_rpi=1; is_pi5=1 ;;
  *"Raspberry Pi"*)   is_rpi=1 ;;
  *"OrangePi"*|*"Orange Pi"*) is_orangepi=1 ;;
esac

# Camera-streamer policy:
#   auto: try prebuilt; fall back to stub if not available
#   1   : force install attempt (still falls back to stub if download fails)
#   0   : skip install; force stub (ustreamer-only)
: "${CN_INSTALL_CAMERA_STREAMER:=auto}"
: "${CAMERA_STREAMER_VERSION:=0.2.8}"

want_cs=0
if [ "${CN_INSTALL_CAMERA_STREAMER}" = "1" ]; then
  want_cs=1
elif [ "${CN_INSTALL_CAMERA_STREAMER}" = "0" ]; then
  want_cs=0
else
  want_cs=1
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

# Ensure backend bin dirs exist and are user-owned
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/crowsnest/bin/ustreamer"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/crowsnest/bin/camera-streamer"

# Try to install prebuilt camera-streamer (as user with sudo), if desired
if [ "${want_cs}" -eq 1 ]; then
  as_user "${KS_USER}" '
    set -eux
    arch="$(dpkg --print-architecture)"
    codename="$(
      . /etc/os-release 2>/dev/null || true
      printf "%s" "${VERSION_CODENAME:-bookworm}"
    )"
    # Choose flavour name used by upstream assets
    if [ -e /etc/default/raspberrypi-kernel ] || echo "'"${MODEL}"'" | grep -qi "Raspberry Pi"; then
      flavour="raspi"
    else
      flavour="generic"
    fi
    ver="'"${CAMERA_STREAMER_VERSION}"'"
    base="https://github.com/ayufan/camera-streamer/releases/download/v${ver}"
    pkg="camera-streamer-${flavour}_${ver}.${codename}_${arch}.deb"
    tmp="/tmp/${pkg}"
    ok=0
    sudo -En apt-get update
    sudo -En apt-get install -y curl ca-certificates
    if curl -fsSL -o "$tmp" "${base}/${pkg}"; then
      ok=1
    else
      pkg="camera-streamer-generic_${ver}.${codename}_${arch}.deb"
      tmp="/tmp/${pkg}"
      curl -fsSL -o "$tmp" "${base}/${pkg}" && ok=1 || true
    fi
    if [ "$ok" -eq 1 ]; then
      sudo -En apt-get install -y "$tmp"
      ln -sf "$(command -v camera-streamer)" "$HOME/crowsnest/bin/camera-streamer/camera-streamer"
    else
      echo "[crowsnest] WARN: no prebuilt camera-streamer found; will stub." >&2
    fi
  '
fi

# If still missing, write a small stub (NO heredoc inside runuser)
cs_dir="${HOME_DIR}/crowsnest/bin/camera-streamer"
stub="${cs_dir}/camera-streamer"
if [ ! -x "${stub}" ]; then
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo "camera-streamer not installed on this device; using ustreamer-only." >&2' \
    'exit 0' \
  | wr_pi 0755 "${stub}"
fi

# Ensure a no-op Makefile so 'make -C bin/camera-streamer' or 'cd && make' both succeed
noop_make='
.PHONY: all apps install clean
all:
	@echo "camera-streamer: using prebuilt/stub binary; nothing to build."
apps:
	@true
install:
	@true
clean:
	@true
'
for mf in "Makefile" "makefile" "GNUmakefile"; do
  if [ ! -f "${cs_dir}/${mf}" ]; then
    printf "%s\n" "${noop_make}" | wr_pi 0644 "${cs_dir}/${mf}"
  fi
done

section "Build/install Crowsnest (sudo inside, non-interactive, verbose)"
# Extra visibility: list the camera-streamer dir before building
ls -lah "${cs_dir}" || true

# Capture make output for debugging and try to complete even if a sub-target fails.
as_user "${KS_USER}" '
  set -eux
  cd "$HOME/crowsnest"
  export V=1
  export MAKEFLAGS="--output-sync=line -j$(nproc)"
  # Capture full log
  sudo -En bash -lc '\''( make install ) 2>&1 | tee /tmp/crowsnest-make-install.log'\'' || INSTALL_FAIL=1
  # Share log path with root for later collection
  if [ -f /tmp/crowsnest-make-install.log ]; then
    sudo cp -f /tmp/crowsnest-make-install.log /tmp/crowsnest-make-install.log.root || true
  fi
  exit ${INSTALL_FAIL:-0}
'

# If make install failed, attempt a fallback manual install so the image remains functional
if [ "${PIPESTATUS[0]:-0}" -ne 0 ] 2>/dev/null || [ ! -f /etc/systemd/system/crowsnest.service ]; then
  section "Fallback: manual Crowsnest install (service + binaries)"
  # Install main launcher if present
  if [ -x "${HOME_DIR}/crowsnest/crowsnest" ]; then
    install -D -m0755 "${HOME_DIR}/crowsnest/crowsnest" /usr/local/bin/crowsnest
  elif [ -x "${HOME_DIR}/crowsnest/scripts/crowsnest.sh" ]; then
    install -D -m0755 "${HOME_DIR}/crowsnest/scripts/crowsnest.sh" /usr/local/bin/crowsnest
  else
    # Last resort: provide a tiny wrapper that calls repo script if it appears later
    cat <<'EOF' >/usr/local/bin/crowsnest
#!/usr/bin/env bash
if [ -x "$HOME/crowsnest/crowsnest" ]; then exec "$HOME/crowsnest/crowsnest" "$@"; fi
if [ -x "$HOME/crowsnest/scripts/crowsnest.sh" ]; then exec "$HOME/crowsnest/scripts/crowsnest.sh" "$@"; fi
echo "crowsnest entrypoint not found under $HOME/crowsnest" >&2
exit 1
EOF
    chmod 0755 /usr/local/bin/crowsnest
  fi

  # Ensure a minimal config exists
  install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"
  cfg="${HOME_DIR}/printer_data/config/crowsnest.conf"
  if [ ! -s "${cfg}" ]; then
    cat <<'EOF' | wr_pi 0644 "${cfg}"
# Minimal Crowsnest config (ustreamer-only fallback)
[general]
log_path: ~/printer_data/logs
[cam usb0]
enabled: true
device: /dev/video0
mode: mjpg
port: 8080
EOF
  fi

  # Create a simple service if missing
  if [ ! -f /etc/systemd/system/crowsnest.service ]; then
    cat >/etc/systemd/system/crowsnest.service <<EOF
[Unit]
Description=Crowsnest camera manager
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${KS_USER}
Group=${KS_USER}
WorkingDirectory=${HOME_DIR}
Environment=CN_CONFIG=${cfg}
ExecStart=/usr/local/bin/crowsnest -c ${cfg}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  fi
fi

# Enable at boot by symlink (safe in chroot)
if [ -f /etc/systemd/system/crowsnest.service ]; then
  install -d -m0755 /etc/systemd/system/multi-user.target.wants
  ln -sf ../crowsnest.service /etc/systemd/system/multi-user.target.wants/crowsnest.service
fi
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

section "Cleanup"
remove_systemctl_shim
# Keep NOPASSWD:ALL until all installers finish; remove in your finalizer (e.g., 100-harden.sh)
apt_clean_all

echo "[crowsnest] install complete (ustreamer ready; camera-streamer policy: ${CN_INSTALL_CAMERA_STREAMER})"
