#!/usr/bin/env bash
# 54-sonar.sh — Install Sonar (WiFi keepalive) via unattended Makefile flow (no /files/00-config)
# - Mirrors MainsailOS: create ./tools/.config → make install
# - Detects target user from ks_helpers and/or /etc/ks-user.conf
# - NO data-path creation here (02-user handles printer_data/*)
# - Grants temporary sudo NOPASSWD for the build (remove later in hardening)
# - Creates Moonraker Update Manager entry via um_write_repo (with fallback)
# - Service enablement is deferred to 99-enable-units

set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

########################################
# Common helpers                       #
########################################
source /common.sh
install_cleanup_trap
# Optional repo-specific helpers
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh || true

########################################
# Resolve target user/home             #
########################################
# Priority: /etc/ks-user.conf → ks_helpers (USER_NAME/USER_HOME) → defaults
if [ -r /etc/ks-user.conf ]; then
  # shellcheck disable=SC1091
  . /etc/ks-user.conf
fi

if [ -z "${BASE_USER:-}" ]; then
  if [ -n "${KS_USER:-}" ]; then
    BASE_USER="${KS_USER}"
  elif [ -n "${USER_NAME:-}" ]; then
    BASE_USER="${USER_NAME}"
  else
    BASE_USER="pi"
  fi
fi

if [ -z "${HOME_DIR:-}" ]; then
  if [ -n "${USER_HOME:-}" ]; then
    HOME_DIR="${USER_HOME}"
  else
    HOME_DIR="/home/${BASE_USER}"
  fi
fi

########################################
# Config & deps                        #
########################################
readonly REPO="https://github.com/mainsail-crew/sonar.git"
readonly BRANCH="main"
# MainsailOS installs git; we also ensure 'make' is present
readonly DEPS=(git make)

########################################
# Prep sudo (avoid prompts in CI)      #
########################################
install -d -m0750 -o root -g root /etc/sudoers.d
chown root:root /etc/sudoers.d
find /etc/sudoers.d -type f -exec chown root:root {} \; -exec chmod 0440 {} \; || true
install -D -m0440 /dev/stdin "/etc/sudoers.d/999-custopizer-${BASE_USER}-all" <<EOF
${BASE_USER} ALL=(ALL) NOPASSWD:ALL
EOF

########################################
# APT deps                             #
########################################
apt-get update
apt-get install --yes --no-install-recommends "${DEPS[@]}"

########################################
# Clone or refresh repo                #
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

# Write installer config to skip TUI, add UM integration, and set data path
install -D -m0644 /dev/stdin "./tools/.config" <<EOF
BASE_USER="${BASE_USER}"
SONAR_DATA_PATH="${HOME_DIR}/printer_data"
SONAR_ADD_SONAR_MOONRAKER="1"
SONAR_UNATTENDED="1"
EOF

# Avoid any tput/ANSI issues; UNATTENDED should bypass prompts anyway
export TERM=xterm-256color

# Run the upstream installer (as root; it will sudo internally for user-level ops)
make install

# Clean up the temporary installer config
rm -f ./tools/.config

popd >/dev/null

########################################
# Moonraker Update Manager include     #
########################################
# um_write_repo <name> <path> <origin> <branch> [managed_services] [install_script]
um_write_repo "sonar" "${HOME_DIR}/sonar" "https://github.com/mainsail-crew/sonar.git" "main" "sonar" "tools/install.sh"

########################################
# NOTE: Service enabling is handled by
# 99-enable-units, so we do nothing here
########################################

echo "[sonar] install complete — user=${BASE_USER} data_path=${HOME_DIR}/printer_data"
