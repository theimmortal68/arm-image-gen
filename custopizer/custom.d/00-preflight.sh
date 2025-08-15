#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap

echo "[preflight] start"

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

                                      # ---- DNS parachute (only if resolv.conf has no nameserver) -----------------
                                      if ! grep -Eq '^\s*nameserver\s+' /etc/resolv.conf 2>/dev/null; then
                                        printf '%s\n' 'nameserver 8.8.8.8' 'nameserver 1.1.1.1' > /etc/resolv.conf
                                          echo "[preflight] wrote fallback /etc/resolv.conf"
                                          fi

                                          echo "[preflight] ok"
                                          exit 0
