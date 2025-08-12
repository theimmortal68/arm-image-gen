
#!/usr/bin/env bash
set -euo pipefail
source /root/.custopizer_user_env || true
USER="${KS_USER}"
: "${USER:?KS_USER not set}"
HOME_DIR="$(getent passwd "${USER}" | cut -d: -f6)"

install -d "${HOME_DIR}/mainsail"
chown -R "${USER}:${USER}" "${HOME_DIR}/mainsail"
su - "${USER}" -c "cd ${HOME_DIR}/mainsail && wget -q -O mainsail.zip https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip && unzip -oq mainsail.zip && rm mainsail.zip"

cat >/etc/nginx/sites-available/mainsail <<EOF
server {
    listen 80 default_server;
    server_name _;

    root ${HOME_DIR}/mainsail;
    index index.html;
    access_log /var/log/nginx/mainsail.access.log;
    error_log  /var/log/nginx/mainsail.error.log;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
    location /printer/ {
        proxy_pass http://127.0.0.1:7125/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default || true
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
nginx -t || true
systemctl enable nginx || true
