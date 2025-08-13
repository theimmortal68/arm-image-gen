#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

rm -f /usr/sbin/policy-rc.d || true
echo_green "[cleanup] removed policy-rc.d so services can start on first boot"
