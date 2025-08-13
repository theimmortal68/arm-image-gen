#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Basic serial device access for Klipper MCUs
cat >/etc/udev/rules.d/99-klipper-serial.rules <<'EOF'
KERNEL=="ttyUSB*", MODE="0666", GROUP="dialout"
KERNEL=="ttyACM*", MODE="0666", GROUP="dialout"
SUBSYSTEM=="tty", GROUP="dialout"
EOF

echo_green "[udev] serial rules installed"
