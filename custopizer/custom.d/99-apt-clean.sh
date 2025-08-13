#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb || true
echo_green "[cleanup] apt caches cleared"
