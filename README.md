# Orange Pi 5 family imaging — board-aware + serial console

`scripts/make-img-orangepi5max.sh` now:
- Detects **OPi5 / OPi5 Plus / OPi5 Max** automatically (or accept `BOARD=` hint).
- Seeds `/boot/extlinux/extlinux.conf` with the right DTB, root UUID and **serial console** args.
- Lets you override serial console (`KERNEL_CONSOLE`) and append extra kernel args (`EXTRA_APPEND`).

Examples:
```bash
# Auto-detect board, default console
bash scripts/make-img-orangepi5max.sh out/orangepi5max-bookworm-arm64/rootfs build/input-orangepi5max.img

# Force OPi5 Plus and set a custom serial console
BOARD=orangepi5-plus KERNEL_CONSOLE='console=ttyS2,1500000 console=tty1'   bash scripts/make-img-orangepi5max.sh out/orangepi5max-bookworm-arm64/rootfs build/input-orangepi5plus.img

# Add extra kernel parameters
EXTRA_APPEND='loglevel=3 systemd.unified_cgroup_hierarchy=1'   bash scripts/make-img-orangepi5max.sh out/orangepi5max-bookworm-arm64/rootfs build/input-orangepi5.img
```
