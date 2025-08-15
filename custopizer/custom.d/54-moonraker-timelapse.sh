#!/bin/bash
set -Eeuo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

#--- discover user/home set by our earlier user scripts ------------------------
if [[ -f /etc/ks-user.conf ]]; then
  # shellcheck disable=SC1091
  . /etc/ks-user.conf
fi
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "${KS_USER}" | cut -d: -f6 || true)"
HOME_DIR="${HOME_DIR:-/home/${KS_USER}}"

VENV="${HOME_DIR}/moonraker-env"
REPO_DIR="${HOME_DIR}/moonraker-timelapse"
REPO_URL="https://github.com/mainsail-crew/moonraker-timelapse.git"

echo "::group::moonraker-timelapse"

#--- sanity: venv must exist ---------------------------------------------------
if [[ ! -x "${VENV}/bin/pip" ]]; then
  echo_red "[timelapse] missing venv at ${VENV}"
  exit 1
fi

#--- fetch/update repo (run as user for sane ownership) ------------------------
if [[ ! -d "${REPO_DIR}/.git" ]]; then
  runuser -u "${KS_USER}" -- git clone --depth=1 "${REPO_URL}" "${REPO_DIR}"
else
  runuser -u "${KS_USER}" -- git -C "${REPO_DIR}" fetch --depth=1 origin || true
  runuser -u "${KS_USER}" -- git -C "${REPO_DIR}" reset --hard origin/HEAD || true
fi
chown -R "${KS_USER}:${KS_USER}" "${REPO_DIR}"

#--- install dependencies into moonraker venv ----------------------------------
pushd "${REPO_DIR}" >/dev/null
if [[ -f pyproject.toml || -f setup.py ]]; then
  # Repo became installable at some point
  "${VENV}/bin/pip" install --no-cache-dir -U pip wheel setuptools
  "${VENV}/bin/pip" install --no-cache-dir .
elif [[ -f requirements.txt ]]; then
  "${VENV}/bin/pip" install --no-cache-dir -U pip wheel setuptools
  "${VENV}/bin/pip" install --no-cache-dir -r requirements.txt
else
  echo_yellow "[timelapse] no pyproject/setup.py/requirements.txt found; assuming self-contained"
fi
popd >/dev/null

#--- pick an entrypoint for systemd --------------------------------------------
ENTRY=""
# 1) Installed module?
if "${VENV}/bin/python" - <<'PY'
import importlib, sys
sys.exit(0 if importlib.util.find_spec("moonraker_timelapse") else 1)
PY
then
  ENTRY="${VENV}/bin/python -m moonraker_timelapse"
else
  # 2) Run a common main file from the repo
  for cand in main.py timelapse.py app.py server.py run.py; do
    if [[ -f "${REPO_DIR}/${cand}" ]]; then
      ENTRY="${VENV}/bin/python ${REPO_DIR}/${cand}"
      break
    fi
  done
fi

if [[ -z "${ENTRY}" ]]; then
  echo_red "[timelapse] could not determine an entrypoint to run"
  ls -la "${REPO_DIR}" || true
  exit 1
fi

#--- systemd unit --------------------------------------------------------------
install -d /etc/systemd/system
cat >/etc/systemd/system/moonraker-timelapse.service <<EOF
[Unit]
Description=Moonraker Timelapse Service
After=network-online.target moonraker.service
Wants=network-online.target

[Service]
Type=simple
User=${KS_USER}
Group=${KS_USER}
WorkingDirectory=${REPO_DIR}
ExecStart=${ENTRY}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/moonraker-timelapse.service \
      /etc/systemd/system/multi-user.target.wants/moonraker-timelapse.service || true
systemctl_if_exists daemon-reload || true

#--- add update_manager block to moonraker.conf --------------------------------
CFG="${HOME_DIR}/printer_data/config/moonraker.conf"
install -d "$(dirname "${CFG}")"
touch "${CFG}"

if ! grep -q '^\[update_manager moonraker-timelapse\]' "${CFG}"; then
  cat >>"${CFG}" <<EOF

[update_manager moonraker-timelapse]
type: git_repo
path: ${REPO_DIR}
origin: ${REPO_URL}
primary_branch: master
managed_services: moonraker-timelapse
EOF
fi

echo_green "[timelapse] installed"
echo "::endgroup::"
