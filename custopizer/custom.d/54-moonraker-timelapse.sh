#!/bin/bash
set -euox pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Resolve target user written by your user-setup
BASE_USER="$(. /etc/ks-user.env; echo "${KS_USER:-pi}")"
HOME_DIR="/home/${BASE_USER}"

REPO="https://github.com/mainsail-crew/moonraker-timelapse.git"
SRC_DIR="${HOME_DIR}/moonraker-timelapse"
MOONRAKER_COMPONENTS="${HOME_DIR}/moonraker/moonraker/components"
PRINTER_CFG_DIR="${HOME_DIR}/printer_data/config"
MOONRAKER_CONFIG="${PRINTER_CFG_DIR}/moonraker.conf"

apt-get update
apt-get install -y --no-install-recommends git ffmpeg ca-certificates

# Clone or fast-update
if [[ ! -d "${SRC_DIR}/.git" ]]; then
  git clone --depth=1 "${REPO}" "${SRC_DIR}"
else
  git -C "${SRC_DIR}" fetch --depth=1 origin
  git -C "${SRC_DIR}" reset --hard origin/HEAD || true
fi
chown -R "${BASE_USER}:${BASE_USER}" "${SRC_DIR}"

# Link the Moonraker component
install -d -o "${BASE_USER}" -g "${BASE_USER}" "${MOONRAKER_COMPONENTS}"
ln -sf "${SRC_DIR}/component/timelapse.py" "${MOONRAKER_COMPONENTS}/timelapse.py"
chown -h "${BASE_USER}:${BASE_USER}" "${MOONRAKER_COMPONENTS}/timelapse.py"

# Link macros into printer_data/config (if that tree already exists)
if [[ -d "${PRINTER_CFG_DIR}" ]]; then
  ln -sf "${SRC_DIR}/klipper_macro/timelapse.cfg" "${PRINTER_CFG_DIR}/timelapse.cfg"
  chown -h "${BASE_USER}:${BASE_USER}" "${PRINTER_CFG_DIR}/timelapse.cfg"
fi

# Append Moonraker config snippet once, if you staged it via /files
if [[ -f "${MOONRAKER_CONFIG}" && -f /files/moonraker/timelapse.conf ]]; then
  if ! grep -q '^\[timelapse\]' "${MOONRAKER_CONFIG}"; then
    cat /files/moonraker/timelapse.conf >> "${MOONRAKER_CONFIG}"
  fi
fi

echo_green "[timelapse] installed (linked component + macros)"
