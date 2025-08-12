# CI board hint

The **Build & Customize (Klipper Suite)** workflow now accepts an optional `board` input for the
Orange Pi 5 family imaging step. Leave it empty to auto-detect, or provide one explicitly:

- `orangepi5`
- `orangepi5-plus`
- `orangepi5-max`

This value is passed as `BOARD=` to `scripts/make-img-orangepi5max.sh`.
