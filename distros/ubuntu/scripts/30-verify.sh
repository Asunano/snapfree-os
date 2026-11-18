#!/usr/bin/env bash
# 产物校验 + 打印启动方法
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

QCOW2="$OUT_DIR/$IMAGE_NAME.qcow2"

printf '\n=== 产物 ===\n'
ls -lh "$QCOW2" "$QCOW2.sha256" 2>/dev/null
printf '\n=== qcow2 信息 ===\n'
qemu-img info "$QCOW2"
printf '\n=== 完整性 ===\n'
qemu-img check "$QCOW2" || true
printf '\n=== 校验和 ===\n'
cat "$QCOW2.sha256"

printf '\n=== 下一步 ===\n'
cat <<EOF
1) 生成 cloud-init seed（把公钥注入，否则只能靠串口控制台）：
     ./scripts/make-seed.sh ~/.ssh/id_ed25519.pub

2) 本地试启动（需要 KVM + OVMF）：
     ./scripts/test-boot.sh

3) 部署到物理机：
     dd if=$QCOW2 of=/dev/sdX bs=4M status=progress conv=fsync
     # 整盘 dd 后分区不会自动扩展到全盘，首启用 cloud-init 的 growpart 或：
     # growpart /dev/sdX 3 && resize2fs /dev/sdXp3
EOF
