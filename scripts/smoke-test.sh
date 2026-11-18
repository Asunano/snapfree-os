#!/usr/bin/env bash
# CI 冒烟启动：TCG 无 KVM 也能跑，看串口是否出现 cloud-init / login
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

IMG="$OUT_DIR/$IMAGE_NAME.qcow2"
LOG="$WORK_DIR/serial.log"
TIMEOUT="${SMOKE_TIMEOUT:-420}"

# CI 里是干净 checkout，work/ 与 out/ 可能不存在
mkdir -p "$WORK_DIR" "$OUT_DIR"

[ -f "$IMG" ] || { echo "[!] 找不到 $IMG"; ls -lR "$OUT_DIR" 2>/dev/null; exit 1; }

echo "镜像：$IMG（$(du -h "$IMG" | cut -f1)）"

CODE=""
for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
  [ -f "$f" ] && CODE="$f" && break
done
[ -n "$CODE" ] || { echo "[!] 缺 OVMF 固件（apt install ovmf）"; ls /usr/share/OVMF 2>/dev/null; exit 1; }

echo "OVMF：$CODE"

VARS_SRC="${CODE/OVMF_CODE/OVMF_VARS}"
[ -f "$VARS_SRC" ] || VARS_SRC="$(dirname "$CODE")/OVMF_VARS.fd"
[ -f "$VARS_SRC" ] || { echo "[!] 缺 OVMF_VARS 模板"; ls /usr/share/OVMF 2>/dev/null; exit 1; }
VARS="$WORK_DIR/OVMF_VARS.fd"
cp -f "$VARS_SRC" "$VARS"

: > "$LOG"
echo "启动 QEMU（TCG）：最多等 ${TIMEOUT}s"

qemu-system-x86_64 \
  -accel tcg -cpu max -smp 2 -m 2048 \
  -drive "if=pflash,format=raw,readonly=on,file=$CODE" \
  -drive "if=pflash,format=raw,file=$VARS" \
  -drive "file=$IMG,if=virtio,format=qcow2" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -serial "file:$LOG" -no-reboot \
  >/dev/null 2>&1 &
QPID=$!

found=0
for _ in $(seq 1 "$TIMEOUT"); do
  if grep -qiE 'Cloud-init v|cloud-init.*finished|login:' "$LOG" 2>/dev/null; then
    found=1; break
  fi
  kill -0 "$QPID" 2>/dev/null || break
  sleep 1
done

kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

echo "--- 串口尾部 ---"
tail -n 40 "$LOG" || true

if [ "$found" -eq 1 ]; then
  echo "[+] 冒烟通过：内核启动并进入 cloud-init/login"
else
  echo "[!] 冒烟失败：${TIMEOUT}s 内没看到 cloud-init 或 login"
  exit 1
fi

# 顺手确认 GRUB 确实写进去了
grep -q 'Ubuntu 26.04 LTS' "$LOG" && echo "[+] GRUB 菜单品牌字段命中" || true
