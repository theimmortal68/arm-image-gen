
#!/usr/bin/env bash
set -euo pipefail
source /root/.custopizer_user_env || true
USER="${KS_USER}"
: "${USER:?KS_USER not set}"
HOME_DIR="$(getent passwd "${USER}" | cut -d: -f6)"

su - "${USER}" -c "git clone --depth=1 https://github.com/mainsail-crew/crowsnest ${HOME_DIR}/crowsnest"
yes | make -C "${HOME_DIR}/crowsnest" install
systemctl enable crowsnest || true
