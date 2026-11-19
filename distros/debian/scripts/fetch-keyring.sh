#!/usr/bin/env bash
# 从目标发行版索引里取 archive keyring（宿主 keyring 太旧 -> NO_PUBKEY）
# 用法：KEYRING=$(bash scripts/fetch-keyring.sh)
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

echo "  · 拉取 $SUITE 的 archive keyring（宿主 keyring 不匹配）" >&2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
IDX="$TMP/Packages.gz"
for comp in main universe contrib; do
  if curl -fsSL --retry 3 --max-time 120 "$MIRROR/dists/$SUITE/$comp/binary-$ARCH/Packages.gz" -o "$IDX"; then
    break
  fi
done
[ -s "$IDX" ] || { echo "[!] 拉取 $SUITE 索引失败：$MIRROR" >&2; exit 1; }

PKG=""
for cand in ubuntu-keyring debian-archive-keyring; do
  if gzip -dc "$IDX" | grep -q "^Package: $cand$"; then PKG="$cand"; break; fi
done
[ -n "$PKG" ] || { echo "[!] $SUITE 索引里找不到 archive keyring 包" >&2; exit 1; }

FN=$(gzip -dc "$IDX" | awk -v p="$PKG" '/^Package: /{cur=$2} cur==p && /^Filename: /{print $2}' | sed -n '1p')
[ -n "$FN" ] || { echo "[!] 找不到 $PKG 的 Filename" >&2; exit 1; }
curl -fsSL --retry 3 --max-time 120 "$MIRROR/$FN" -o "$TMP/kr.deb"
dpkg-deb -x "$TMP/kr.deb" "$TMP/x"
KR=$(find "$TMP/x/usr/share/keyrings" -name '*-archive-keyring.gpg' -print -quit 2>/dev/null || true)
[ -n "$KR" ] || { echo '[!] deb 里没有 archive keyring' >&2; exit 1; }
mkdir -p "$WORK_DIR"
DEST="$WORK_DIR/$(basename "$KR")"
cp "$KR" "$DEST"
echo "  · keyring 已就位：$DEST" >&2
printf '%s\n' "$DEST"
