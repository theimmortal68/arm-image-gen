#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git make ca-certificates

runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git
'

bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/crowsnest'
  make install
"

# Update Manager fragment
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
cat > "${UMDIR}/crowsnest.conf" <<EOF
[update_manager crowsnest]
type: git_repo
path: ${HOME_DIR}/crowsnest
origin: https://github.com/mainsail-crew/crowsnest.git
install_script: tools/pkglist.sh
EOF
chown "${KS_USER}:${KS_USER}" "${UMDIR}/crowsnest.conf"
chmod 0644 "${UMDIR}/crowsnest.conf"

systemctl_if_exists daemon-reload || true
echo_green "[crowsnest] installed; UM fragment written"
