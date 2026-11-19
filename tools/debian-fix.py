#!/usr/bin/env python3
# Debian 套件第二轮修复：
#   1. keyring 包名显式指定（Debian 主源里也有 ubuntu-keyring，会误取）
#   2. Debian 安全源走 security.debian.org（deb.debian.org 没有 <suite>-security）
#   3. apt-mirror 在 Debian 下写两个 deb822 stanza（main/updates + security）
#   4. 国内默认源改用 USTC（aliyun 的 debian 路径在本环境 403）
import pathlib
import sys


def edit(rel, pairs):
    p = pathlib.Path(rel)
    t = p.read_text()
    for old, new in pairs:
        if old not in t:
            print('[!] 锚点缺失', rel, repr(old[:70]))
            sys.exit(1)
        t = t.replace(old, new)
    p.write_text(t)
    print('patched', rel)


edit('distros/debian/conf.sh', [
    ('export KEYRING="${KEYRING:-}"',
     'export KEYRING="${KEYRING:-}"\n'
     'export KEYRING_PKG="${KEYRING_PKG:-debian-archive-keyring}"\n'
     'export SECURITY_MIRROR="${SECURITY_MIRROR:-https://security.debian.org/debian-security}"'),
    ('GUEST_MIRROR_CN="${GUEST_MIRROR_CN:-https://mirrors.aliyun.com/debian}"',
     'GUEST_MIRROR_CN="${GUEST_MIRROR_CN:-https://mirrors.ustc.edu.cn/debian}"'),
])

for rel in ('distros/ubuntu/scripts/fetch-keyring.sh', 'distros/debian/scripts/fetch-keyring.sh'):
    edit(rel, [
        ('for cand in ubuntu-keyring debian-archive-keyring; do',
         'for cand in ${KEYRING_PKG:-} ubuntu-keyring debian-archive-keyring; do\n  [ -n "$cand" ] || continue'),
    ])

edit('distros/debian/scripts/10-rootfs.sh', [
    ('"deb $MIRROR $SUITE-security main contrib non-free-firmware"',
     '"deb ${SECURITY_MIRROR:-$MIRROR} $SUITE-security main contrib non-free-firmware"'),
])

edit('distros/debian/hooks/10-prepare.sh', [
    ('Suites: $SUITE $SUITE-updates $SUITE-security\n'
     'Components: main contrib non-free-firmware\n'
     'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg',
     'Suites: $SUITE $SUITE-updates\n'
     'Components: main contrib non-free-firmware\n'
     'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg\n'
     '\n'
     'Types: deb\n'
     'URIs: ${SECURITY_MIRROR:-$GUEST_MIRROR}\n'
     'Suites: $SUITE-security\n'
     'Components: main contrib non-free-firmware\n'
     'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg'),
])

OLD = '''cat > "$SOURCES" <<EOF
Types: deb
URIs: $URI
Suites: $SUITE $SUITE-updates $SUITE-security
Components: $COMPONENTS
Signed-By: $SIGNED_BY
EOF'''

NEW = '''DEF_SECURITY="https://security.debian.org/debian-security"
if [ "$SUB" = debian ]; then
  SEC_URI=$(printf '%s' "$URI" | sed -e 's|deb.debian.org/debian|security.debian.org/debian-security|' -e 's|/debian$|/debian-security|')
  [ "$SEC_URI" != "$URI" ] || SEC_URI="$DEF_SECURITY"
  cat > "$SOURCES" <<EOF
Types: deb
URIs: $URI
Suites: $SUITE $SUITE-updates
Components: $COMPONENTS
Signed-By: $SIGNED_BY

Types: deb
URIs: $SEC_URI
Suites: $SUITE-security
Components: $COMPONENTS
Signed-By: $SIGNED_BY
EOF
else
  cat > "$SOURCES" <<EOF
Types: deb
URIs: $URI
Suites: $SUITE $SUITE-updates $SUITE-security
Components: $COMPONENTS
Signed-By: $SIGNED_BY
EOF
fi'''

for rel in ('distros/ubuntu/files/usr/local/bin/apt-mirror', 'distros/debian/files/usr/local/bin/apt-mirror'):
    edit(rel, [(OLD, NEW)])

print('done')
