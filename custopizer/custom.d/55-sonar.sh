#!/usr/bin/env bash
# 54-sonar.sh — Install Sonar (WiFi keepalive) via unattended Makefile flow à la MainsailOS
# - Mirrors MainsailOS flow: create ./tools/.config, then `make install`
# - Non-interactive, chroot-safe; relies on /common.sh helpers (install_cleanup_trap, systemctl_if_exists)
# - Ensures ~/printer_data exists and is user-owned to avoid permission issues seen earlier

set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

########################################
# Functions and Base Configuration     #
########################################

# CustoPiZer common helpers
source /common.sh
install_cleanup_trap

# Repo-specific helpers (optional)
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true

# Pull BASE_USER from /files/00-config if available (MainsailOS style).
# Fallback to previously detected KS_USER or 'pi'.
if [ -r /files/00-config ]; then
  # shellcheck disable=SC1091
  source /files/00-config
fi
: "${KS_USER:=pi}"
: "${BASE_USER:=${KS_USER}}"
: "${HOME_DIR:=/home/${BASE_USER}}"

########################################
# Tunables                             #
########################################

readonly REPO="https://github.com/mainsail-crew/sonar.git"
readonly BRANCH="main"
readonly DEPS=(git make)

########################################
# Prepare sudo (avoid password prompts)
########################################

# Some upstream installers call sudo internally; ensure noninteractive success in CI.
if command -v install >/dev/null 2>&1; then
  install -d -m0750 -o root -g root /etc/sudoers.d
  # Fix ownership/mode in case earlier steps left it dirty
  chown root:root /etc/sudoers.d || true
  find /etc/sudoers.d -type f -exec chown root:root {} \; -exec chmod 0440 {} \; || true
  # Allow passwordless sudo for BASE_USER during build (remove in final hardening if desired)
  install -D -m0440 /dev/stdin /etc/sudoers.d/999-custopizer-${BASE_USER}-all <<EOF
${BASE_USER} ALL=(ALL) NOPASSWD:ALL
EOF
fi

########################################
# Install System Packages              #
########################################

apt-get update
apt-get install --yes --no-install-recommends "${DEPS[@]}"

########################################
# Ensure user data path                #
########################################

# Create ~/printer_data with proper ownership to avoid "Permission denied"
install -d -o "${BASE_USER}" -g "${BASE_USER}" "${HOME_DIR}/printer_data"
install -d -o "${BASE_USER}" -g "${BASE_USER}" "${HOME_DIR}/printer_data/config"
install -d -o "${BASE_USER}" -g "${BASE_USER}" "${HOME_DIR}/printer_data/logs"

########################################
# Clone or refresh repository          #
########################################

if [ ! -d "${HOME_DIR}/sonar/.git" ]; then
  pushd "${HOME_DIR}" >/dev/null
  sudo -u "${BASE_USER}" git clone -b "${BRANCH}" --depth=1 "${REPO}" sonar
  popd >/dev/null
else
  sudo -u "${BASE_USER}" git -C "${HOME_DIR}/sonar" fetch --depth=1 origin "${BRANCH}"
  sudo -u "${BASE_USER}" git -C "${HOME_DIR}/sonar" reset --hard "origin/${BRANCH}"
fi

########################################
# Unattended config & install          #
########################################

pushd "${HOME_DIR}/sonar" >/dev/null

# Prepare unattended config consumed by tools/install.sh via Makefile
install -D -m0644 /dev/stdin "./tools/.config" <<EOF
BASE_USER="${BASE_USER}"
SONAR_DATA_PATH="${HOME_DIR}/printer_data"
SONAR_ADD_SONAR_MOONRAKER="1"
SONAR_UNATTENDED="1"
EOF

# TERM helps avoid any tput/ANSI issues in CI logs, though UNATTENDED should bypass TUI
export TERM=xterm-256color

# Run install as the user; installer will sudo when needed
sudo -u "${BASE_USER}" make install

# Clean up the temporary config file
rm -f ./tools/.config

popd >/dev/null

########################################
# Enable Service (chroot-safe)         #
########################################

# Use /common.sh helper that no-ops if systemd isn't PID 1
systemctl_if_exists enable sonar.service || true
systemctl_if_exists daemon-reload || true

echo "[sonar] install complete — user=${BASE_USER} data_path=${HOME_DIR}/printer_data"
