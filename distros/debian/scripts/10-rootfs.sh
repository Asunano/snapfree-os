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
  --components=main,contrib,non-free-firmware
  --include="$PKGS"
  --aptopt='APT::Install-Recommends "false"'
  --aptopt='APT::Install-Suggests "false"'
  --aptopt='Acquire::Languages "none"'
  --format=tar
  --customize-hook="bash '$HERE/hooks/10-prepare.sh' \"\$1\""
  --customize-hook="bash '$HERE/hooks/99-cleanup.sh' \"\$1\""
)
# 宿主 keyring 与目标发行版不同时：
#   --keyring 给 mmdebstrap 自己那趟 apt 用；
#   --setup-hook 把 keyring 拷进 chroot 的 trusted.gpg.d，给 chroot 里的 apt update 用
#   （setup hook 在 apt update 之前执行，这是 man 页明确推荐的做法）
if [ -n "${KEYRING:-}" ]; then
  MMD+=(--keyring="$KEYRING")
  MMD+=(--setup-hook="bash -c 'mkdir -p \"\$1/etc/apt/trusted.gpg.d\"; cp \"$KEYRING\" \"\$1/etc/apt/trusted.gpg.d/99-archive-keyring.gpg\"'")
fi

log "包数量：$(printf '%s' "$PKGS" | tr ',' '\n' | wc -l)（ops=$WITH_OPS qga=$WITH_QGA firmware=$WITH_FIRMWARE）"
log "开始下载并解压（首次约 400-600MB，视网络 5-20 分钟）"
[ -n "${KEYRING:-}" ] && log "使用 keyring：$KEYRING"

rm -f "$ROOTFS_TAR"
"${MMD[@]}" \
  "$SUITE" "$ROOTFS_TAR" \
  "deb $MIRROR $SUITE main contrib non-free-firmware" \
  "deb $MIRROR $SUITE-updates main contrib non-free-firmware" \
  "deb ${SECURITY_MIRROR:-$MIRROR} $SUITE-security main contrib non-free-firmware"

[ -s "$ROOTFS_TAR" ] || die "rootfs.tar 生成失败"
log "rootfs：$(du -h "$ROOTFS_TAR" | cut -f1)"
