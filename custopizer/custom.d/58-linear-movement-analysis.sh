#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git ca-certificates curl

# Clone (no idempotence)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/worksasintended/klipper_linear_movement_analysis.git
'

# Run upstream installer
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  bash "$HOME/klipper_linear_movement_analysis/install.sh"
'

# Ensure output directory exists
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config/linear_vibrations"

# Update Manager fragment
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
cat > "${UMDIR}/LinearMovementAnalysis.conf" <<EOF
[update_manager LinearMovementAnalysis]
type: git_repo
path: ${HOME_DIR}/klipper_linear_movement_analysis
primary_branch: main
origin: https://github.com/worksasintended/klipper_linear_movement_analysis.git
install_script: install.sh
env: ${HOME_DIR}/klippy-env/bin/python
requirements: requirements.txt
managed_services: klipper
EOF
chown "${KS_USER}:${KS_USER}" "${UMDIR}/LinearMovementAnalysis.conf"
chmod 0644 "${UMDIR}/LinearMovementAnalysis.conf"

systemctl_if_exists daemon-reload || true
echo_green "[KLMA] installed via upstream install.sh; UM fragment written"
