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

  # rsync preserves perms/timestamps/xattrs and respects symlinks; force root:root on dest
  # We avoid --delete here (overlay-only behavior).
  apt_get_ensure rsync
  rsync -aHAX --info=stats2 --exclude='.git*' \
        --chown=root:root \
        "${FILES_DIR}/" "/"

  # Normalize/ensure perms for known paths (overlay can provide initial content)
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    chown root:root /etc/avahi/avahi-daemon.conf
    chmod 0644      /etc/avahi/avahi-daemon.conf
  fi

  # Ensure log file exists with sane perms (overlay supplies it; keep it world-readable)
  if [ -f /var/log/ratos.log ]; then
    chown root:root /var/log/ratos.log
    chmod 0644      /var/log/ratos.log
  fi

  echo_green "[15-stage-files] Overlay staged."
else
  echo_yellow "[15-stage-files] No overlay directory at ${FILES_DIR}; skipping."
fi

# ... your existing tail of the script (if any) ...
