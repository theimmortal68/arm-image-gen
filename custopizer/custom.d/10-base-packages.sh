#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

KS_USER="${KS_USER:-pi}"

retry 4 2 apt-get update

# Core build/runtime deps (defensive: only install if present in apt)
PKGS=(
  ca-certificates curl wget git unzip rsync jq crudini
  python3 python3-venv python3-dev python3-pip
  build-essential gcc g++ make pkg-config
  libffi-dev libusb-1.0-0-dev libncurses-dev
  v4l-utils ffmpeg
  nginx
  avrdude stm32flash dfu-util
  # toolchains (if available on the chosen base)
  gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi
  gcc-avr binutils-avr avr-libc
)

TO_INSTALL=()
for p in "${PKGS[@]}"; do
  if is_in_apt "$p"; then TO_INSTALL+=("$p"); fi
done

if [ "${#TO_INSTALL[@]}" -gt 0 ]; then
  apt-get install -y --no-install-recommends "${TO_INSTALL[@]}"
else
  echo_red "[base] WARN: no packages from list were available in apt"
fi

# Ensure user exists and has useful groups for serial/video
if ! id -u "$KS_USER" >/dev/null 2>&1; then
  useradd -m -G sudo,video,plugdev,dialout,tty "$KS_USER"
else
  usermod -aG video,plugdev,dialout,tty "$KS_USER" || true
fi

# Prepare printer_data tree
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
install -d -o "$KS_USER" -g "$KS_USER" \
  "$HOME_DIR/printer_data/config" \
  "$HOME_DIR/printer_data/logs" \
  "$HOME_DIR/bin"

echo_green "[base] packages installed and user prepared"
