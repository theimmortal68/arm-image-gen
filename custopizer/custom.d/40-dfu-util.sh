#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Build and install dfu-util from git"

# Build prerequisites
apt_install git ca-certificates curl \
  libusb-1.0-0-dev \
  autoconf automake libtool pkg-config build-essential \
  pandoc

install -d -m 0755 /usr/local/src
cd /usr/local/src

# No idempotence per your policy: fail if dir exists
if [ -e dfu-util ]; then
  echo_red "[dfu-util] /usr/local/src/dfu-util already exists"; exit 1
fi

# Clone with fallbacks
if git clone --depth=1 https://gitlab.com/dfu-util/dfu-util.git dfu-util; then
  :
elif git clone --depth=1 git://git.code.sf.net/p/dfu-util/dfu-util dfu-util; then
  :
else
  git clone --depth=1 https://git.code.sf.net/p/dfu-util/dfu-util dfu-util
fi

cd dfu-util

./autogen.sh
./configure --prefix=/usr/local
make -j"$(nproc)"
make install

# Record version in manifest (optional)
if command -v dfu-util >/dev/null 2>&1; then
  install -d -m 0755 /etc
  printf 'DFU-UTIL\t%s\n' "$(dfu-util --version | head -n1)" >> /etc/ks-manifest.txt
fi

echo_green "[dfu-util] built and installed from git"
apt_clean_all
