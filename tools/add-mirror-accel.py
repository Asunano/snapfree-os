#!/usr/bin/env python3
# 给 installer/reinstall.sh 加“镜像下载加速”：
#   国内机器 -> 按优先级探测镜像站
#   海外机器 -> GitHub 直连可用就直连，不通才走镜像站
# 只代理 catalog 里的 GitHub 链接，不影响用户自传的 --img
import pathlib
import sys

p = pathlib.Path('installer/reinstall.sh')
t = p.read_text()

BLOCK = r'''# [snapfree] 镜像下载加速（只作用于 catalog 里的 GitHub 链接）
#   国内机器：按优先级探测镜像站，命中即用
#   海外机器：GitHub 直连可用就直连，不通才用镜像站
sf_mirrors() {
    printf '%s\n' \
        https://mirror-one.losn.cc \
        https://mirror.drxian.qzz.io \
        https://v4.gh-proxy.org \
        https://axisnow.gh-proxy.org
}

# 探测镜像站是否能拿到目标文件（HEAD 优先，不支持 HEAD 的用 1KB Range 兜底）
sf_mirror_probe() {
    curl -fsSLI -o /dev/null --max-time 8 --connect-timeout 5 "$1" >/dev/null 2>&1 && return 0
    curl -fsSL -o /dev/null -r 0-1023 --max-filesize 65536 \
        --max-time 8 --connect-timeout 5 "$1" >/dev/null 2>&1
}

sf_accel_is_cn() {
    if [ -n "${_loc:-}" ]; then
        [ "$_loc" = CN ]
        return
    fi
    local _c
    _c=$(curl -fsS --max-time 6 https://api.ip.sb/geoip 2>/dev/null |
        tr ',' '\n' | sed -n 's/.*"country_code":"\([A-Z]*\)".*/\1/p' | head -n 1)
    [ -n "$_c" ] && _loc=$_c
    [ "$_c" = CN ]
}

sf_accel_url() {
    local _u=$1 _m
    case "$_u" in
    https://github.com/* | https://raw.githubusercontent.com/* | https://objects.githubusercontent.com/*) ;;
    *)
        printf '%s' "$_u"
        return 0
        ;;
    esac

    # 同一趟安装里选中的镜像站会缓存，避免每个链接都探测一通
    if [ -n "${_sf_mirror:-}" ]; then
        printf '%s/%s' "$_sf_mirror" "$_u"
        return 0
    fi

    if sf_accel_is_cn; then
        for _m in $(sf_mirrors); do
            if sf_mirror_probe "$_m/$_u"; then
                _sf_mirror=$_m
                echo "Location: CN, mirror=$_m" >&2
                printf '%s/%s' "$_m" "$_u"
                return 0
            fi
        done
        echo "mirror: 国内镜像站均不可用，回落到 GitHub 直连" >&2
        printf '%s' "$_u"
        return 0
    fi

    if curl -fsSLI -o /dev/null --max-time 8 --connect-timeout 5 https://github.com/ >/dev/null 2>&1; then
        printf '%s' "$_u"
        return 0
    fi
    echo "mirror: GitHub 不可达，尝试镜像站" >&2
    for _m in $(sf_mirrors); do
        if sf_mirror_probe "$_m/$_u"; then
            _sf_mirror=$_m
            echo "Location: 非 CN 且 GitHub 不通, mirror=$_m" >&2
            printf '%s/%s' "$_m" "$_u"
            return 0
        fi
    done
    printf '%s' "$_u"
}
'''

if 'sf_accel_url() {' in t:
    print('already patched')
    sys.exit(0)

ANCHOR = 'sf_lookup_img() {\n'
if ANCHOR not in t:
    print('[!] sf_lookup_img 锚点缺失')
    sys.exit(1)
t = t.replace(ANCHOR, BLOCK + ANCHOR, 1)

OLD_ECHO = '''        [ "$_arch" = any ] || [ "$_arch" = "$(sf_arch)" ] || continue
        echo "$_url"'''
NEW_ECHO = '''        [ "$_arch" = any ] || [ "$_arch" = "$(sf_arch)" ] || continue
        sf_accel_url "$_url"'''
if OLD_ECHO not in t:
    print('[!] sf_lookup_img 输出锚点缺失')
    sys.exit(1)
t = t.replace(OLD_ECHO, NEW_ECHO, 1)

OLD_SEL = '    sf_sel_img=$url'
NEW_SEL = '    sf_sel_img=$(sf_accel_url "$url")'
if OLD_SEL not in t:
    print('[!] 菜单赋值锚点缺失')
    sys.exit(1)
t = t.replace(OLD_SEL, NEW_SEL, 1)

p.write_text(t)
print('patched installer/reinstall.sh')
