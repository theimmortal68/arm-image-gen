# Idempotent kernel-arg handling

- **Pi (`make-img-rpi.sh`)**: merges `EXTRA_APPEND` into `/boot/firmware/cmdline.txt` **without duplicating**
  keys (anything before `=`) or flags. Re-running with the same `extra_append` will not add duplicates.
- **OPi (`make-img-orangepi5max.sh`)**: builds the `append` line for extlinux by merging the base parameters
  and `EXTRA_APPEND` **uniquely** (dedup by key). Re-running yields the same `extlinux.conf`.

Tip: if you change a parameter value (e.g., `loglevel=7` → `loglevel=3`), put the new one in `extra_append`;
the merge logic keeps the **first occurrence** of each key.
