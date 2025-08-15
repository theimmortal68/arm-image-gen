#!/usr/bin/env bash
set -euox pipefail
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap

# Remove policy-rc.d if present (prevents services from starting in chroot)
rm -f /usr/sbin/policy-rc.d
echo "[unblock] ensured /usr/sbin/policy-rc.d is absent"

# Remove any preset that disables services by default
rm -f /etc/systemd/system-preset/00-disable-all.preset || true
# Also clear any similar “disable all” presets if they exist
if [ -d /etc/systemd/system-preset ]; then
  find /etc/systemd/system-preset -maxdepth 1 -type f -name '*disable*all*.preset' -exec rm -f {} +
fi
echo "[unblock] ensured no 'disable-all' systemd presets remain"

# No systemctl actions here — enabling happens later via wants/ symlinks
echo "[unblock] done"
