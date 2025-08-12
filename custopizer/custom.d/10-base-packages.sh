
#!/usr/bin/env bash
set -euo pipefail
source /root/.custopizer_user_env || true
USER="${KS_USER}"
: "${USER:?KS_USER not set}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends   git curl wget unzip ca-certificates   build-essential gcc make pkg-config   python3 python3-venv python3-dev python3-pip python3-numpy python3-cffi libffi-dev   libusb-1.0-0-dev libncurses-dev   gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi   gcc-avr binutils-avr avr-libc avrdude stm32flash dfu-util   ffmpeg v4l-utils   nginx

usermod -aG dialout,tty,video,render,spi,i2c "${USER}" || true
