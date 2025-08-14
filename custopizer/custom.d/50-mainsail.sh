#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap
export DEBIAN_FRONTEND=noninteractive

# Ensure nginx (best-effort)
if is_in_apt nginx-light && ! is_installed nginx-light; then
  apt-get update || true
  apt-get install -y --no-install-recommends nginx-light unzip ca-certificates curl || true
fi

# Install Mainsail (latest release ZIP)
TMP=$(mktemp -d)
URL="https://api.github.com/repos/mainsail-crew/mainsail/releases/latest"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  TAG=$(curl -fsSL "$URL" | jq -r '.tag_name')
  ZIP_URL="https://github.com/mainsail-crew/mainsail/releases/download/${TAG}/mainsail.zip"
else
  ZIP_URL="https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip"
fi

mkdir -p /var/www/mainsail
curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "${TMP}/mainsail.zip" "$ZIP_URL"
unzip -o "${TMP}/mainsail.zip" -d /var/www/mainsail

# nginx site may already be staged; ensure dirs exist
install -d /etc/nginx/sites-available /etc/nginx/sites-enabled
if [ ! -f /etc/nginx/sites-available/mainsail ]; then
  cat >/etc/nginx/sites-available/mainsail <<'NGX'
server {
  listen 80 default_server;
  server_name _;
  root /var/www/mainsail;
  index index.html;
  location / { try_files $uri $uri/ /index.html; }
  location ~* \.(?:js|css|png|jpg|jpeg|gif|svg|ico|woff2?)$ {
    expires 7d; add_header Cache-Control "public";
  }
}
NGX
  ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
fi

test -s /var/www/mainsail/index.html
echo "[mainsail] installed to /var/www/mainsail"
