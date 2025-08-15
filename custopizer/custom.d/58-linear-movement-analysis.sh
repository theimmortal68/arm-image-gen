#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Klipper Linear Movement Vibrations Analysis
# Repo: https://github.com/worksasintended/klipper_linear_movement_analysis
# Adds GCODE commands:
#   MEASURE_LINEAR_VIBRATIONS
#   MEASURE_LINEAR_VIBRATIONS_RANGE

# Target user/home
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive

# Minimal deps (git+pip). Numeric libs (numpy/matplotlib/atlas/fortran) are handled in 20-klipper.sh
apt-get update
apt-get install -y --no-install-recommends git ca-certificates python3-pip

# Clone (no idempotence: will error if dir exists)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/worksasintended/klipper_linear_movement_analysis.git
'

# Install Python requirements into the Klipper venv, then run upstream install.sh
# (install.sh copies the module into Klipper’s extras and does any repo-specific steps)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  VENV="$HOME/klippy-env"
  test -x "$VENV/bin/pip"
  "$VENV/bin/pip" install -U pip
  if [ -f "$HOME/klipper_linear_movement_analysis/requirements.txt" ]; then
    "$VENV/bin/pip" install --prefer-binary -r "$HOME/klipper_linear_movement_analysis/requirements.txt"
  fi
  cd "$HOME/klipper_linear_movement_analysis"
  bash ./install.sh
'

# Ensure an output directory users can access via the UI
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config/linear_vibrations"

# Add/refresh a Moonraker Update Manager block (normalized name without the README typo)
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
echo_green "[KLMA] installed; Update Manager block added; output dir ready"
