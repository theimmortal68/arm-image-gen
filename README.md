# arm-image-gen

Minimal, reproducible, CI-driven images for Klipper stacks (Klipper + Moonraker + Mainsail + Crowsnest + extras) across Raspberry Pi and other ARM SBCs.

- **Raspberry Pi**: Debian Bookworm base + **Raspberry Pi kernel/firmware/userland** (full camera support).  
- **Non-Pi boards (e.g., Orange Pi)**: **Armbian** vendor images or Debian base (board-specific) + the same customization layer.  
- **Customization** via **CustoPiZer** (idempotent bash scripts), designed for headless/server builds.

> Result: a small, clean image that boots straight into the Klipper ecosystem with sensible defaults.

---

## Table of contents

- [What gets built](#what-gets-built)
- [Repo layout](#repo-layout)
- [Build in GitHub Actions (recommended)](#build-in-github-actions-recommended)
- [Build locally](#build-locally)
- [Supported devices](#supported-devices)
- [How layers work (bdebstrap)](#how-layers-work-bdebstrap)
- [How customization works (CustoPiZer)](#how-customization-works-custopizer)
- [Camera stack recommendations](#camera-stack-recommendations)
- [Common environment variables](#common-environment-variables)
- [Add a new device](#add-a-new-device)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## What gets built

1) **Base rootfs** (with `mmdebstrap` via the `bdebstrap` wrapper):
- Debian Bookworm arm64 + core build/runtime tools.
- For Raspberry Pi: Raspberry Pi apt repo + pinned **kernel/bootloader/EEPROM** + userland/camera tools.

2) **Bootable image**:
- RPi: DOS MBR, **FAT32 /boot/firmware**, **ext4 /** (root=LABEL=rootfs).

3) **Customization (CustoPiZer)**:
- Users, groups, SSH, networking fixes.
- **Klipper**, **Moonraker**, **Mainsail**.
- **Crowsnest** + streaming backend(s).
- Optional plugins: **moonraker-timelapse**, **sonar**.
- Cleanup and service enablement.

Artifacts are uploaded as `output-<device>.img`.

---

## Repo layout

```
.
├─ bconf/                       # bdebstrap layer configs (YAML)
│  ├─ minimal-bookworm-arm64/
│  │  └─ config.yaml
│  ├─ common/
│  │  ├─ base-packages-debian.yaml
│  │  ├─ base-packages-armbian.yaml
│  │  ├─ networking.yaml
│  │  └─ ssh.yaml
│  ├─ rpi64/
│  │  ├─ firmware.yaml          # adds RPi repo + pins + installs kernel/boot/eeprom
│  │  └─ userland.yaml          # installs rpicam-apps, libcamera*, v4l-utils, ffmpeg, ustreamer
│  └─ orangepi5max/
│     └─ armbian.yaml           # adds Armbian repo/key (used when building from Debian base)
│
├─ devices/
│  ├─ rpi64/
│  │  └─ layers.yaml            # stack for Raspberry Pi 64-bit
│  └─ orangepi5max/
│     └─ layers.yaml            # stack for Orange Pi 5 Max
│
├─ custopizer/
│  └─ custom.d/                 # CustoPiZer customization scripts (run inside chroot)
│     ├─ 00-fix-network.sh
│     ├─ 00-detect-user.sh
│     ├─ 05-create-user.sh
│     ├─ 20-klipper.sh
│     ├─ 30-moonraker.sh
│     ├─ 52-mainsail.sh
│     ├─ 52-camera-streamer.sh
│     ├─ 53-crowsnest.sh
│     ├─ 54-moonraker-timelapse.sh
│     ├─ 55-sonar.sh
│     ├─ 97-restore-resolvconf.sh
│     ├─ 98-unblock-services.sh
│     └─ 99-apt-clean.sh
│
├─ scripts/
│  ├─ build-bdebstrap.sh        # runs bdebstrap with a device’s layers
│  ├─ make-img-rpi.sh           # builds bootable RPi .img from rootfs
│  ├─ run-custopizer.sh         # runs CustoPiZer against an input .img
│  └─ fetch-raspios.sh          # (optional) fetch official Raspberry Pi OS Lite image
│
└─ .github/workflows/
   ├─ build-and-customize.yml   # single-device CI
   └─ build-multi-device.yml    # multi-device CI (RPi + Orange Pi etc.)
```

---

## Build in GitHub Actions (recommended)

### Single device
`/.github/workflows/build-and-customize.yml` builds the `rpi64` image:
- **Step 1**: bdebstrap → `out/rpi64-bookworm-arm64/rootfs/`
- **Step 2**: make bootable image → `build/input-rpi64.img`
- **Step 3**: customize with CustoPiZer → `build/output-rpi64.img` (artifact)

Trigger on push/PR or via “Run workflow”.

### Multiple devices
`/.github/workflows/build-multi-device.yml` supports:
- **rpi64**: build from rootfs (as above).
- **orangepi5max**: download an **Armbian** `.img(.xz)` (set repo variable `ARMBIAN_OPI5_URL`), then run CustoPiZer.

> Add more devices by extending the job matrix (see [Add a new device](#add-a-new-device)).

---

## Build locally

> Requires Ubuntu host (or similar) with `docker` (for CustoPiZer) and loopback FS tools.

Install tools:
```bash
sudo apt-get update
sudo apt-get install -y mmdebstrap qemu-user-static binfmt-support   ca-certificates curl wget jq git unzip rsync   parted dosfstools e2fsprogs kpartx xz-utils util-linux udev mount kmod
python3 -m pip install --user bdebstrap
export PATH="$HOME/.local/bin:$PATH"
```

Build **rpi64**:
```bash
# 1) Rootfs
bash scripts/build-bdebstrap.sh rpi64 devices/rpi64/layers.yaml out/rpi64-bookworm-arm64

# 2) Bootable image
sudo bash scripts/make-img-rpi.sh out/rpi64-bookworm-arm64/rootfs build/input-rpi64.img

# 3) Customize
bash scripts/run-custopizer.sh build/input-rpi64.img build/output-rpi64.img 8000
```

Output: `build/output-rpi64.img`

---

## Supported devices

- **Raspberry Pi 3/4/Zero2/5** → use `devices/rpi64/layers.yaml` (64-bit).  
  - Pi 5 notes in [Camera stack recommendations](#camera-stack-recommendations).
- **Orange Pi 5 Max** (and similar) → via **Armbian** in CI (`build-multi-device.yml`) or Debian base + board layer (advanced).

---

## How layers work (bdebstrap)

`bconf/*.yaml` define rootfs build layers. We combine them per device:

**Raspberry Pi 64-bit**  
`devices/rpi64/layers.yaml`
```yaml
layers:
  - bconf/minimal-bookworm-arm64/config.yaml
  - bconf/common/base-packages-debian.yaml
  - bconf/rpi64/firmware.yaml
  - bconf/rpi64/userland.yaml
  - bconf/common/networking.yaml
  - bconf/common/ssh.yaml
```

**Key rules**
- `suite`, `components`, `architectures`, `packages`, etc. live **inside** the `mmdebstrap:` block.
- Hooks (`setup-hook`, `customize-hook`, etc.) are **top-level** keys (not under `mmdebstrap:`).  
- Layers are applied in order; later layers can depend on repos added by earlier ones (e.g., `userland.yaml` after `firmware.yaml`).

---

## How customization works (CustoPiZer)

All scripts in `custopizer/custom.d/` are run inside the image chroot. Each script begins with:

```bash
set -x
set -e
export LC_ALL=C
source /common.sh
install_cleanup_trap
```

Highlights:
- `00-fix-network.sh` ensures resolvable DNS inside chroot (replaces stub `/etc/resolv.conf` during build).
- `00-detect-user.sh` + `05-create-user.sh` pick/create `$KS_USER` (default `pi`), add to useful groups, and create `printer_data` dirs.
- `20-klipper.sh`, `30-moonraker.sh` set up venvs/services.
- `52-mainsail.sh` installs the latest release zip to `$HOME/mainsail`.
- `52-camera-streamer.sh` installs **camera-streamer** (RPi variants available).
- `53-crowsnest.sh` installs **Crowsnest** and drops a minimal `/etc/crowsnest.conf`.
- `54-moonraker-timelapse.sh`, `55-sonar.sh` install optional extras.
- `97-restore-resolvconf.sh` (optional), `98-unblock-services.sh`, `99-apt-clean.sh` finalize the image.

> CustoPiZer prevents service autostart at build time; services are enabled to start on first boot.

---

## Camera stack recommendations

- **Pi 3/4/Zero2 (Debian + RPi kernel/userland)**: default to **camera-streamer** (hardware H.264 / WebRTC when available). Keep `rpicam-apps`, `libcamera*`, `v4l-utils`, `ffmpeg` installed for detection/diagnostics.
- **Pi 5**: use **ustreamer** (MJPEG). Current Crowsnest guidance favors ustreamer on Pi 5 due to limitations in exposed HW encoders in the supported stack.
- **Non-Pi (Armbian)**: prefer **USB UVC webcams** + **ustreamer**. CSI cameras may work depending on kernel/ISP, but results vary.

**Crowsnest example (`/etc/crowsnest.conf`):**
```ini
[global]
log_path: /var/log/crowsnest

# For Pi 3/4: camera-streamer + libcamera device path
#[cam rpi-libcamera]
#mode: camera-streamer
#device: /base/soc/i2c0mux/i2c@1/imx708@1a
#resolution: 1280x720
#max_fps: 30
#port: 8080

# Generic UVC webcam (Pi 5 & Armbian default)
[cam uvc]
mode: ustreamer
device: /dev/video0
resolution: 1280x720
max_fps: 30
port: 8081
```

---

## Common environment variables

- `KS_USER` – user to configure (default `pi`).  
  Provide via **workflow env** or bake into a CustoPiZer script.
- `KS_SSH_PUBKEY` – optional; if set, added to `$HOME/.ssh/authorized_keys`.
- `ENLARGEROOT` – root partition resize during customization (default **8000** MB).

---

## Add a new device

1) **Create a device stack**:
```
devices/<myboard>/layers.yaml
```
Point it at an appropriate `bconf` stack (Debian base + board layer), or skip bdebstrap and use a **vendor image** in CI.

2) **If using vendor image (easiest for Armbian)**:
- Add a matrix entry in `build-multi-device.yml` with `build_from_rootfs: false`.
- Create a repo/org variable with a direct image URL (e.g., `ARMBIAN_<BOARD>_URL`).
- The workflow will download → CustoPiZer customize → upload image.

3) **If building from Debian base**:
- Create `bconf/<board>/...` for the board’s repo/key/pinning and boot bits.
- Add an image maker script in `scripts/` if not RPi (u-boot/extlinux, dtb, etc.).
- Reference it in the workflow.

---

## Troubleshooting

- **DNS errors in chroot**: `00-fix-network.sh` replaces stub `/etc/resolv.conf` with static servers during customization. You can also pass `--dns` flags to the CustoPiZer Docker run (already handled in `scripts/run-custopizer.sh`).
- **“output dir exists” (bdebstrap)**: our wrapper nukes the outdir before each run. If you run bdebstrap directly, add `--force` or remove the dir.
- **mmdebstrap hooks not firing**: ensure `setup-hook`/`customize-hook` are **top-level** YAML keys (not under `mmdebstrap:`).
- **Missing tools in scripts**: base tools (git, unzip, rsync, python3-venv, etc.) are installed in the **base-packages** layer; scripts check and install only if necessary.
- **Pi 5 camera issues**: switch your Crowsnest camera to `mode: ustreamer`. Confirm `/dev/video0` exists and test `ustreamer --help`.

---

## License

This repository includes third-party tools and scripts. Your own code is MIT unless specified otherwise at the file level. Verify licenses of bundled upstream projects (Klipper, Moonraker, Mainsail, CustoPiZer, Crowsnest, Armbian, Raspberry Pi OS components) before redistribution.
