#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Mainsail UI + nginx reverse proxy"

# Target user/home
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
: "${KS_USER:=pi}"
: "${HOME_DIR:=/home/${KS_USER}}"

# Packages
apt_install nginx git unzip wget ca-certificates

# nginx layout
install -d -m 0755 /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled

# upstreams
cat >/etc/nginx/conf.d/upstreams.conf <<'EOF'
upstream apiserver { ip_hash; server 127.0.0.1:7125; }
upstream mjpgstreamer1 { ip_hash; server 127.0.0.1:8080; }
upstream mjpgstreamer2 { ip_hash; server 127.0.0.1:8081; }
upstream mjpgstreamer3 { ip_hash; server 127.0.0.1:8082; }
upstream mjpgstreamer4 { ip_hash; server 127.0.0.1:8083; }
EOF

# variables
cat >/etc/nginx/conf.d/common_vars.conf <<'EOF'
map $http_upgrade $connection_upgrade { default upgrade; '' close; }
EOF

# site (needs $HOME_DIR expanded now)
cat >/etc/nginx/sites-available/mainsail <<EOF
server {
    listen 80 default_server;
    access_log /var/log/nginx/mainsail-access.log;
    error_log  /var/log/nginx/mainsail-error.log;
    gzip on; gzip_vary on; gzip_proxied any;
    gzip_proxied expired no-cache no-store private auth;
    gzip_comp_level 4; gzip_buffers 16 8k; gzip_http_version 1.1;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/x-javascript application/json application/xml;
    root ${HOME_DIR}/mainsail;
    index index.html;
    server_name _;
    client_max_body_size 0;
    proxy_request_buffering off;
    location / { try_files \$uri \$uri/ /index.html; }
    location = /index.html { add_header Cache-Control "no-store, no-cache, must-revalidate"; }
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
    location /webcam/  { proxy_buffering off; proxy_ignore_headers X-Accel-Buffering; access_log off; error_log off; proxy_pass http://mjpgstreamer1/; }
    location /webcam2/ { proxy_buffering off; proxy_ignore_headers X-Accel-Buffering; access_log off; error_log off; proxy_pass http://mjpgstreamer2/; }
    location /webcam3/ { proxy_buffering off; proxy_ignore_headers X-Accel-Buffering; access_log off; error_log off; proxy_pass http://mjpgstreamer3/; }
    location /webcam4/ { proxy_buffering off; proxy_ignore_headers X-Accel-Buffering; access_log off; error_log off; proxy_pass http://mjpgstreamer4/; }
}
EOF

rm -f /etc/nginx/sites-enabled/default || true
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail

# Install Mainsail web files
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${HOME_DIR}"
if [ -e "${HOME_DIR}/mainsail" ]; then
  echo "Directory ${HOME_DIR}/mainsail already exists" >&2
  exit 1
fi
as_user "${KS_USER}" 'mkdir -p "$HOME/mainsail" && cd "$HOME/mainsail" && wget -q -O mainsail.zip "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" && unzip mainsail.zip && rm -f mainsail.zip'

# Permissions
gpasswd -a www-data "${KS_USER}" || true
chmod g+x "${HOME_DIR}" || true

# Update Manager fragment via safe writer
UMDIR="${HOME_DIR}/printer_data/config/update-manager.d"
install -d -o "${KS_USER}" -g "${KS_USER}" -m 0755 "${UMDIR}"
cat > "${UMDIR}/mainsail.conf" <<EOF
[update_manager mainsail]
type: web
channel: stable
repo: mainsail-crew/mainsail
path: ${HOME_DIR}/mainsail
EOF
chown "${KS_USER}:${KS_USER}" "${UMDIR}/mainsail.conf"
chmod 0644 "${UMDIR}/mainsail.conf"

echo_green "[mainsail] nginx ready; httpdocs installed; UM fragment written"
apt_clean_all
