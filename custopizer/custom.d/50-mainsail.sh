#!/bin/bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Fetch helper with retries (curl preferred, wget fallback)
fetch() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o "$out" "$url"
  else
    wget --tries=5 --waitretry=2 --retry-connrefused -O "$out" "$url"
  fi
}

# Detect user
[ -f /etc/ks-user.conf ] && . /etc/ks-user.conf || true
KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[mainsail] user $KS_USER missing"; exit 1; }

# Ensure unzip/rsync exist (they’re in your base layer; belt & suspenders)
is_in_apt unzip && ! is_installed unzip && apt-get update && apt-get install -y --no-install-recommends unzip || true
is_in_apt rsync && ! is_installed rsync && apt-get update && apt-get install -y --no-install-recommends rsync || true

# Download latest mainsail release asset (stable zip)
TMP=/tmp/mainsail.zip
fetch "https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip" "$TMP"

# Unpack into /home/<user>/mainsail
install -d "$HOME_DIR/mainsail"
rm -rf /tmp/_mainsail_zip && mkdir -p /tmp/_mainsail_zip
unzip -o "$TMP" -d /tmp/_mainsail_zip
rsync -a --delete /tmp/_mainsail_zip/ "$HOME_DIR/mainsail/"
chown -R "$KS_USER:$KS_USER" "$HOME_DIR/mainsail"

# After unzip
test -s /var/www/mainsail/index.html
test -d /var/www/mainsail/assets

# Nginx site (if you install nginx)
install -d /etc/nginx/sites-available /etc/nginx/sites-enabled
cat >/etc/nginx/sites-available/mainsail <<'NGX'
server {
  listen 80 default_server;
  server_name _;
  root /var/www/mainsail;
  index index.html;
  location / {
    try_files $uri $uri/ /index.html;
  }
}
NGX
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail

echo_green "[mainsail] installed to $HOME_DIR/mainsail"
