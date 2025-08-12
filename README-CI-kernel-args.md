# CI: kernel args

The **Build & Customize (Klipper Suite)** workflow accepts optional inputs to tweak kernel
command-line parameters during image assembly:

- `kernel_console` — serial/tty console parameters (**OPi only**). Example:
  `console=ttyS2,1500000 console=tty1`
- `extra_append` — any additional kernel parameters to append (**applies to OPi and Pi**). Example:
  `loglevel=3 nowatchdog`

These are passed as environment variables to the imaging scripts:
- OPi: `KERNEL_CONSOLE`, `EXTRA_APPEND` → written into `/boot/extlinux/extlinux.conf`.
- Pi: `EXTRA_APPEND` → appended to `/boot/firmware/cmdline.txt`.
