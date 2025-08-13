#!/bin/bash
# Install Mainsail from the latest GitHub release asset (mainsail.zip)
# - No Node.js build, just unzip the prebuilt bundle.
# - Adds Moonraker Update Manager entry: type=web (tracks releases).

set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap

# retry polyfill: retry <attempts> <delay> <cmd...>
type retry >/dev/null 2>&1 || retry() {
  local tries="$1"; local delay="$2"; shift 2
  local n=0
  until "$@"; do n=$((n+1)); [ "$n" -ge "$tries" ] && return 1; sleep "$delay"; done
}

KS_USER="${KS_USER:-pi}"
HOME_DIR="$(getent passwd "$KS_USER" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || { echo_red "[mainsail] user $KS_USER missing"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
retry 4 2 apt-get update

# Tools we need for fetching/unpacking & serving
for p in ca-certificates curl wget unzip rsync nginx; do
  is_in_apt "$p" && apt-get install -y --no-install-recommends "$p" || true
done

WEBROOT="$HOME_DIR/mainsail"
TMP="/tmp/mainsail.zip"
TMPDIR="/tmp/_mainsail_zip"

rm -rf "$TMPDIR" && mkdir -p "$TMPDIR"

# Official prebuilt asset
URL="https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip"
echo_green "[mainsail] downloading → $URL"
retry 4 2 wget -O "$TMP" "$URL"

unzip -o "$TMP" -d "$TMPDIR"

# Handle both layouts: files directly in ZIP root or nested in 'mainsail/'
SRC="$TMPDIR"
[ -d "$TMPDIR/mainsail" ] && SRC="$TMPDIR/mainsail"

install -d "$WEBROOT"

# ✅ Correct: source and destination are separate args
rsync -a --delete "$SRC/" "$WEBROOT/"

chown -R "$KS_USER:$KS_USER" "$WEBROOT"

# Health checks
test -s "$WEBROOT/index.html" || { echo_red "[mainsail] index.html missing"; exit 1; }
grep -Eo 'src="/assets/.+\.js' "$WEBROOT/index.html" >/dev/null || {
  echo_red "[mainsail] no JS bundle referenced in index.html"; exit 1; }

# Nginx site
cat >/etc/nginx/sites-available/mainsail <<EOF
server {
    listen 80;
    server_name _;

    root $WEBROOT;
    index index.html;

    location / { try_files \$uri \$uri/ /index.html; }

    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /api     { proxy_pass http://127.0.0.1:7125/api;     proxy_set_header X-Real-IP \$remote_addr; }
    location /printer { proxy_pass http://127.0.0.1:7125/printer; proxy_set_header X-Real-IP \$remote_addr; }
    location /access  { proxy_pass http://127.0.0.1:7125/access;  proxy_set_header X-Real-IP \$remote_addr; }
}
EOF
rm -f /etc/nginx/sites-enabled/default || true
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
systemctl_if_exists daemon-reload || true
systemctl_if_exists enable nginx || true

# Moonraker Update Manager: type=web
MOON_CFG="$HOME_DIR/printer_data/config/moonraker.conf"
install -d "$(dirname "$MOON_CFG")"
touch "$MOON_CFG"; chown "$KS_USER:$KS_USER" "$MOON_CFG"

# Remove any prior mainsail block (git/web) then add web entry
if grep -q "^\[update_manager mainsail\]" "$MOON_CFG"; then
  awk '
    BEGIN{skip=0}
    /^\[update_manager mainsail\]/{skip=1; next}
    /^\[update_manager / && skip==1 {skip=0}
    skip==0 {print}
  ' "$MOON_CFG" >"$MOON_CFG.tmp" && mv "$MOON_CFG.tmp" "$MOON_CFG"
fi

cat >>"$MOON_CFG" <<'EOF'

[update_manager mainsail]
type: web
repo: mainsail-crew/mainsail
path: ~/mainsail
EOF
chown "$KS_USER:$KS_USER" "$MOON_CFG"

echo_green "[mainsail] installed from release ZIP → $WEBROOT"
