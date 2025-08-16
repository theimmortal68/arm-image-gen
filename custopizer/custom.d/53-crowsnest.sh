#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Crowsnest (webcam daemon) — install per upstream instructions:
#   cd ~
#   git clone https://github.com/mainsail-crew/crowsnest.git
#   cd ~/crowsnest
#   sudo make install
# We clone as the target user, then run make install as root (no sudo in chroot).

# Target user/home
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git make ca-certificates

# Clone upstream (no idempotence: will fail if already present)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git
'

# Install as root (upstream make target handles deps/services)
bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/crowsnest'
  make install
"

# Add/refresh Moonraker Update Manager block exactly as the docs show
CFG_DIR="${HOME_DIR}/printer_data/config"
CFG="${CFG_DIR}/moonraker.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" "${CFG_DIR}"
[ -e "${CFG}" ] || install -m 0644 -o "${KS_USER}" -g "${KS_USER}" /dev/null "${CFG}"

TMP="$(mktemp)"
awk '
  BEGIN{skip=0}
  /^\[update_manager[[:space:]]+crowsnest\]/{skip=1; next}
  skip && /^\[/{skip=0}
  !skip{print}
' "${CFG}" > "${TMP}"
printf "\n" >> "${TMP}"
cat >> "${TMP}" <<EOF
[update_manager crowsnest]
type: git_repo
path: ${HOME_DIR}/crowsnest
origin: https://github.com/mainsail-crew/crowsnest.git
install_script: tools/pkglist.sh
EOF
install -m 0644 -o "${KS_USER}" -g "${KS_USER}" "${TMP}" "${CFG}"
rm -f "${TMP}"

# Optional: record revision
if [ -d "${HOME_DIR}/crowsnest/.git" ]; then
  rev="$(git -C "${HOME_DIR}/crowsnest" rev-parse --short HEAD || true)"
  install -d -m 0755 /etc
  printf 'Crowsnest\t%s\n' "${rev:-unknown}" >> /etc/ks-manifest.txt
fi

systemctl_if_exists daemon-reload || true
echo_green "[crowsnest] installed via make; Update Manager configured"
