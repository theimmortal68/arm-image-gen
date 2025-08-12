
# CustoPiZer customizations: Klipper Suite

After building a base `.img` for your device, run:

```bash
docker run --rm -it   -v $PWD/build:/work   -v $PWD/custopizer/custom.d:/custom.d   ghcr.io/octoprint/custopizer:latest   --image /work/input-<device>.img   --customizations /custom.d   --out /work/output-<device>.img
```

Override the username with `-e KS_USER=pi` if desired.
