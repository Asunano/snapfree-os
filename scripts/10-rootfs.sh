#!/usr/bin/env bash
# 用 mmdebstrap 从目标源构建最小 rootfs（tar 包）
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

log(){ printf '  · %s\n' "$*"; }
die(){ printf '[!] %s\n' "$*" >&2; exit 1; }

ROOTFS_TAR="$WORK_DIR/rootfs.tar"
mkdir -p "$WORK_DIR"

# 读清单文件成逗号分隔
read_list(){ grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null | tr -d ' \t' | paste -sd, - || true; }

PKGS=$(read_list "$KIT_DIR/packages.list")
[ -n "$PKGS" ] || die "packages.list 是空的"
if [ "$WITH_OPS" = "1" ]; then
  OPS=$(read_list "$KIT_DIR/packages-ops.list")
  [ -n "$OPS" ] && PKGS="$PKGS,$OPS"
fi
[ "$WITH_QGA" = "1" ] && PKGS="$PKGS,qemu-guest-agent"
[ "$WITH_FIRMWARE" = "1" ] && PKGS="$PKGS,linux-firmware"

MMD=(mmdebstrap
  --variant=apt
  --arch="$ARCH"
  --components=main,universe
  --include="$PKGS"
  --apt-options="--no-install-recommends"
  --format=tar
  --customize-hook="bash '$HERE/hooks/10-prepare.sh' \"\$1\""
  --customize-hook="bash '$HERE/hooks/99-cleanup.sh' \"\$1\""
)
# 宿主 keyring 不是目标发行版时必须显式指定，否则 apt 验签直接失败
[ -n "${KEYRING:-}" ] && MMD+=(--keyring="$KEYRING")

log "包数量：$(printf '%s' "$PKGS" | tr ',' '\n' | wc -l)（ops=$WITH_OPS qga=$WITH_QGA firmware=$WITH_FIRMWARE）"
log "开始下载并解压（首次约 400-600MB，视网络 5-20 分钟）"
[ -n "${KEYRING:-}" ] && log "使用 keyring：$KEYRING"

rm -f "$ROOTFS_TAR"
"${MMD[@]}" \
  "$SUITE" "$ROOTFS_TAR" \
  "deb $MIRROR $SUITE main universe" \
  "deb $MIRROR $SUITE-updates main universe" \
  "deb $MIRROR $SUITE-security main universe"

[ -s "$ROOTFS_TAR" ] || die "rootfs.tar 生成失败"
log "rootfs：$(du -h "$ROOTFS_TAR" | cut -f1)"
