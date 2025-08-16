#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Klipper Linear Movement Vibrations Analysis
# Upstream docs: clone then run the repo's install.sh. :contentReference[oaicite:0]{index=0}
# We run everything as the target user; no sudo inside chroot.

# Target user/home
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive

# Minimal prereqs to fetch and run installer
apt-get update
apt-get install -y --no-install-recommends git ca-certificates curl

# Clone (no idempotence: will error if dir already exists)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/worksasintended/klipper_linear_movement_analysis.git
'

# Run upstream installer (handles copying module, python deps, etc.)
# NOTE: Installation (matplotlib build) is heavy; avoid doing this while printing. :contentReference[oaicite:1]{index=1}
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  bash "$HOME/klipper_linear_movement_analysis/install.sh"
'

# Ensure an output directory visible in UIs (matches README example path)
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config/linear_vibrations"

# Add/refresh Moonraker Update Manager block
CFG_DIR="${HOME_DIR}/printer_data/config"
CFG="${CFG_DIR}/moonraker.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" "${CFG_DIR}"
[ -e "${CFG}" ] || install -m 0644 -o "${KS_USER}" -g "${KS_USER}" /dev/null "${CFG}"

TMP="$(mktemp)"
awk '
  BEGIN{skip=0}
  /^\[update_manager[[:space:]]+LinearMovementAnalysis\]/{skip=1; next}
  skip && /^\[/{skip=0}
  !skip{print}
' "${CFG}" > "${TMP}"
printf "\n" >> "${TMP}"
cat >> "${TMP}" <<EOF
[update_manager LinearMovementAnalysis]
type: git_repo
path: ${HOME_DIR}/klipper_linear_movement_analysis
primary_branch: main
origin: https://github.com/worksasintended/klipper_linear_movement_analysis.git
install_script: install.sh
env: ${HOME_DIR}/klippy-env/bin/python
requirements: requirements.txt
managed_services: klipper
EOF
install -m 0644 -o "${KS_USER}" -g "${KS_USER}" "${TMP}" "${CFG}"
rm -f "${TMP}"

# Record revision in manifest (optional)
if [ -d "${HOME_DIR}/klipper_linear_movement_analysis/.git" ]; then
  rev="$(git -C "${HOME_DIR}/klipper_linear_movement_analysis" rev-parse --short HEAD || true)"
  install -d -m 0755 /etc
  printf 'KLMA\t%s\n' "${rev:-unknown}" >> /etc/ks-manifest.txt
fi

systemctl_if_exists daemon-reload || true
echo_green "[KLMA] installed via upstream install.sh; Update Manager configured"
