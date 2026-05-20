#!/usr/bin/env bash
# NONOS Operating System
# Copyright (C) 2026 NONOS Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Boot-test harness for the signed desktop GUI profile. The test boots
# QEMU with the devices the profile expects and proves that init admits
# the storage, GPU, network, input, compositor, WM, and shell capsules.

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly LOG="${REPO_ROOT}/target/boot-test-desktop-gui.log"
readonly DISK="${REPO_ROOT}/target/test-desktop-gui.img"
readonly TIMEOUT_SECS="${BOOT_TEST_TIMEOUT:-300}"

cd "${REPO_ROOT}"

resolve_ovmf() {
    if [ -n "${OVMF:-}" ] && [ -r "${OVMF}" ]; then
        echo "${OVMF}"
        return 0
    fi
    for candidate in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/qemu/OVMF.fd \
        /usr/share/ovmf/OVMF.fd \
        /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /opt/homebrew/share/qemu/edk2-x86_64-code.fd \
        /usr/local/share/qemu/edk2-x86_64-code.fd ; do
        if [ -r "${candidate}" ]; then
            echo "${candidate}"
            return 0
        fi
    done
    return 1
}

OVMF_PATH="$(resolve_ovmf)" || {
    echo "[harness] FAIL: no readable OVMF firmware found" >&2
    echo "[harness] install ovmf/edk2-ovmf or set OVMF=/path/to/OVMF_CODE.fd" >&2
    exit 1
}
echo "[harness] firmware: ${OVMF_PATH}"

echo "[harness] building signed desktop GUI profile"
make nonos-mk-desktop-gui-prod >/dev/null

echo "[harness] packaging ESP"
make nonos-mk-esp >/dev/null
mkdir -p "$(dirname "${LOG}")"
truncate -s 64M "${DISK}"
: > "${LOG}"

if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD=(timeout "${TIMEOUT_SECS}")
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD=(gtimeout "${TIMEOUT_SECS}")
else
    TIMEOUT_CMD=(perl -e 'alarm shift; exec @ARGV or die "exec failed: $!"' "${TIMEOUT_SECS}")
fi

echo "[harness] booting QEMU desktop chain (timeout ${TIMEOUT_SECS}s)"
set +e
"${TIMEOUT_CMD[@]}" qemu-system-x86_64 \
    -m 2G -cpu max -smp 2 -machine q35 \
    -drive "format=raw,file=fat:rw:${REPO_ROOT}/target/esp" \
    -drive if=pflash,format=raw,readonly=on,file="${OVMF_PATH}" \
    -drive "file=${DISK},if=none,id=vd0,format=raw" \
    -device virtio-blk-pci,drive=vd0 \
    -device virtio-gpu-pci,disable-modern=on,vectors=0 \
    -device virtio-rng-pci \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -device qemu-xhci,id=xhci \
    -device usb-tablet,bus=xhci.0 \
    -serial "file:${LOG}" -display none -no-reboot &
QEMU_PID=$!

EXPECTED=(
    "[INIT] Starting"
    "[DRIVER-VIRTIO-RNG] capsule spawned"
    "[DRIVER-VIRTIO-BLK] capsule spawned"
    "[DRIVER-VIRTIO-GPU] capsule spawned"
    "[DRIVER-VIRTIO-NET] capsule spawned"
    "[DRIVER-PS2-INPUT] capsule spawned"
    "[DRIVER-XHCI] capsule spawned"
    "[VFS] capsule spawned"
    "[NET-L2] capsule spawned"
    "[NET-IP] capsule spawned"
    "[NET-UDP] capsule spawned"
    "[NET-DHCP] capsule spawned"
    "[INPUT-ROUTER] capsule spawned"
    "[COMPOSITOR] capsule spawned"
    "[WM] capsule spawned"
    "[DESKTOP-SHELL] capsule spawned"
    "[INIT] Capsules spawned"
    "[input_router] boot"
    "[compositor] setup complete"
    "[wm] setup complete"
    "[desktop_shell] overlay attached"
)

DEADLINE=$(( $(date +%s) + TIMEOUT_SECS ))
while [ "$(date +%s)" -lt "${DEADLINE}" ]; do
    if grep -qF "[desktop_shell] overlay attached" "${LOG}" 2>/dev/null; then
        break
    fi
    if grep -qF "[FATAL]" "${LOG}" 2>/dev/null; then
        break
    fi
    if grep -qF "setup failed" "${LOG}" 2>/dev/null; then
        break
    fi
    if grep -qF "capsule manifest rejected" "${LOG}" 2>/dev/null; then
        break
    fi
    sleep 1
done

kill "${QEMU_PID}" 2>/dev/null || true
wait "${QEMU_PID}" 2>/dev/null || true
set -e

echo "[harness] verifying desktop boot markers in ${LOG}"
MISSING=0
for marker in "${EXPECTED[@]}"; do
    if ! grep -qF "${marker}" "${LOG}"; then
        echo "  MISSING: ${marker}"
        MISSING=$((MISSING + 1))
    fi
done

if grep -qF "[FATAL]" "${LOG}"; then
    echo "[harness] FAIL: fatal marker emitted"
    grep -F "[FATAL]" "${LOG}"
    exit 1
fi
if grep -qF "setup failed" "${LOG}"; then
    echo "[harness] FAIL: userland setup failed"
    grep -F "setup failed" "${LOG}"
    exit 1
fi
if grep -qF "capsule manifest rejected" "${LOG}"; then
    echo "[harness] FAIL: trust verifier rejected a capsule"
    grep -F "capsule manifest rejected" "${LOG}"
    exit 1
fi
if [ "${MISSING}" -ne 0 ]; then
    echo "[harness] FAIL: ${MISSING} expected markers missing"
    exit 1
fi

echo "[harness] PASS: signed desktop GUI capsule chain admitted by init"
exit 0
