# Kernel-arg merge strategy

Both imaging scripts now support an `ARG_STRATEGY` env (CI input: `arg_strategy`) to control how
`EXTRA_APPEND` is merged with existing kernel args:

- `append` (default): keep existing values, add new keys from `EXTRA_APPEND`
- `replace`: replace existing keys with the ones provided in `EXTRA_APPEND`

Applies to:
- **RPi**: merges into `/boot/firmware/cmdline.txt`
- **OPi**: merges into the `append` line in `/boot/extlinux/extlinux.conf`

Examples:
```bash
# Local RPi: replace loglevel and add cgroups params
ARG_STRATEGY=replace EXTRA_APPEND='loglevel=3 cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1' \
  bash scripts/make-img-rpi.sh out/rpi64-bookworm-arm64/rootfs build/input-rpi64.img

# CI (OPi): use replace strategy
device=orangepi5max, arg_strategy=replace, extra_append='loglevel=3 nowatchdog'
```
