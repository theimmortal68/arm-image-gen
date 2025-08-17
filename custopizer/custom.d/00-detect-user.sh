#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Detecting/setting KS_USER"
if id "${KS_USER:-pi}" >/dev/null 2>&1; then
  :
else
  export KS_USER=pi
fi
echo "Using KS_USER=${KS_USER}"
