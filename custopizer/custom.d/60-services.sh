#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Enable core services (CustoPiZer blocks starting during build)
for s in klipper.service moonraker.service crowsnest.service nginx.service; do
  if [ -f "/etc/systemd/system/$s" ] || systemctl_if_exists status "$s" >/dev/null 2>&1; then
    systemctl_if_exists enable "$s" || true
  fi
done

echo_green "[services] enabled (will start on first boot)"
