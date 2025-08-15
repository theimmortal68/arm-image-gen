#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# ... your existing Pi-only guards + APT pin code remains above ...

# --- Stage overlay files from ./files into /
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

if [ -d "${FILES_DIR}" ]; then
  echo_green "[15-stage-files] Staging overlay from: ${FILES_DIR}"

  # Ensure rsync is available (no helper dependency)
  if ! command -v rsync >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends rsync
  fi

  # Mirror the overlay into / (no --delete; overlay-only)
  rsync -aHAX --info=stats2 --exclude='.git*' \
        --chown=root:root \
        "${FILES_DIR}/" "/"

  # Normalize perms for known paths
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    chown root:root /etc/avahi/avahi-daemon.conf
    chmod 0644      /etc/avahi/avahi-daemon.conf
  fi
  if [ -f /var/log/ratos.log ]; then
    chown root:root /var/log/ratos.log
    chmod 0644      /var/log/ratos.log
  fi

  echo_green "[15-stage-files] Overlay staged."
else
  echo_yellow "[15-stage-files] No overlay directory at ${FILES_DIR}; skipping."
fi
