#!/usr/bin/env bash
# 生成 NoCloud seed.iso（cloud-init 用它注入 SSH 公钥 / 主机名）
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

KEY_FILE="${1:-$HOME/.ssh/id_ed25519.pub}"
[ -f "$KEY_FILE" ] || { echo "找不到公钥：$KEY_FILE（先 ssh-keygen -t ed25519）" >&2; exit 1; }

SEED_DIR="$WORK_DIR/seed"
mkdir -p "$SEED_DIR"

cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
hostname: $IMAGE_HOSTNAME
users:
  - name: $USER_NAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: [sudo]
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$KEY_FILE")
ssh_pwauth: false
package_update: false
EOF

cat > "$SEED_DIR/meta-data" <<EOF
instance-id: $IMAGE_NAME-$(date +%s)
local-hostname: $IMAGE_HOSTNAME
EOF

OUT="$OUT_DIR/seed.iso"
if command -v genisoimage >/dev/null 2>&1; then
  genisoimage -quiet -output "$OUT" -volid cidata -joliet -rock "$SEED_DIR/user-data" "$SEED_DIR/meta-data"
elif command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs -quiet -output "$OUT" -volid cidata -joliet -rock "$SEED_DIR/user-data" "$SEED_DIR/meta-data"
elif command -v mkisofs >/dev/null 2>&1; then
  mkisofs -quiet -output "$OUT" -volid cidata -joliet -rock "$SEED_DIR/user-data" "$SEED_DIR/meta-data"
else
  echo "需要 genisoimage / xorriso / mkisofs 之一" >&2; exit 1
fi

echo "已生成：$OUT"
