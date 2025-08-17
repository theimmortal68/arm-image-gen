#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Sonar"
apt_install sudo git ca-certificates
ensure_sudo_nopasswd
create_systemctl_shim

# Clone/update and install (skip interactive make config)
as_user "${KS_USER:-pi}" 'git_sync https://github.com/mainsail-crew/sonar.git "$HOME/sonar" main 1'
as_user "${KS_USER:-pi}" 'cd "$HOME/sonar" && sudo -En make install'

# Update-manager include via helper (no direct edits to moonraker.conf)
um_write_repo sonar "/home/${KS_USER:-pi}/sonar" "https://github.com/mainsail-crew/sonar.git" "main" "sonar"

enable_at_boot sonar.service
remove_systemctl_shim
apt_clean_all
