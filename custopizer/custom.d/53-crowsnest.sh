#!/usr/bin/env bash
# 53-crowsnest.sh — Install Crowsnest only (no unit enable, no streamer install)
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

export DEBIAN_FRONTEND=noninteractive

: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

section "Clone/refresh Crowsnest as ${KS_USER}"
as_user "${KS_USER}" '
  if [ ! -d "$HOME/crowsnest/.git" ]; then
    git clone --depth=1 https://github.com/mainsail-crew/crowsnest.git "$HOME/crowsnest"
  else
    git -C "$HOME/crowsnest" fetch --depth=1 origin
    git -C "$HOME/crowsnest" reset --hard origin/master
  fi
'

section "Install Crowsnest binaries"
# Try upstream Makefile first (preferred)
set +e
as_user "${KS_USER}" '
  set -eux
  cd "$HOME/crowsnest"
  export MAKEFLAGS="--output-sync=line -j$(nproc)"
  sudo -En make install
'
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  section "Fallback: copy launcher"
  if [ -x "${HOME_DIR}/crowsnest/crowsnest" ]; then
    install -D -m0755 "${HOME_DIR}/crowsnest/crowsnest" /usr/local/bin/crowsnest
  elif [ -x "${HOME_DIR}/crowsnest/scripts/crowsnest.sh" ]; then
    install -D -m0755 "${HOME_DIR}/crowsnest/scripts/crowsnest.sh" /usr/local/bin/crowsnest
  else
    echo "ERROR: Crowsnest binary not found" >&2
    exit 1
  fi
fi

section "Write minimal config (if missing)"
install -d -o "${KS_USER}" -g "${KS_USER}" "${HOME_DIR}/printer_data/config"
CFG="${HOME_DIR}/printer_data/config/crowsnest.conf"
if [ ! -f "${CFG}" ]; then
  cat >"${CFG}" <<'EOF'
# Minimal Crowsnest config
[general]
port: 8080
EOF
  chown "${KS_USER}:${KS_USER}" "${CFG}"
fi

section "Service file (no enablement here)"
install -d -m0755 /etc/systemd/system
cat >/etc/systemd/system/crowsnest.service <<EOF
[Unit]
Description=Crowsnest camera manager
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${KS_USER}
Group=${KS_USER}
WorkingDirectory=${HOME_DIR}
ExecStart=/usr/local/bin/crowsnest -c ${HOME_DIR}/printer_data/config/crowsnest.conf
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

# No enablement here; 99-enable-units.sh will enable crowsnest + chosen backend.
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload || true

section "Crowsnest install complete"
