#!/usr/bin/env bash
set -euxo pipefail
export LC_ALL=C

source /common.sh; install_cleanup_trap

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends iproute2 can-utils
rm -rf /var/lib/apt/lists/*

# Load CAN modules at boot on the target system (don't modprobe during image build)
install -D -m 0644 /dev/stdin /etc/modules-load.d/klipper-can.conf <<'EOF'
can
can_raw
# Uncomment if needed:
# gs_usb
# slcan
EOF

# Helper that (re)configures a CAN interface using /etc/default/<ifname>
# (fixed: provide a source to `install` via /dev/stdin)
install -D -m 0755 /dev/stdin /usr/local/sbin/can-setup.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
IFACE="${1:?usage: can-setup.sh <ifname>}"
CONF="/etc/default/${IFACE}"

# Defaults
BITRATE="${BITRATE:-500000}"
FD="${FD:-0}"
DBITRATE="${DBITRATE:-2000000}"
SAMPLE_POINT="${SAMPLE_POINT:-}"

# Load overrides from /etc/default/<ifname> if present
[ -r "$CONF" ] && . "$CONF"

# Always down before reconfig
/sbin/ip link set "$IFACE" down || true

# Build type args
ARGS=(type can bitrate "$BITRATE")
[ -n "$SAMPLE_POINT" ] && ARGS+=(sample-point "$SAMPLE_POINT")
if [ "$FD" = "1" ] || [ "${CAN_FD:-0}" = "1" ]; then
  ARGS+=(dbitrate "$DBITRATE" fd on)
fi

/sbin/ip link set "$IFACE" "${ARGS[@]}"
/sbin/ip link set "$IFACE" up
EOS

# systemd template: can@can0.service brings up can0 (works fine alongside NetworkManager)
cat >/etc/systemd/system/can@.service <<'EOF'
[Unit]
Description=Bring up SocketCAN interface %i
BindsTo=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/can-setup.sh %i
ExecStop=/sbin/ip link set %i down

[Install]
WantedBy=multi-user.target
EOF

# Seed defaults for can0 if absent
if [ ! -e /etc/default/can0 ]; then
  cat >/etc/default/can0 <<'EOF'
# Defaults for can0
BITRATE=500000
# Enable CAN-FD (1 to enable)
FD=0
# Data bitrate used when FD=1
DBITRATE=2000000
# Optional sample point (e.g., 0.875)
# SAMPLE_POINT=
EOF
fi

systemctl_if_exists daemon-reload || true
echo_green "[canbus] Installed modules-load and can@.service; edit /etc/default/can0 and enable can@can0.service via ks-enable-units or systemctl"
