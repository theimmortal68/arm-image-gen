#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# 15-stage-files.sh
# - Pi-only guards + APT pin (camera stack preference when Raspberry Pi repo is present)
# - Stage everything from ./files/ into / (preserve modes, chown root:root)
# - Handle *.append files by appending to the matching destination (path without .append)
#
# Notes:
# - No idempotence checks by design (matches project conventions).
# - The overlay preserves the executable bit and modes you commit to git.

# ------------------------------
# Raspberry Pi APT pin (optional)
# ------------------------------
# If an RPi repo is configured, prefer its camera stack packages.
if grep -Rqs 'archive\.raspberrypi\.org' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  install -d -m 0755 /etc/apt/preferences.d
  cat > /etc/apt/preferences.d/99-raspi-camera-prefer <<'EOF'
Explanation: Prefer Raspberry Pi camera stack when Raspberry Pi repo is configured
Package: libcamera* libcamera-apps* libraspberrypi* rpicam* raspi-config*
Pin: origin archive.raspberrypi.org
Pin-Priority: 991
EOF
  echo_green "[15-stage-files] Installed Raspberry Pi APT pin (camera stack preference)"
fi

# ---------------------------------------
# Stage overlay from ./files into the root
# ---------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

if [ -d "${FILES_DIR}" ]; then
  echo_green "[15-stage-files] Staging overlay from: ${FILES_DIR}"

  # Ensure rsync is available (no helper dependency)
  if ! command -v rsync >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends rsync
  fi

  # 1) Mirror everything EXCEPT *.append; keep repo file modes, force root ownership.
  #    We do *not* use --delete (overlay-only behavior).
  rsync -aHAX --info=stats2 \
        --exclude='.git*' \
        --exclude='**/*.append' \
        --chown=root:root \
        "${FILES_DIR}/" "/"

  # 2) Process all *.append files: append their content to the destination
  #    (same path without the .append suffix). This supports things like:
  #      files/boot/firmware/config.txt.append  -> /boot/firmware/config.txt
  #    We ensure the destination ends with a newline before appending to avoid line-glue.
  mapfile -t APPENDS < <(find "${FILES_DIR}" -type f -name '*.append' | sort || true)
  for src in "${APPENDS[@]:-}"; do
    # Relative path under files/ and destination without .append
    rel="${src#${FILES_DIR}/}"
    dest="/${rel%.append}"

    # Make sure the parent exists
    install -d -m 0755 -- "$(dirname -- "${dest}")"

    # Track whether the destination pre-existed
    dest_existed=0
    [ -e "${dest}" ] && dest_existed=1

    # If dest exists and is non-empty, ensure it ends with a newline
    if [ -f "${dest}" ] && [ -s "${dest}" ]; then
      lastchar="$(tail -c1 -- "${dest}" || true)"
      if [ "${lastchar}" != $'\n' ]; then
        printf '\n' >> "${dest}"
      fi
    fi

    # Append the content
    cat -- "${src}" >> "${dest}"

    # Ensure root ownership; keep existing mode if file already existed
    chown root:root "${dest}"
    if [ "${dest_existed}" -eq 0 ]; then
      # New file created via append: set a sane default mode
      chmod 0644 "${dest}"
    fi

    echo_green "[15-stage-files] appended: ${rel} -> ${dest}"
  done

  echo_green "[15-stage-files] Overlay staging complete."
else
  echo_yellow "[15-stage-files] No overlay directory at ${FILES_DIR}; skipping."
fi
```0
