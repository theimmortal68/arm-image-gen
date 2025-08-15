#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# dfu-util from source
# Primary: https://gitlab.com/dfu-util/dfu-util.git
# Fallbacks: git://git.code.sf.net/p/dfu-util/dfu-util  (or https://git.code.sf.net/p/dfu-util/dfu-util)

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  libusb-1.0-0-dev autoconf pandoc

# NOTE: If your base image doesn't already have a toolchain for autoconf builds,
# you may need these too (uncomment if required):
# apt-get install -y --no-install-recommends build-essential automake libtool pkg-config

install -d -m 0755 /usr/local/src
cd /usr/local/src

# Clone with fallbacks
rm -rf dfu-util
if git clone --depth=1 https://gitlab.com/dfu-util/dfu-util.git dfu-util; then
  :
elif git clone --depth=1 git://git.code.sf.net/p/dfu-util/dfu-util dfu-util; then
  :
else
  git clone --depth=1 https://git.code.sf.net/p/dfu-util/dfu-util dfu-util
fi

cd dfu-util

# Autotools build
./autogen.sh
./configure --prefix=/usr/local
make -j"$(nproc)"
make install

# Record version in manifest (optional)
if command -v dfu-util >/dev/null 2>&1; then
  install -d -m 0755 /etc
  printf 'DFU-UTIL\t%s\n' "$(dfu-util --version | head -n1)" >> /etc/ks-manifest.txt
fi
