#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

# Mainsail (manual setup per docs)
# - Install nginx + config files
# - Install httpdocs (~/mainsail from latest release ZIP)
# - Append Moonraker Update Manager block
#
# Docs:
# - Manual setup flow, nginx confs, httpdocs zip path, and Bookworm permissions. 
# - Update Manager snippet for Mainsail.
#   https://docs.mainsail.xyz/setup/getting-started/manual-setup
#   https://docs.mainsail.xyz/setup/updates/update-manager

# Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  nginx git unzip wget ca-certificates

# ----------------------------
# NGINX config (per the docs)
# ----------------------------
# upstreams + common_vars + site file
install -d -m 0755 /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled

cat >/etc/nginx/conf.d/upstreams.conf <<'EOF'
# /etc/nginx/conf.d/upstreams.conf
upstream apiserver {
    ip_hash;
    server 127.0.0.1:7125;
}

upstream mjpgstreamer1 {
    ip_hash;
    server 127.0.0.1:8080;
}
upstream mjpgstreamer2 {
    ip_hash;
    server 127.0.0.1:8081;
}
upstream mjpgstreamer3 {
    ip_hash;
    server 127.0.0.1:8082;
}
upstream mjpgstreamer4 {
    ip_hash;
    server 127.0.0.1:8083;
}
EOF

cat >/etc/nginx/conf.d/common_vars.conf <<'EOF'
# /etc/nginx/conf.d/common_vars.conf
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}
EOF

# Mainsail site (root path uses HOME_DIR)
cat >/etc/nginx/sites-available/mainsail <<EOF
# /etc/nginx/sites-available/mainsail
server {
    listen 80 default_server;
    # listen [::]:80 default_server; # enable IPv6 if desired

    access_log /var/log/nginx/mainsail-access.log;
    error_log  /var/log/nginx/mainsail-error.log;

    # disable this section on smaller hardware like a pi zero
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_proxied expired no-cache no-store private auth;
    gzip_comp_level 4;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/x-javascript application/json application/xml;

    # web_path from mainsail static files
    root ${HOME_DIR}/mainsail;
    index index.html;
    server_name _;

    # disable max upload size checks
    client_max_body_size 0;

    # disable proxy request buffering
    proxy_request_buffering off;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location = /index.html {
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    location /websocket {
        proxy_pass http://apiserver/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://apiserver\$request_uri;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Scheme \$scheme;
    }

    location /webcam/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer1/;
    }
    location /webcam2/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer2/;
    }
    location /webcam3/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer3/;
    }
    location /webcam4/ {
        postpone_output 0;
        proxy_buffering off;
        proxy_ignore_headers X-Accel-Buffering;
        access_log off;
        error_log off;
        proxy_pass http://mjpgstreamer4/;
    }
}
EOF

# Activate site (don't restart nginx in chroot; it’ll be picked up on first boot)
rm -f /etc/nginx/sites-enabled/default || true
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail

# ------------------------------------
# Install httpdocs into ~/mainsail
# ------------------------------------
# Fail if the dir already exists (keeps your "no idempotence" stance)
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${HOME_DIR}"
if [ -e "${HOME_DIR}/mainsail" ]; then
  echo "Directory ${HOME_DIR}/mainsail already exists" >&2
  exit 1
fi
runuser -u "${KS_USER}" -- mkdir -p "${HOME_DIR}/mainsail"
runuser -u "${KS_USER}" -- bash -lc '
  set -euo pipefail
  cd "$HOME/mainsail"
  wget -q -O mainsail.zip "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip"
  unzip mainsail.zip
  rm -f mainsail.zip
'

# Debian 12 (Bookworm) permission tweak from docs:
# add www-data to ${KS_USER} group and ensure $HOME is traversable for group
gpasswd -a www-data "${KS_USER}" || true
chmod g+x "${HOME_DIR}" || true

# ----------------------------------------------------
# Moonraker Update Manager block for Mainsail (web)
# ----------------------------------------------------
CFG_DIR="${HOME_DIR}/printer_data/config"
CFG="${CFG_DIR}/moonraker.conf"
install -d -o "${KS_USER}" -g "${KS_USER}" "${CFG_DIR}"
[ -e "${CFG}" ] || install -m 0644 -o "${KS_USER}" -g "${KS_USER}" /dev/null "${CFG}"

TMP="$(mktemp)"
awk '
  BEGIN{skip=0}
  /^\[update_manager[[:space:]]+mainsail\]/{skip=1; next}
  skip && /^\[/{skip=0}
  !skip{print}
' "${CFG}" > "${TMP}"
printf "\n" >> "${TMP}"
cat >> "${TMP}" <<EOF
[update_manager mainsail]
type: web
channel: stable
repo: mainsail-crew/mainsail
path: ${HOME_DIR}/mainsail
EOF
install -m 0644 -o "${KS_USER}" -g "${KS_USER}" "${TMP}" "${CFG}"
rm -f "${TMP}"

# Optional manifest
rev="web-zip"
install -d -m 0755 /etc
printf 'Mainsail\t%s\n' "${rev}" >> /etc/ks-manifest.txt

echo_green "[mainsail] nginx config installed; httpdocs downloaded; Update Manager configured"
