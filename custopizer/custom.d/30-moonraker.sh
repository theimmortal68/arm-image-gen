#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

# Optional: source your helpers if present
[ -r /common.sh ] && source /common.sh && install_cleanup_trap

export DEBIAN_FRONTEND=noninteractive

# --- Fix sudoers perms (yours are owned by uid 1001) ---
if [ -d /etc/sudoers.d ]; then
  chown root:root /etc/sudoers.d
  chmod 0750 /etc/sudoers.d
else
  install -d -m 0750 -o root -g root /etc/sudoers.d
fi

# Give pi passwordless sudo (needed for Moonraker’s installer/update flows)
install -D -m 0440 /dev/stdin /etc/sudoers.d/010_pi-nopasswd <<'EOF'
pi ALL=(ALL) NOPASSWD:ALL
EOF
# (If you want to lock this down, limit to apt/systemctl later.)

# --- Preinstall the system packages Moonraker expects ---
apt-get update
apt-get install -y --no-install-recommends \
  sudo git curl build-essential python3-venv python3-virtualenv python3-dev \
  libffi-dev libssl-dev libjpeg-dev libopenjp2-7 zlib1g-dev libsodium-dev \
  packagekit wireless-tools
rm -rf /var/lib/apt/lists/*

# Ensure config dir exists and is owned by pi
install -d -o pi -g pi /home/pi/printer_data/config

# Clone/update Moonraker as pi (keeps ownership correct)
runuser -u pi -- bash -lc '
  set -eux
  if [ ! -d "$HOME/moonraker/.git" ]; then
    git clone --depth=1 https://github.com/Arksine/moonraker.git "$HOME/moonraker"
  else
    git -C "$HOME/moonraker" fetch --depth=1 origin
    git -C "$HOME/moonraker" reset --hard origin/master
  fi
'

# Install Moonraker as pi; skip systemctl in chroot
runuser -u pi -- bash -lc '
  set -eux
  cd "$HOME/moonraker"
  MOONRAKER_DISABLE_SYSTEMCTL=1 ./scripts/install-moonraker.sh \
    -f -c "$HOME/printer_data/config/moonraker.conf"
'
