#!/usr/bin/env python3
# 强化安装器的国内判定：ip.sb 被挡时依次退化到 ipinfo / qualcomm trace
import pathlib
import sys

p = pathlib.Path('installer/reinstall.sh')
t = p.read_text()

OLD = '''sf_accel_is_cn() {
    if [ -n "${_loc:-}" ]; then
        [ "$_loc" = CN ]
        return
    fi
    local _c
    _c=$(curl -fsS --max-time 6 https://api.ip.sb/geoip 2>/dev/null |
        tr ',' '\\n' | sed -n 's/.*"country_code":"\\([A-Z]*\\)".*/\\1/p' | head -n 1)
    [ -n "$_c" ] && _loc=$_c
    [ "$_c" = CN ]
}'''

NEW = '''sf_accel_is_cn() {
    if [ -n "${_loc:-}" ]; then
        [ "$_loc" = CN ]
        return
    fi
    local _c
    # 依次尝试多种识别方式，任一命中 CN 即算国内（单点被挡不影响判定）
    _c=$(curl -fsS --max-time 6 -A 'curl/8.5.0' https://api.ip.sb/geoip 2>/dev/null |
        tr ',' '\\n' | sed -n 's/.*"country_code":"\\([A-Z]*\\)".*/\\1/p' | head -n 1)
    [ -n "$_c" ] || _c=$(curl -fsS --max-time 6 https://ipinfo.io/country 2>/dev/null | tr -d ' \\r\\n')
    [ -n "$_c" ] || _c=$(curl -fsS --max-time 6 http://www.qualcomm.cn/cdn-cgi/trace 2>/dev/null |
        sed -n 's/^loc=\\([A-Z]*\\).*/\\1/p' | head -n 1)
    [ -n "$_c" ] && _loc=$_c
    [ "$_c" = CN ]
}'''

if NEW in t:
    print('already patched')
    sys.exit(0)
if OLD not in t:
    print('[!] sf_accel_is_cn 锚点缺失')
    sys.exit(1)
t = t.replace(OLD, NEW, 1)
p.write_text(t)
print('patched sf_accel_is_cn')
