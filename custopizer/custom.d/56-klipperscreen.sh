#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# KlipperScreen install via upstream script
# Uses:
#   cd ~
#   git clone https://github.com/KlipperScreen/KlipperScreen.git
#   SERVICE=Y BACKEND=X NETWORK=N START=0 ./KlipperScreen/scripts/KlipperScreen-install.sh

# Target user/home
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive

# Minimal prerequisites (installer handles system deps via sudo)
apt-get update
apt-get install -y --no-install-recommends git ca-certificates curl sudo

# Clone upstream into the user's home (no idempotence: will fail if already exists)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/KlipperScreen/KlipperScreen.git
'

# Run upstream installer with requested flags (service enabled, Xorg backend, no network tweaks, do not start now)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  SERVICE=Y BACKEND=X NETWORK=N START=0 ./KlipperScreen/scripts/KlipperScreen-install.sh
'

# Moonraker Update Manager block (strip existing, then append fresh)
CFG_DIR="${HOME_DIR}/printer_data/config"
CFG="${CFG_DIR}/moonraker.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" "${CFG_DIR}"
[ -e "${CFG}" ] || install -m 0644 -o "${KS_USER}" -g "${KS_USER}" /dev/null "${CFG}"

TMP="$(mktemp)"
awk '
  BEGIN{skip=0}
  /^\[update_manager[[:space:]]+KlipperScreen\]/{skip=1; next}
  skip && /^\[/{skip=0}
  !skip{print}
' "${CFG}" > "${TMP}"
printf "\n" >> "${TMP}"
cat >> "${TMP}" <<EOF
[update_manager KlipperScreen]
type: git_repo
path: ${HOME_DIR}/KlipperScreen
origin: https://github.com/KlipperScreen/KlipperScreen.git
virtualenv: ${HOME_DIR}/.KlipperScreen-env
requirements: scripts/KlipperScreen-requirements.txt
system_dependencies: scripts/system-dependencies.json
managed_services: KlipperScreen
EOF
install -m 0644 -o "${KS_USER}" -g "${KS_USER}" "${TMP}" "${CFG}"
rm -f "${TMP}"

# Record revision in manifest (optional)
if [ -d "${HOME_DIR}/KlipperScreen/.git" ]; then
  rev="$(git -C "${HOME_DIR}/KlipperScreen" rev-parse --short HEAD || true)"
  install -d -m 0755 /etc
  printf 'KlipperScreen\t%s\n' "${rev:-unknown}" >> /etc/ks-manifest.txt
fi

systemctl_if_exists daemon-reload || true
echo_green "[KlipperScreen] installed via upstream script (SERVICE=Y BACKEND=X NETWORK=N START=0); Update Manager configured"
