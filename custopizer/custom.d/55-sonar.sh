#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git make ca-certificates iputils-ping

runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/mainsail-crew/sonar.git
'

runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME/sonar"
  make config
'
bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/sonar'
  make install
"

# Update Manager fragment
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
cat > "${UMDIR}/sonar.conf" <<EOF
[update_manager sonar]
type: git_repo
path: ${HOME_DIR}/sonar
origin: https://github.com/mainsail-crew/sonar.git
primary_branch: main
managed_services: sonar
install_script: tools/install.sh
EOF
chown "${KS_USER}:${KS_USER}" "${UMDIR}/sonar.conf"
chmod 0644 "${UMDIR}/sonar.conf"

systemctl_if_exists daemon-reload || true
echo_green "[sonar] installed; UM fragment written"
