#!/usr/bin/env bash
set -Eeuxo pipefail
export LC_ALL=C
source /common.sh; install_cleanup_trap

# Where to read the list (first hit wins)
# Recommended: ship /etc/ks-enable-units.txt from an earlier script
CANDIDATES=(
  "/etc/ks-enable-units.txt"
  "/root/enable-units.txt"
  "/opt/enable-units.txt"
)

UNITS=()

# Load list if available (one unit per line, comments allowed)
for f in "${CANDIDATES[@]}"; do
  if [ -f "$f" ]; then
    mapfile -t UNITS < <(sed -e 's/#.*$//' -e 's/^\s\+//;s/\s\+$//' "$f" | awk 'NF')
    echo "[enable-units] using list from $f: ${UNITS[*]}"
    break
  fi
done

# If no list, auto-detect common services that actually exist
if [ "${#UNITS[@]}" -eq 0 ]; then
  GUESS=( klipper.service moonraker.service crowsnest.service
          moonraker-timelapse.service sonar.service )
  for u in "${GUESS[@]}"; do
    [ -e "/etc/systemd/system/$u" ] || [ -e "/lib/systemd/system/$u" ] && UNITS+=("$u")
  done
  echo "[enable-units] autodetected: ${UNITS[*]:-<none>}"
fi

install -d /etc/systemd/system/multi-user.target.wants

enable_one() {
  local unit="$1" target="/etc/systemd/system/multi-user.target.wants/$unit"
  local src=""
  if   [ -e "/etc/systemd/system/$unit" ]; then src="/etc/systemd/system/$unit"
  elif [ -e "/lib/systemd/system/$unit" ]; then src="/lib/systemd/system/$unit"
  else
    echo "[enable-units] WARN: $unit not found, skipping"
    return 0
  fi
  ln -sf "$src" "$target"
  echo "[enable-units] enabled $unit -> $target"
}

for u in "${UNITS[@]}"; do
  enable_one "$u"
done

echo "[enable-units] done"
