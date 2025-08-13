#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap

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

# Tools we need (add zip/unzip to satisfy npm's build.zip step)
for p in ca-certificates curl git rsync jq zip unzip; do
  is_in_apt "$p" && apt-get install -y --no-install-recommends "$p" || true
done

# Ensure Node.js >= 20
NEED_NODE=1
if command -v node >/dev/null 2>&1; then
  NV_MAJOR="$(node -v | sed 's/^v//;s/\..*//')"
  if [ "${NV_MAJOR:-0}" -ge 20 ]; then NEED_NODE=0; fi
fi
if [ "$NEED_NODE" -eq 1 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y --no-install-recommends nodejs
fi

SRC_DIR="$HOME_DIR/mainsail-src"
WEBROOT="$HOME_DIR/mainsail"

# Clone or update repo
if [ ! -d "$SRC_DIR/.git" ]; then
  sudo -u "$KS_USER" git clone --depth=1 https://github.com/mainsail-crew/mainsail.git "$SRC_DIR"
else
  sudo -u "$KS_USER" git -C "$SRC_DIR" fetch --all --prune || true
fi

# Prefer master → then main → then develop
sudo -u "$KS_USER" bash -lc '
  set -e
  cd "'"$SRC_DIR"'"
  git fetch --depth=1 origin master || true
  git fetch --depth=1 origin main || true
  git fetch --depth=1 origin develop || true
  if git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
    git checkout -B master origin/master
  elif git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    git checkout -B main origin/main
  elif git ls-remote --exit-code --heads origin develop >/dev/null 2>&1; then
    git checkout -B develop origin/develop
  else
    echo "No suitable branch (master/main/develop) found"; exit 1
  fi
'

# Build (quiet-ish)
export npm_config_audit=false npm_config_fund=false
sudo -u "$KS_USER" bash -lc "cd '$SRC_DIR' && npm ci && npm run build"

# Install built assets
install -d "$WEBROOT"
rsync -a --delete "$SRC_DIR"/dist/ "$WEBROOT"/
chown -R "$KS_USER:$KS_USER" "$WEBROOT"

# Health checks
test -s "$WEBROOT/index.html" || { echo_red "[mainsail] index.html missing"; exit 1; }
grep -Eo 'src=\"/assets/.+\.js' "$WEBROOT/index.html" >/dev/null || {
  echo_red "[mainsail] no JS bundle referenced in index.html"; exit 1; }

# Nginx site
if is_in_apt nginx; then
  apt-get install -y --no-install-recommends nginx || true
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
fi

# Moonraker Update Manager: git_repo on master
MOON_CFG="$HOME_DIR/printer_data/config/moonraker.conf"
install -d "$(dirname "$MOON_CFG")"
touch "$MOON_CFG"; chown "$KS_USER:$KS_USER" "$MOON_CFG"

# Remove any old 'type: web' mainsail block
if grep -q "^\[update_manager mainsail\]" "$MOON_CFG"; then
  awk '
    BEGIN{skip=0}
    /^\[update_manager mainsail\]/{skip=1; next}
    /^\[update_manager / && skip==1 {skip=0}
    skip==0 {print}
  ' "$MOON_CFG" >"$MOON_CFG.tmp" && mv "$MOON_CFG.tmp" "$MOON_CFG"
fi

# Script for Moonraker to rebuild & sync
cat >"$SRC_DIR/.moonraker-install.sh" <<'EOS'
#!/bin/bash
set -e
set -x
export LC_ALL=C
npm ci
npm run build
WEBROOT="$HOME/mainsail"
mkdir -p "$WEBROOT"
rsync -a --delete dist/ "$WEBROOT/"
EOS
chown "$KS_USER:$KS_USER" "$SRC_DIR/.moonraker-install.sh"
chmod +x "$SRC_DIR/.moonraker-install.sh"

# Add UM entry if missing
if ! grep -q "^\[update_manager mainsail\]" "$MOON_CFG"; then
  cat >>"$MOON_CFG" <<EOF

[update_manager mainsail]
type: git_repo
path: ~/mainsail-src
origin: https://github.com/mainsail-crew/mainsail.git
primary_branch: master
install_script: .moonraker-install.sh
managed_services: nginx
EOF
  chown "$KS_USER:$KS_USER" "$MOON_CFG"
fi

echo_green "[mainsail] built from master and installed to $WEBROOT"
