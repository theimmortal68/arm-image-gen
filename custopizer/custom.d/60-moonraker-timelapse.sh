
#!/usr/bin/env bash
set -euo pipefail
source /root/.custopizer_user_env || true
USER="${KS_USER}"
: "${USER:?KS_USER not set}"
HOME_DIR="$(getent passwd "${USER}" | cut -d: -f6)"

su - "${USER}" -c "git clone --depth=1 https://github.com/mainsail-crew/moonraker-timelapse ${HOME_DIR}/moonraker-timelapse"
su - "${USER}" -c "${HOME_DIR}/moonraker-env/bin/pip install -U pip wheel"
su - "${USER}" -c "${HOME_DIR}/moonraker-env/bin/pip install ${HOME_DIR}/moonraker-timelapse"

grep -q '^[[]timelapse[]]' "${HOME_DIR}/moonraker.conf" 2>/dev/null || cat >> "${HOME_DIR}/moonraker.conf" <<'EOF'

[timelapse]
output_path: ~/printer_data/timelapse
ffmpeg_binary_path: /usr/bin/ffmpeg
camera: stream
EOF

chown -R "${USER}:${USER}" "${HOME_DIR}/moonraker-timelapse" "${HOME_DIR}/moonraker.conf"
