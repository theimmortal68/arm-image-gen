#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Moonraker"
apt_install git curl build-essential libffi-dev libssl-dev python3-venv python3-virtualenv python3-dev packagekit wireless-tools sudo
ensure_sudo_nopasswd

# Ensure config path owned by user
install -d -o "${KS_USER:-pi}" -g "${KS_USER:-pi}" "/home/${KS_USER:-pi}/printer_data/config"

# Clone/update and install as user (disable systemctl during chroot)
as_user "${KS_USER:-pi}" '
  if [ ! -d "$HOME/moonraker/.git" ]; then
    git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME/moonraker"
  else
    git -C "$HOME/moonraker" fetch --depth=1 origin
    git -C "$HOME/moonraker" reset --hard origin/master
  fi
  cd "$HOME/moonraker"
  MOONRAKER_DISABLE_SYSTEMCTL=1 ./scripts/install-moonraker.sh -f -c "$HOME/printer_data/config/moonraker.conf"
'

apt_clean_all
