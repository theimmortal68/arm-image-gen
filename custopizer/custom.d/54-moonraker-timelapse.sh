#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git make ca-certificates ffmpeg

runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/mainsail-crew/moonraker-timelapse.git
'

bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/moonraker-timelapse'
  make install
"

# Update Manager fragment
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
cat > "${UMDIR}/timelapse.conf" <<EOF
[update_manager timelapse]
type: git_repo
primary_branch: main
path: ${HOME_DIR}/moonraker-timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
managed_services: klipper moonraker
EOF
chown "${KS_USER}:${KS_USER}" "${UMDIR}/timelapse.conf"
chmod 0644 "${UMDIR}/timelapse.conf"

systemctl_if_exists daemon-reload || true
echo_green "[moonraker-timelapse] installed; UM fragment written"
