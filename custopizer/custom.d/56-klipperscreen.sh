#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git ca-certificates curl sudo

# Clone upstream
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/KlipperScreen/KlipperScreen.git
'

# Run upstream installer with requested flags
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  SERVICE=Y BACKEND=X NETWORK=N START=0 ./KlipperScreen/scripts/KlipperScreen-install.sh
'

# Update Manager fragment
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
cat > "${UMDIR}/KlipperScreen.conf" <<EOF
[update_manager KlipperScreen]
type: git_repo
path: ${HOME_DIR}/KlipperScreen
origin: https://github.com/KlipperScreen/KlipperScreen.git
virtualenv: ${HOME_DIR}/.KlipperScreen-env
requirements: scripts/KlipperScreen-requirements.txt
system_dependencies: scripts/system-dependencies.json
managed_services: KlipperScreen
EOF
chown "${KS_USER}:${KS_USER}" "${UMDIR}/KlipperScreen.conf"
chmod 0644 "${UMDIR}/KlipperScreen.conf"

systemctl_if_exists daemon-reload || true
echo_green "[KlipperScreen] installed via upstream script; UM fragment written"
