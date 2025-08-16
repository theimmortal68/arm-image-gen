#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

# If you use shared helpers, this won't error if absent
[ -r /common.sh ] && source /common.sh && install_cleanup_trap

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  git python3-venv python3-dev build-essential libffi-dev libssl-dev
rm -rf /var/lib/apt/lists/*

# Ensure config dir exists and is owned by pi
install -d -o pi -g pi /home/pi/printer_data/config

# Clone or refresh Moonraker as the pi user (so ownership is correct)
runuser -u pi -- bash -lc '
  set -eux
  if [ ! -d "$HOME/moonraker/.git" ]; then
    git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME/moonraker"
  else
    git -C "$HOME/moonraker" fetch origin
    git -C "$HOME/moonraker" reset --hard origin/master
  fi
'

# Install Moonraker as the pi user; skip systemctl inside chroot
runuser -u pi -- bash -lc '
  set -eux
  cd "$HOME/moonraker"
  MOONRAKER_DISABLE_SYSTEMCTL=1 ./scripts/install-moonraker.sh \
    -f -c "$HOME/printer_data/config/moonraker.conf"
'

# Notes:
# - Running under runuser avoids: "This script must not run as root".
# - MOONRAKER_DISABLE_SYSTEMCTL=1 prevents systemctl calls during image build.
#   (Enable services later on the device with: sudo systemctl enable --now moonraker)
