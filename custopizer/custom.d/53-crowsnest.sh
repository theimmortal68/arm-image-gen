#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Crowsnest"
apt_install sudo git build-essential curl ca-certificates pkg-config
ensure_sudo_nopasswd
create_systemctl_shim

# Clone/update and install as pi with sudo (installer expects sudo, not root)
as_user "${KS_USER:-pi}" '
  if [ ! -d "$HOME/crowsnest/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git "$HOME/crowsnest"
  else
    git -C "$HOME/crowsnest" fetch --depth=1 origin
    git -C "$HOME/crowsnest" reset --hard origin/master
  fi
  cd "$HOME/crowsnest"
  sudo -En make install
'

enable_at_boot crowsnest.service
remove_systemctl_shim
apt_clean_all
