
#!/usr/bin/env bash
set -euo pipefail
source /root/.custopizer_user_env || true
USER="${KS_USER}"
: "${USER:?KS_USER not set}"
HOME_DIR="$(getent passwd "${USER}" | cut -d: -f6)"

su - "${USER}" -c "git clone --depth=1 https://github.com/Arksine/moonraker ${HOME_DIR}/moonraker"
su - "${USER}" -c "python3 -m venv ${HOME_DIR}/moonraker-env"
su - "${USER}" -c "${HOME_DIR}/moonraker-env/bin/pip install -U pip wheel"
su - "${USER}" -c "${HOME_DIR}/moonraker-env/bin/pip install -r ${HOME_DIR}/moonraker/scripts/moonraker-requirements.txt"

cat >"${HOME_DIR}/moonraker.conf" <<'EOF'
[server]
host: 0.0.0.0
port: 7125
enable_debug_logging: False

[authorization]
trusted_clients:
  127.0.0.1
  ::1
cors_domains:
  *.local
  *.lan
  192.168.0.0/16
  10.0.0.0/8

[machine]
provider: systemd_cli

[octoprint_compat]

[history]

[virtual_sdcard]
path: ~/printer_data/gcodes

[database]

[update_manager]
channel: stable
EOF
chown "${USER}:${USER}" "${HOME_DIR}/moonraker.conf"

cat >/etc/systemd/system/moonraker.service <<EOF
[Unit]
Description=Moonraker API Server
After=network-online.target klipper.service
Requires=network-online.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=${HOME_DIR}
ExecStart=${HOME_DIR}/moonraker-env/bin/python ${HOME_DIR}/moonraker/moonraker/moonraker.py -c ${HOME_DIR}/moonraker.conf
Restart=on-failure
RestartSec=3
SyslogIdentifier=moonraker

[Install]
WantedBy=multi-user.target
EOF

systemctl enable moonraker || true
