
#!/usr/bin/env bash
set -euo pipefail

if [ -n "${KS_USER:-}" ]; then
  USER="$KS_USER"
else
  USER="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd || true)"
fi

if [ -z "${USER:-}" ]; then
  echo "[customizer] No non-root user detected; later step will create one."
else
  echo "[customizer] Using existing user: ${USER}"
fi

echo "KS_USER=${USER:-}" > /root/.custopizer_user_env
