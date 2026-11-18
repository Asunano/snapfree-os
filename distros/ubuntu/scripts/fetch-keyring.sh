#!/usr/bin/env bash
# 从目标发行版的索引里取 ubuntu-keyring，解决「宿主 keyring 太旧 -> NO_PUBKEY」
# 用法：KEYRING=$(bash scripts/fetch-keyring.sh)
# 只在 stdout 输出 keyring 路径，其余信息走 stderr
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

echo "  · 拉取 $SUITE 的 ubuntu-keyring（宿主 keyring 不匹配）" >&2

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

IDX="$TMP/Packages.gz"
for comp in main universe; do
  if curl -fsSL --retry 3 --max-time 120 \
      "$MIRROR/dists/$SUITE/$comp/binary-$ARCH/Packages.gz" -o "$IDX"; then
    break
  fi
done
[ -s "$IDX" ] || { echo "[!] 拉取 $SUITE 索引失败：$MIRROR" >&2; exit 1; }

# 注意：这里不能用 awk 的 exit 提前退出，否则 gzip 收到 SIGPIPE，pipefail 下整条命令返回 141
FN=$(gzip -dc "$IDX" | awk '
  /^Package: /{p=$2}
  p=="ubuntu-keyring" && /^Filename: /{print $2}
' | sed -n '1p')
[ -n "$FN" ] || { echo "[!] $SUITE 索引里找不到 ubuntu-keyring" >&2; exit 1; }

curl -fsSL --retry 3 --max-time 120 "$MIRROR/$FN" -o "$TMP/keyring.deb"
dpkg-deb -x "$TMP/keyring.deb" "$TMP/x"

KR=$(find "$TMP/x/usr/share/keyrings" -name 'ubuntu-archive-keyring.gpg' -print -quit 2>/dev/null || true)
[ -n "$KR" ] || { echo "[!] deb 里没有 ubuntu-archive-keyring.gpg" >&2; exit 1; }

mkdir -p "$WORK_DIR"
DEST="$WORK_DIR/ubuntu-archive-keyring.gpg"
cp "$KR" "$DEST"
echo "  · keyring 已就位：$DEST" >&2
printf '%s\n' "$DEST"
