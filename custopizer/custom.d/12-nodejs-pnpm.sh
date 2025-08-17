#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Install Node.js + pnpm (robust)"
: "${NODE_MAJOR:=22}"
: "${PNPM_VERSION:=latest}"

# Prereqs
apt_install ca-certificates curl gnupg

# NodeSource repo + key
install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg

cat >/etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main
EOF

# Pin NodeSource for nodejs so Debian's package can't override it
cat >/etc/apt/preferences.d/99-nodesource <<'EOF'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 1001
EOF

apt_update_once

# Prefer NodeSource explicitly; fall back to Debian if repo is unreachable
if ! apt-get install -y -t nodistro nodejs; then
  apt_install nodejs
fi

# Ensure /usr/bin/node exists (Debian may only ship /usr/bin/nodejs)
if ! command -v node >/dev/null 2>&1 && [ -x /usr/bin/nodejs ]; then
  ln -sf /usr/bin/nodejs /usr/bin/node
fi

# Ensure npm exists (NodeSource includes it; Debian splits it)
if ! command -v npm >/dev/null 2>&1; then
  apt_install npm || true
fi

# Install pnpm: prefer npm, else fall back to corepack on Node >=16
if command -v npm >/dev/null 2>&1; then
  npm install -g "pnpm@${PNPM_VERSION}"
else
  if command -v corepack >/dev/null 2>&1; then
    corepack enable
    corepack prepare "pnpm@${PNPM_VERSION}" --activate
  else
    echo "WARNING: npm and corepack not available; skipping pnpm install" >&2
  fi
fi

# Record versions (optional)
install -d -m 0755 /etc
{
  printf 'Node.js\t%s\n' "$(node -v || true)"
  printf 'npm\t%s\n' "$(npm -v || true)"
  printf 'pnpm\t%s\n' "$(pnpm -v || true)"
} >> /etc/ks-manifest.txt

apt_clean_all
