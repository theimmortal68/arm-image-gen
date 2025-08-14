#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Raspberry Pi repository for Bookworm
install -d /etc/apt/keyrings
# Prefer keyring package if available
apt-get -o Acquire::Retries=3 update || true
apt-get -y install raspberrypi-archive-keyring || true

cat >/etc/apt/sources.list.d/raspi.list <<'EOF'
deb http://archive.raspberrypi.org/debian/ bookworm main
# Optional firmware/channel components if you need them later:
# deb http://raspbian.raspberrypi.org/raspbian/ bookworm main contrib non-free rpi
EOF

# Pin RPi-origin libcamera stack to avoid libcamera-ipa/libcamera0 mismatches
cat >/etc/apt/preferences.d/99-raspi-camera.pref <<'EOF'
Package: libcamera* libcaml* libepoxy* libdrm* libv4l-0* libv4l2rds*
Pin: origin "archive.raspberrypi.org"
Pin-Priority: 1001
EOF

apt-get -o Acquire::Retries=3 update
