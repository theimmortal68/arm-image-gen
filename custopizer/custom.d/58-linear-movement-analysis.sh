#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Linear Movement Analysis (KLMA)"

# Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

# Basic deps
apt_install git ca-certificates curl

# Clone or refresh as target user
as_user "${KS_USER}" 'git_sync https://github.com/worksasintended/klipper_linear_movement_analysis.git "$HOME/klipper_linear_movement_analysis" main 1'

# Run upstream installer (does its own pip/env work)
as_user "${KS_USER}" 'bash "$HOME/klipper_linear_movement_analysis/install.sh"'

# Ensure output directory exists for results
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config/linear_vibrations"

# Update Manager include (needs extra keys; write directly as pi)
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${HOME_DIR}/printer_data/config/update-manager.d"
cat > "${HOME_DIR}/printer_data/config/update-manager.d/LinearMovementAnalysis.conf" <<'EOF'
[update_manager LinearMovementAnalysis]
type: git_repo
path: ~/klipper_linear_movement_analysis
primary_branch: main
origin: https://github.com/worksasintended/klipper_linear_movement_analysis.git
install_script: install.sh
env: ~/klippy-env/bin/python
requirements: requirements.txt
managed_services: klipper
EOF
chown "${KS_USER}:${KS_USER}" "${HOME_DIR}/printer_data/config/update-manager.d/LinearMovementAnalysis.conf"
chmod 0644 "${HOME_DIR}/printer_data/config/update-manager.d/LinearMovementAnalysis.conf"

systemctl_if_exists daemon-reload || true
echo_green "[KLMA] installed; UM fragment written"
apt_clean_all
