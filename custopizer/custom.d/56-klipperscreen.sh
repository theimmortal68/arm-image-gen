#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# KlipperScreen install + Moonraker Update Manager block
# Repo: https://github.com/jordanruthe/KlipperScreen.git

# Target user/home
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive

# Core runtime/build deps (lean; add more GUI bits later if you choose Xorg/Wayland kiosk)
apt-get update
apt-get install -y --no-install-recommends \
  git ca-certificates python3-venv python3-pip \
  libglib2.0-0 libgtk-3-0 libmtdev1 \
  libjpeg62-turbo libtiff5 libopenjp2-7 libfreetype6 \
  libsdl2-image-2.0-0 libsdl2-ttf-2.0-0 \
  fonts-dejavu-core

# Clone upstream (no idempotence: will error if already present)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/jordanruthe/KlipperScreen.git
'

# Create dedicated venv and install requirements
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  python3 -m venv "$HOME/.KlipperScreen-env"
  "$HOME/.KlipperScreen-env/bin/pip" install -U pip wheel setuptools
  req="$HOME/KlipperScreen/scripts/KlipperScreen-requirements.txt"
  if [ -f "$req" ]; then
    "$HOME/.KlipperScreen-env/bin/pip" install --prefer-binary -r "$req"
  else
    "$HOME/.KlipperScreen-env/bin/pip" install --prefer-binary "$HOME/KlipperScreen"
  fi
'

# Systemd service (leave enablement to your 99-enable-units.sh)
cat >/etc/systemd/system/KlipperScreen.service <<EOF
[Unit]
Description=KlipperScreen (touchscreen GUI for Klipper)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${KS_USER}
Environment=PYTHONUNBUFFERED=1
ExecStart=${HOME_DIR}/.KlipperScreen-env/bin/python ${HOME_DIR}/KlipperScreen/screen.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Moonraker Update Manager block (append fresh; strip any existing block)
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
origin: https://github.com/jordanruthe/KlipperScreen.git
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
echo_green "[KlipperScreen] installed and update_manager block added"
