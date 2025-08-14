#!/bin/bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

if [ -s /etc/.resolvconf-original ] && [ -e "$(cat /etc/.resolvconf-original)" ]; then
  rm -f /etc/resolv.conf
  ln -s "$(cat /etc/.resolvconf-original)" /etc/resolv.conf || true
  rm -f /etc/.resolvconf-original
  echo_green "[net] restored resolv.conf symlink"
else
  echo_green "[net] keeping static resolv.conf"
fi
