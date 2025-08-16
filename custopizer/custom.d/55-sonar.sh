#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

# Standard project header
source /common.sh; install_cleanup_trap

# Sonar (Mainsail Crew) — simple keepalive for Wi-Fi
# Upstream install flow (per README):
#   git clone https://github.com/mainsail-crew/sonar.git
#   cd ~/sonar
#   make config
#   sudo make install
# We run "make config" as the target user and "make install" as root. :contentReference[oaicite:0]{index=0}

# Target user/home
# shellcheck disable=SC1091
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive

# Minimal prerequisites
apt-get update
apt-get install -y --no-install-recommends \
  git make ca-certificates iputils-ping

# Clone upstream into the user's home (no idempotence: will fail if already exists)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME"
  git clone --depth=1 https://github.com/mainsail-crew/sonar.git
'

# Create default config in ~/printer_data/config/sonar.conf (upstream make target)
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME/sonar"
  make config
'

# Install service/system files as root (no sudo in chroot)
bash -lc "
  set -euo pipefail
  cd '${HOME_DIR}/sonar'
  make install
"

# Add Moonraker Update Manager block exactly as documented:
#   [update_manager sonar]
#   type: git_repo
#   path: ~/sonar
#   origin: https://github.com/mainsail-crew/sonar.git
#   primary_branch: main
#   managed_services: sonar
#   install_script: tools/install.sh
# (This enables 1-click updates from Mainsail.) :contentReference[oaicite:1]{index=1}
CFG_DIR="${HOME_DIR}/printer_data/config"
CFG="${CFG_DIR}/moonraker.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" "${CFG_DIR}"
[ -e "${CFG}" ] || install -m 0644 -o "${KS_USER}" -g "${KS_USER}" /dev/null "${CFG}"

TMP="$(mktemp)"
awk '
  BEGIN{skip=0}
  /^\[update_manager[[:space:]]+sonar\]/{skip=1; next}
  skip && /^\[/{skip=0}
  !skip{print}
' "${CFG}" > "${TMP}"
printf "\n" >> "${TMP}"
cat >> "${TMP}" <<EOF
[update_manager sonar]
type: git_repo
path: ${HOME_DIR}/sonar
origin: https://github.com/mainsail-crew/sonar.git
primary_branch: main
managed_services: sonar
install_script: tools/install.sh
EOF
install -m 0644 -o "${KS_USER}" -g "${KS_USER}" "${TMP}" "${CFG}"
rm -f "${TMP}"

# Reload units if supported; enabling/starting is handled by your 99-enable-units.sh
systemctl_if_exists daemon-reload || true

# Manifest (optional)
if [ -d "${HOME_DIR}/sonar/.git" ]; then
  rev="$(git -C "${HOME_DIR}/sonar" rev-parse --short HEAD || true)"
  install -d -m 0755 /etc
  printf 'Sonar\t%s\n' "${rev:-unknown}" >> /etc/ks-manifest.txt
fi

echo_green "[sonar] installed per upstream Make targets; Update Manager configured"
