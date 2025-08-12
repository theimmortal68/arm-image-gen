
#!/usr/bin/env bash
set -euo pipefail
ROOTFS="${1:?usage: $0 /path/to/rootfs}"

DEVICE="unknown"
if [ -f "$ROOTFS/etc/device-id" ]; then
  DEVICE="$(tr -d '\n' < "$ROOTFS/etc/device-id")"
fi

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl --root="$ROOTFS" enable NetworkManager || true
  sudo systemctl --root="$ROOTFS" enable ssh || true
fi

case "$DEVICE" in
  rpi64)
    install -d "$ROOTFS/boot/firmware"
    [ -f "$ROOTFS/boot/firmware/config.txt" ] ||       printf "arm_64bit=1\nenable_uart=1\n" | sudo tee "$ROOTFS/boot/firmware/config.txt" >/dev/null
    [ -f "$ROOTFS/boot/firmware/cmdline.txt" ] ||       printf "console=serial0,115200 console=tty1 root=PARTUUID=00000000-02 rootfstype=ext4 fsck.repair=yes rootwait\n"         | sudo tee "$ROOTFS/boot/firmware/cmdline.txt" >/dev/null
    ;;
  orangepi5max)
    install -d "$ROOTFS/boot"
    ;;
  *)
    :
    ;;
esac
