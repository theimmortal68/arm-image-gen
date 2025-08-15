#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Build dfu-util from git (GitLab preferred; fall back to SourceForge)
# Upstream needs autotools when cloning from git: autoconf, automake (aclocal), libtool, pkg-config, compiler.
# You also asked for pandoc and libusb-1.0-0-dev.

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  git ca-certificates curl \
  libusb-1.0-0-dev \
  autoconf automake libtool pkg-config build-essential \
  pandoc

install -d -m 0755 /usr/local/src
cd /usr/local/src

# Honor "no idempotence": fail if the dir already exists
if [ -e dfu-util ]; then
  echo_red "[dfu-util] /usr/local/src/dfu-util already exists"; exit 1
fi

# Clone with fallbacks (network fallback only; still fails if dir exists)
if git clone --depth=1 https://gitlab.com/dfu-util/dfu-util.git dfu-util; then
  : # ok
elif git clone --depth=1 git://git.code.sf.net/p/dfu-util/dfu-util dfu-util; then
  : # ok
else
  git clone --depth=1 https://git.code.sf.net/p/dfu-util/dfu-util dfu-util
fi

cd dfu-util

# Autotools bootstrap + configure + build + install
# (Using autogen.sh, which runs autoreconf -i under the hood.)
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
