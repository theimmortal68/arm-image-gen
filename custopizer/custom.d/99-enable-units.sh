#!/usr/bin/env bash
set -euox pipefail
export LC_ALL=C
# shellcheck disable=SC1091
source /common.sh; install_cleanup_trap

# Where to read the unit list from (first hit wins)
FILES_LIST="/files/etc/ks-enable-units.txt"
ETC_LIST="/etc/ks-enable-units.txt"

# Read units (ignore blanks/comments) safely under set -u
read_units() {
  local src="$1"
  local line trimmed
  # shellcheck disable=SC2034  # UNITS is a global we intentionally fill
  UNITS=()
  while IFS= read -r line || [ -n "${line:-}" ]; do
    # strip comments; trim whitespace
    trimmed="${line%%#*}"
    trimmed="$(printf '%s' "${trimmed}" | xargs || true)"
    [ -n "${trimmed}" ] && UNITS+=("${trimmed}")
  done < "$src"
}

if [ -f "$ETC_LIST" ]; then
  read_units "$ETC_LIST"
elif [ -f "$FILES_LIST" ]; then
  read_units "$FILES_LIST"
else
  # Sensible defaults if no list is provided
  UNITS=(klipper.service moonraker.service crowsnest.service moonraker-timelapse.service sonar.service)
fi

enable_one() {
  # Default to empty to avoid "unbound variable" under set -u
  local unit="${1-}"
  [ -n "$unit" ] || return 0

  # Locate the unit file (any standard dir)
  local src=""
  for d in /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system; do
    if [ -f "$d/$unit" ]; then src="$d/$unit"; break; fi
  done

  if [ -z "$src" ]; then
    echo "[enable] skip: $unit (unit file not found)"
    return 0
  fi

  install -d /etc/systemd/system/multi-user.target.wants
  ln -sf "$src" "/etc/systemd/system/multi-user.target.wants/$unit"
  echo "[enable] enabled: $unit -> multi-user.target.wants"
}

# Enable each requested unit
for u in "${UNITS[@]}"; do
  enable_one "$u"
done

# Reload unit files if systemctl is available in this chroot image
systemctl_if_exists daemon-reload || true

echo "[enable] done"
