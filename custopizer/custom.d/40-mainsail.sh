#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

# retry polyfill: usage → retry <attempts> <delay> <cmd...>
type retry >/dev/null 2>&1 || retry() {
  local tries="$1"; local delay="$2"; shift 2
  local n=0
  until "$@"; do
    n=$((n+1))
    [ "$n" -ge "$tries" ] && return 1
    sleep "$delay"
  done
}

KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "User $KS_USER missing"; exit 1; }

retry 4 2 apt-get update
is_in_apt nginx || { echo_red "[mainsail] nginx not available"; exit 1; }
apt-get install -y --no-install-recommends nginx || true

WEBROOT="$HOME_DIR/mainsail"
mkdir -p "$WEBROOT"
chown -R "$KS_USER:$KS_USER" "$WEBROOT"

# Fetch latest mainsail release (strict-ish)
TAG="$(curl -fsSL https://api.github.com/repos/mainsail-crew/mainsail/releases/latest | jq -r .tag_name)" || true
[ -n "$TAG" ] || TAG="v2.10.1"
TARBALL="mainsail-${TAG}.zip"
URL="https://github.com/mainsail-crew/mainsail/releases/download/${TAG}/${TARBALL}"

TMP="/tmp/${TARBALL}"
wget -O "$TMP" "$URL"
sudo -u "$KS_USER" unzip -o "$TMP" -d "$WEBROOT"
# Flatten if it extracted into a nested dir
if [ -d "$WEBROOT/mainsail" ]; then
  rsync -a "$WEBROOT/mainsail/" "$WEBROOT/"
  rm -rf "$WEBROOT/mainsail"
fi

# Nginx site
cat >/etc/nginx/sites-available/mainsail <<EOF
server {
    listen 80;
    server_name _;

    root $WEBROOT;
    index index.html;

    # Static assets
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Moonraker API (reverse proxy)
    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /api {
        proxy_pass http://127.0.0.1:7125/api;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /printer {
        proxy_pass http://127.0.0.1:7125/printer;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /access {
        proxy_pass http://127.0.0.1:7125/access;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default || true
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail

systemctl_if_exists daemon-reload || true
systemctl_if_exists enable nginx || true

echo_green "[mainsail] installed to $WEBROOT and nginx configured"
