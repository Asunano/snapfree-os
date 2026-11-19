#!/usr/bin/env python3
# 让 tools/snapfree-check.sh 同时支持 Ubuntu 26.04/24.04 与 Debian 13/12
import pathlib
import sys

p = pathlib.Path('tools/snapfree-check.sh')
t = p.read_text()

OLD1 = '''    resolute) ok "确认为 Ubuntu 26.04 LTS（resolute）" ;;
    noble)    ok "确认为 Ubuntu 24.04 LTS（noble）" ;;
    *)        warn "非预期代号：${VERSION_CODENAME:-?}（自己改的就忽略）" ;;'''
NEW1 = '''    ubuntu:resolute)  ok "确认为 Ubuntu 26.04 LTS（resolute）" ;;
    ubuntu:noble)     ok "确认为 Ubuntu 24.04 LTS（noble）" ;;
    debian:trixie)    ok "确认为 Debian 13（trixie）" ;;
    debian:bookworm)  ok "确认为 Debian 12（bookworm）" ;;
    *)                warn "非预期发行版/代号：${ID:-?}:${VERSION_CODENAME:-?}（自己改的就忽略）" ;;'''

OLD2 = '''if [ -r /etc/apt/sources.list.d/ubuntu.sources ]; then
  URIS=$(awk -F': ' '/^URIs:/{print $2}' /etc/apt/sources.list.d/ubuntu.sources | tr '\\n' ' ')
  info "镜像源：${URIS:-?}"
  echo "$URIS" | grep -q 'mirrors.aliyun.com' && ok "使用国内阿里云源" || info "非阿里云源（自己换过就忽略）"
else
  warn "缺 /etc/apt/sources.list.d/ubuntu.sources（源可能被手动改过）"
fi'''

NEW2 = '''SRC=""
for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/debian.sources; do
  [ -r "$f" ] && { SRC="$f"; break; }
done
if [ -n "$SRC" ]; then
  URIS=$(awk -F': ' '/^URIs:/{print $2}' "$SRC" | tr '\\n' ' ')
  info "镜像源（$SRC）：${URIS:-?}"
  echo "$URIS" | grep -qE 'mirrors\.aliyun\.com|mirrors\.ustc\.edu\.cn|tuna\.tsinghua' && ok "使用国内镜像源" || info "非国内源（自己换过就忽略）"
  awk '/^URIs:/{u=$2} /^Suites:/{print u" "$2}' "$SRC" | grep -q 'security' && info "已配置 security suite"
else
  warn "缺 deb822 源文件（ubuntu.sources / debian.sources，源可能被手动改过）"
fi'''

if OLD1 not in t:
    print('[!] 发行版判定锚点缺失')
    sys.exit(1)
t = t.replace('case "${VERSION_CODENAME:-}" in', 'case "${ID:-}:${VERSION_CODENAME:-}" in').replace(OLD1, NEW1)

if OLD2 not in t:
    print('[!] apt 源检查锚点缺失')
    sys.exit(1)
t = t.replace(OLD2, NEW2)

p.write_text(t)
print('patched tools/snapfree-check.sh')
