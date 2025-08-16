#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Moonraker Timelapse (mainsail-crew)
# Upstream install flow:
#   cd ~
#   git clone https://github.com/mainsail-crew/moonraker-timelapse.git
#   cd ~/moonraker-timelapse
#   make install
#
# Docs also show the Moonraker Update Manager block for in-UI updates.

# Target user/home (same convention as your other scripts)
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
# make for `make install`, ffmpeg is recommended by upstream for render, plus basic tools
apt-get install -y --no-install-recommends git make ca-certificates ffmpeg

# Clone (no idempotence: error if exists)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/mainsail-crew/moonraker-timelapse.git
'

# Install as root (no sudo inside chroot)
bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/moonraker-timelapse'
  make install
"
# Seed a default timelapse.conf if missing (user-owned)
TL_CFG="${HOME_DIR}/printer_data/config/timelapse.conf"
if [ ! -e "${TL_CFG}" ]; then
  install -D -o "${KS_USER}" -g "${KS_USER}" -m 0644 /dev/null "${TL_CFG}"
  cat >> "${TL_CFG}" <<'EOF'
# Moonraker Timelapse defaults
[timelapse]
ffmpeg_binary_path: /usr/bin/ffmpeg
# output_path: ~/printer_data/timelapse
# enable_async_render: True
EOF
fi

# Add/refresh Moonraker Update Manager block exactly as upstream shows
CFG_DIR="${HOME_DIR}/printer_data/config"
CFG="${CFG_DIR}/moonraker.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" "${CFG_DIR}"
[ -e "${CFG}" ] || install -m 0644 -o "${KS_USER}" -g "${KS_USER}" /dev/null "${CFG}"

TMP=\"$(mktemp)\"
awk '
  BEGIN{skip=0}
  /^\[update_manager[[:space:]]+timelapse\]/{skip=1; next}
  skip && /^\[/{skip=0}
  !skip{print}
' \"${CFG}\" > \"${TMP}\"
printf \"\n\" >> \"${TMP}\"
cat >> \"${TMP}\" <<EOF
[update_manager timelapse]
type: git_repo
primary_branch: main
path: ${HOME_DIR}/moonraker-timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
managed_services: klipper moonraker
EOF
install -m 0644 -o \"${KS_USER}\" -g \"${KS_USER}\" \"${TMP}\" \"${CFG}\"
rm -f \"${TMP}\"

# Optional: record revision
if [ -d \"${HOME_DIR}/moonraker-timelapse/.git\" ]; then
  rev=\"$(git -C \"${HOME_DIR}/moonraker-timelapse\" rev-parse --short HEAD || true)\"
  install -d -m 0755 /etc
  printf 'Moonraker-timelapse\t%s\n' \"${rev:-unknown}\" >> /etc/ks-manifest.txt
fi

systemctl_if_exists daemon-reload || true
echo_green \"[moonraker-timelapse] installed via make; Update Manager configured\"
