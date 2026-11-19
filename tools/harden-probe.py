#!/usr/bin/env python3
# 探测加固：HEAD 返回 text/html 之类的错误页不算命中
import pathlib
import sys

p = pathlib.Path('installer/reinstall.sh')
t = p.read_text()

OLD = '''# 探测镜像站是否能拿到目标文件（HEAD 优先，不支持 HEAD 的用 1KB Range 兜底）
sf_mirror_probe() {
    curl -fsSLI -o /dev/null --max-time 8 --connect-timeout 5 "$1" >/dev/null 2>&1 && return 0
    curl -fsSL -o /dev/null -r 0-1023 --max-filesize 65536 \\
        --max-time 8 --connect-timeout 5 "$1" >/dev/null 2>&1
}'''

NEW = '''# 探测镜像站是否能拿到目标文件（HEAD 优先，不支持 HEAD 的用 1KB Range 兜底）
# 注意：很多代理会用 200 + text/html 返回错误页，因此要校验 content-type/content-length
sf_mirror_probe() {
    local _h _ct _cl
    _h=$(curl -fsSLI --max-time 8 --connect-timeout 5 "$1" 2>/dev/null) || {
        curl -fsSL -o /dev/null -r 0-1023 --max-filesize 65536 \\
            --max-time 8 --connect-timeout 5 "$1" >/dev/null 2>&1
        return
    }
    _ct=$(printf '%s\\n' "$_h" | tr -d '\\r' | awk 'tolower($1)=="content-type:"{v=tolower($2)} END{print v}')
    _cl=$(printf '%s\\n' "$_h" | tr -d '\\r' | awk 'tolower($1)=="content-length:"{v=$2} END{print v}')
    case "$_ct" in
    *text/html* | *application/json* | *text/plain*) return 1 ;;
    esac
    if [ -n "$_cl" ]; then
        [ "$_cl" -gt 65536 ] 2>/dev/null && return 0
        return 1
    fi
    return 0
}'''

if NEW in t:
    print('already patched')
    sys.exit(0)
if OLD not in t:
    print('[!] sf_mirror_probe 锚点缺失')
    sys.exit(1)
t = t.replace(OLD, NEW, 1)
p.write_text(t)
print('patched sf_mirror_probe')
