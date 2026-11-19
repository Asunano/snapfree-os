#!/usr/bin/env python3
import pathlib

P = pathlib.Path('installer/reinstall.sh')
t = P.read_text()

NEW = '''# 测速：拉 1MB 区间，返回字节/秒；拿不到或是错误页就失败
# 很多代理会用 200 + text/html 返回错误页，所以要校验 content-type 与大小
sf_mirror_speed() {
    local _o
    _o=$(curl -sSL -o /dev/null --max-time 10 --connect-timeout 5 \\
        -r 0-1048575 --max-filesize 4194304 \\
        -w '%{http_code} %{size_download} %{speed_download} %{content_type}' "$1" 2>/dev/null) || return 1
    printf '%s\\n' "$_o" | awk '
        $1 !~ /^(200|206)$/ { exit 1 }
        $4 ~ /text\\/html/ { exit 1 }
        $2 < 65536 { exit 1 }
        { printf "%.0f\\n", $3 }'
}

'''

start = t.index('# 测速：拉 1MB 区间')
end = t.index('sf_accel_is_cn() {')
if 'awk ' in t[start:end]:
    print('already fixed')
else:
    t = t[:start] + NEW + t[end:]
    P.write_text(t)
    print('fixed sf_mirror_speed parse')

for p in ['tools/fix-speed-parse.py', 'tools/speedfix.flag', '.github/workflows/speed-fix.yml']:
    f = pathlib.Path(p)
    if f.exists():
        f.unlink()
        print('rm', p)
