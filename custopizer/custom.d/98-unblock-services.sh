#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Unblocking service starts on target system"
# CustoPiZer usually installs a policy-rc.d to block starts; ensure removed
rm -f /usr/sbin/policy-rc.d || true

# Daemon reload best-effort
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
