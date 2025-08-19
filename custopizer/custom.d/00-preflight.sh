#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh
install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

echo "[preflight] start"

# 1) Install systemctl shim immediately so package postinsts cannot start services.
ks_systemctl_shim_install

# ---- sudo sanity (self-heal, don't fail the build) -------------------------
if [ -x /usr/bin/sudo ]; then
  st="$(stat -c '%u:%g %a' /usr/bin/sudo || true)"
  owner="${st% *}"
  mode="${st##* }"

  if [ "$owner" != "0:0" ]; then
    echo "[preflight] fixing sudo owner (was $owner)"
      chown 0:0 /usr/bin/sudo || true
  fi

  if [ "$mode" != "4755" ]; then
    echo "[preflight] setting setuid on sudo (was $mode)"
    chmod 4755 /usr/bin/sudo || true
  fi

  echo "[preflight] sudo now: $(stat -c '%u:%g %a' /usr/bin/sudo || true)"
fi

# ---- su binaries: also ensure setuid root ----------------------------------
for su in /bin/su /usr/bin/su; do
  [ -e "$su" ] || continue
  chown 0:0 "$su" || true
  chmod 4755 "$su" || true
done

#### THIS SHOULD BE DONE BY NETWORKING.YAML IN BUILD STAGE ####
# section "Fixing DNS/resolv.conf for chroot"
# # Replace stub resolv.conf with host's for the duration of the build
# if [ -f /etc/resolv.conf ]; then
#   cp -f /etc/resolv.conf /etc/resolv.conf.custopizer.bak || true
# fi
# printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" | wr_root 0644 /etc/resolv.conf
