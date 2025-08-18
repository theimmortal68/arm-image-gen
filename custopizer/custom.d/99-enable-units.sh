#!/usr/bin/env bash
# 99-enable-units.sh — enable a list of systemd units at boot (helper-ized)
set -Eeuo pipefail
export LC_ALL=C

# Bootstrap
source /common.sh; install_cleanup_trap
[ -r /files/ks_helpers.sh ] && source /files/ks_helpers.sh

section "Enabling requested systemd units"

# Remove any policy-rc.d guard so services can start on target
rm -f /usr/sbin/policy-rc.d || true

# Remove systemctl shim FIRST so enables create real symlinks
ks_systemctl_shim_remove

FILES_LIST="/files/etc/ks-enable-units.txt"
ETC_LIST="/etc/ks-enable-units.txt"

# Parse a units file into the global UNITS array (ignore blanks/comments)
read_units() {
  local src="$1"
  local line trimmed
  # shellcheck disable=SC2034
  UNITS=()
  while IFS= read -r line || [ -n "${line-}" ]; do
    trimmed="${line%%#*}"
    trimmed="$(printf '%s' "${trimmed}" | xargs || true)"
    [ -n "${trimmed}" ] && UNITS+=("${trimmed}")
  done < "$src"
  return 0   # prevent set -e from tripping at EOF
}

if [ -f "$ETC_LIST" ]; then
  read_units "$ETC_LIST"
elif [ -f "$FILES_LIST" ]; then
  read_units "$FILES_LIST"
else
  # Sensible defaults; customize via ks-enable-units.txt
  UNITS=(klipper.service moonraker.service crowsnest.service moonraker-timelapse.service sonar.service)
fi

enable_one() {
  local unit="${1-}"
  [ -n "$unit" ] || return 0

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

for u in "${UNITS[@]}"; do
  enable_one "$u"
done

# Do not rely on a helper; handle chroot/non-systemd safely
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi

echo "[enable] done"
