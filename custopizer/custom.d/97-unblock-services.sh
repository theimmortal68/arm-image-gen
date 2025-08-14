#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

[ -e /usr/sbin/policy-rc.d ] && { rm -f /usr/sbin/policy-rc.d; echo "[unblock] removed policy-rc.d"; }
[ -f /etc/systemd/system-preset/00-disable-all.preset ] && { rm -f /etc/systemd/system-preset/00-disable-all.preset; echo "[unblock] removed disable-all preset"; }
