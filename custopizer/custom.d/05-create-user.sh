
#!/usr/bin/env bash
set -euo pipefail
source /root/.custopizer_user_env || true

if [ -z "${KS_USER:-}" ]; then
  KS_USER="pi"
fi

if ! id "${KS_USER}" >/dev/null 2>&1; then
  echo "[customizer] Creating user: ${KS_USER}"
  useradd -m -s /bin/bash "${KS_USER}"
  echo "${KS_USER}:${KS_USER}" | chpasswd
  usermod -aG sudo "${KS_USER}" || true
else
  echo "[customizer] User already exists: ${KS_USER}"
fi

echo "KS_USER=${KS_USER}" > /root/.custopizer_user_env
