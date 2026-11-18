#!/usr/bin/env bash
# 用 QEMU 启动刚构建的 qcow2（UEFI + 串口控制台）
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

QCOW2="$OUT_DIR/$IMAGE_NAME.qcow2"
SEED="$OUT_DIR/seed.iso"
VARS="$WORK_DIR/OVMF_VARS.fd"

CODE=""
for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
  [ -f "$f" ] && CODE="$f" && break
done
[ -n "$CODE" ] || { echo "缺 OVMF 固件（apt install ovmf）" >&2; exit 1; }

SRC_VARS="${CODE/OVMF_CODE/OVMF_VARS}"
[ -f "$SRC_VARS" ] || SRC_VARS="$(dirname "$CODE")/OVMF_VARS.fd"
[ -f "$SRC_VARS" ] || { echo "缺 OVMF_VARS 模板" >&2; exit 1; }

[ -f "$VARS" ] || cp "$SRC_VARS" "$VARS"
[ -f "$SEED" ] || echo "提示：没有 $SEED，将只走串口控制台（不会自动建用户）"

ARGS=(
  -enable-kvm -cpu host -smp 2 -m 2048
  -drive "if=pflash,format=raw,readonly=on,file=$CODE"
  -drive "if=pflash,format=raw,file=$VARS"
  -drive "file=$QCOW2,if=virtio,format=qcow2,cache=writeback"
  -netdev user,id=n0,hostfwd=tcp::2222-:22
  -device virtio-net-pci,netdev=n0
  -nographic
)
[ -f "$SEED" ] && ARGS+=( -drive "file=$SEED,if=virtio,format=raw,readonly=on" )

echo "串口控制台：Ctrl-A 然后 X 退出；SSH: ssh -p 2222 $USER_NAME@127.0.0.1"
exec qemu-system-x86_64 "${ARGS[@]}"
