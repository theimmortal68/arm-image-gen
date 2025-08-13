#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

# Make sure nginx stays quiet if not installed on some base
if is_in_apt nginx; then
  apt-get update
  apt-get install -y --no-install-recommends nginx || true
  systemctl_if_exists enable nginx || true
  systemctl_if_exists daemon-reload || true
  echo_green "[nginx] ensured installed/enabled"
else
  echo_red "[nginx] not available in apt on this base"
fi
