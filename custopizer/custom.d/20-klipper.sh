
#!/usr/bin/env bash
set -euo pipefail
source /root/.custopizer_user_env || true
USER="${KS_USER}"
: "${USER:?KS_USER not set}"
HOME_DIR="$(getent passwd "${USER}" | cut -d: -f6)"

su - "${USER}" -c "git clone --depth=1 https://github.com/Klipper3d/klipper ${HOME_DIR}/klipper"
su - "${USER}" -c "python3 -m venv ${HOME_DIR}/klippy-env"
su - "${USER}" -c "${HOME_DIR}/klippy-env/bin/pip install -U pip wheel"
su - "${USER}" -c "${HOME_DIR}/klippy-env/bin/pip install -r ${HOME_DIR}/klipper/scripts/klippy-requirements.txt"

if [ ! -f "${HOME_DIR}/printer.cfg" ]; then
  su - "${USER}" -c "cp ${HOME_DIR}/klipper/config/printer-anycubic-kobra-go-2022.cfg ${HOME_DIR}/printer.cfg || touch ${HOME_DIR}/printer.cfg"
fi

cat >/etc/systemd/system/klipper.service <<EOF
[Unit]
Description=Klipper 3D printer firmware
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${USER}
ExecStart=${HOME_DIR}/klippy-env/bin/python ${HOME_DIR}/klipper/klippy/klippy.py ${HOME_DIR}/printer.cfg -l ${HOME_DIR}/klipper.log
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable klipper || true
