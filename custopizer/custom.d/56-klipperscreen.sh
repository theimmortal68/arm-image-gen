#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install KlipperScreen (X backend)"

# Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

# Clone/refresh as user
as_user "${KS_USER}" 'git_sync https://github.com/KlipperScreen/KlipperScreen.git "$HOME/KlipperScreen" master 1'

# Run upstream installer as user (non-interactive flags)
as_user "${KS_USER}" 'cd "$HOME" && SERVICE=Y BACKEND=X NETWORK=N START=0 ./KlipperScreen/scripts/KlipperScreen-install.sh'

# Update Manager include (write directly; needs extra keys)
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${HOME_DIR}/printer_data/config/update-manager.d"
cat > "${HOME_DIR}/printer_data/config/update-manager.d/KlipperScreen.conf" <<EOF
[update_manager KlipperScreen]
type: git_repo
path: ${HOME_DIR}/KlipperScreen
origin: https://github.com/KlipperScreen/KlipperScreen.git
virtualenv: ${HOME_DIR}/.KlipperScreen-env
requirements: scripts/KlipperScreen-requirements.txt
system_dependencies: scripts/system-dependencies.json
managed_services: KlipperScreen
EOF
chown "${KS_USER}:${KS_USER}" "${HOME_DIR}/printer_data/config/update-manager.d/KlipperScreen.conf"
chmod 0644 "${HOME_DIR}/printer_data/config/update-manager.d/KlipperScreen.conf"

echo_green "[KlipperScreen] installed; UM fragment written"
