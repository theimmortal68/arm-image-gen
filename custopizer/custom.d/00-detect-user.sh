#!/bin/bash
set -x
set -e
export LC_ALL=C

source /common.sh
install_cleanup_trap

# If KS_USER already provided (e.g. via workflow), keep it.
if [ -n "${KS_USER:-}" ]; then
  CANDIDATE="$KS_USER"
else
  # Try to detect an existing non-system user we could adopt
  for u in pi ubuntu debian armbian orangepi; do
    if getent passwd "$u" >/dev/null 2>&1; then
      CANDIDATE="$u"
      break
    fi
  done
  CANDIDATE="${CANDIDATE:-pi}"
fi

# Persist for subsequent scripts (env doesn't persist between scripts)
echo "KS_USER=${CANDIDATE}" >/etc/ks-user.conf
echo_green "[detect-user] KS_USER=${CANDIDATE} (written to /etc/ks-user.conf)"
