# micro-kernel-only-tests

Smoke harnesses and recorded test results for the NØNOS upper-half
microkernel. This repo lives next to
[NON-OS/nonos-micro-kernel](https://github.com/NON-OS/nonos-micro-kernel)
and is consumed from there as a git submodule mounted at `tests/`.

## Layout

```
boot/         boot smoke harnesses (one shell script per profile)
```

Future trees (unit, integration, fuzz, perf) sit alongside `boot/`
when they land. Nothing in this repo runs without the kernel source
checked out side by side.

## Boot harnesses

Every script in `boot/` builds the kernel with a specific feature
profile, boots it under QEMU with the matching device set, captures
the boot serial to a log file, and grades the run by greping for
deterministic markers. No manual inspection. The kernel side of each
profile is responsible for emitting the markers; if a marker goes
missing the harness fails closed.

| Script                       | Profile                                |
| ---------------------------- | -------------------------------------- |
| `ramfs_round_trip.sh`        | open / write / read / truncate / close |
| `keyring_round_trip.sh`      | client ops + documented errno mapping  |
| `entropy_round_trip.sh`      | getrandom + repeat-differs + stats     |
| `crypto_hash_round_trip.sh`  | BLAKE3 / SHA3-256 / SHA-256 / SHA-512  |
| `vfs_round_trip.sh`          | open / write / read / stat / list      |
| `market_round_trip.sh`       | healthcheck + load_index accept/reject |
| `virtio_rng_round_trip.sh`   | healthcheck + 32B/256B/4096B fills     |
| `virtio_blk_round_trip.sh`   | capacity, read, round-trip, flush      |
| `virtio_net_round_trip.sh`   | MAC, link, tx/rx, oversize reject      |
| `ps2_input_round_trip.sh`    | i8042 IRQ → PIO → ring → IPC pipe      |
| `xhci_round_trip.sh`         | controller bring-up (P0): No-op event  |
| `wallpaper_round_trip.sh`    | display query → surface → present      |

Each script is self-contained: it resolves OVMF, builds the right
kernel target via the kernel `Makefile`, packages an ESP, runs QEMU
with serial captured, and asserts the marker list. The kernel
`Makefile` exposes `make nonos-mk-boot-<name>` wrappers that call
into this directory.

## Running locally

From the kernel checkout (with this repo mounted at `tests/`):

```
make nonos-mk-boot-ramfs
make nonos-mk-boot-ps2-input
make nonos-mk-boot-xhci
```

Set `OVMF=/path/to/OVMF_CODE.fd` if firmware is not in a default
location. The harnesses fail closed when firmware cannot be found.

## Adding a smoke

A new boot smoke goes in three places:

1. The kernel side emits a stable PASS/FAIL marker on serial behind
   the matching feature flag.
2. The kernel `Makefile` adds a `nonos-mk-<name>-test` build target
   and an `nonos-mk-boot-<name>` wrapper that invokes the script
   here.
3. A new script in `boot/` builds the right profile, boots the
   right QEMU device, and greps for the marker set the kernel
   emits.

Markers are the contract. Restructure freely; do not silently
rename what the harness greps for.
