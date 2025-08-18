#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Stage overlay from /files into / (and process *.append)"

# Use /files as the canonical overlay root (so staged assets live under custopizer/files/*)
FILES_DIR="/files"

if [ -d "${FILES_DIR}" ]; then
  echo_green "[15-stage-files] Staging overlay from: ${FILES_DIR}"

  # 1) Mirror everything EXCEPT:
  #    - any .git* metadata
  #    - any *.append files (handled in step 2)
  #    - top-level helper artifacts: ks_helpers.sh, systemctl
  rsync -aHAX --info=stats2 \
        --exclude='.git*' \
        --exclude='**/*.append' \
        --exclude='ks_helpers.sh' \
        --exclude='systemctl' \
        --chown=root:root \
        "${FILES_DIR}/" "/"

  # 2) Process all *.append files: append to same path minus .append
  mapfile -t APPENDS < <(find "${FILES_DIR}" -type f -name '*.append' | sort || true)
  for src in "${APPENDS[@]:-}"; do
    rel="${src#${FILES_DIR}/}"
    dest="/${rel%.append}"

    install -d -m 0755 -- "$(dirname -- "${dest}")"

    dest_existed=0
    [ -e "${dest}" ] && dest_existed=1

    if [ -f "${dest}" ] && [ -s "${dest}" ]; then
      lastchar="$(tail -c1 -- "${dest}" || true)"
      [ "${lastchar}" = $'\n' ] || printf '\n' >> "${dest}"
    fi

    cat -- "${src}" >> "${dest}"
    chown root:root "${dest}"
    [ "${dest_existed}" -eq 0 ] && chmod 0644 "${dest}"

    echo_green "[15-stage-files] appended: ${rel} -> ${dest}"
  done

  echo_green "[15-stage-files] Overlay staging complete."
else
  echo_yellow "[15-stage-files] No overlay directory at ${FILES_DIR}; skipping."
fi
