#!/usr/bin/env python3
# 一次性脚手架：从 distros/ubuntu 生成 distros/debian，并把通用脚本、安装器补丁一起落地
# 幂等：distros/debian 已存在时只做补丁，不重复复制
import pathlib
import shutil
import sys

root = pathlib.Path('.')
PROBE = None

up = root / 'distros/ubuntu'
db = root / 'distros/debian'


def write(rel, text, also_up=False):
    p = db / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    print('  written', p)
    if also_up:
        q = up / rel
        q.parent.mkdir(parents=True, exist_ok=True)
        q.write_text(text)
        print('  written', q)


def sub(rel, old, new, must=True, also_up=False):
    p = db / rel
    if not p.exists():
        if must:
            print('[!] 文件不存在:', p)
            sys.exit(1)
        return
    t = p.read_text()
    n = t.count(old)
    if n == 0 and must:
        print('[!] 锚点缺失:', p, repr(old))
        sys.exit(1)
    p.write_text(t.replace(old, new))
    print('  patched', p, repr(old), '->', repr(new), 'x', n)
    if also_up:
        q = up / rel
        t2 = q.read_text()
        if t2.count(old):
            q.write_text(t2.replace(old, new))
            print('  patched', q, 'x', t2.count(old))


if not db.exists():
    shutil.copytree(up, db)
    print('copied distros/ubuntu -> distros/debian')
else:
    print('distros/debian 已存在，跳过复制')

for junk in ('out', 'work', 'build.log'):
    q = db / junk
    if q.is_dir():
        shutil.rmtree(q)
    elif q.exists():
        q.unlink()

# ============ 1. 通用脚本（两个套件共用同一份实现）============
APT_MIRROR = r'''#!/usr/bin/env bash
# 镜像内 apt 源切换工具（Ubuntu / Debian 通用）
#   apt-mirror                 列出可选镜像
#   apt-mirror auto            按出口 IP 所在地区自动选源（国内/海外）
#   apt-mirror aliyun          切换并 apt update
#   apt-mirror official        换回官方源
#   apt-mirror https://xxx/xxx 自定义源
set -Eeuo pipefail

[ "$(id -u)" -eq 0 ] || { echo "需要 root：sudo apt-mirror ..."; exit 1; }

SOURCES=""
for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/debian.sources; do
  [ -f "$f" ] && { SOURCES="$f"; break; }
done
[ -n "$SOURCES" ] || { echo "找不到 deb822 源文件（ubuntu.sources / debian.sources）" >&2; exit 1; }

ID=$(. /etc/os-release; printf '%s' "${ID:-ubuntu}")
SUB=ubuntu
KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
DEF_COMPONENTS="main universe"
DEF_OFFICIAL="http://archive.ubuntu.com/ubuntu"
if [ "$ID" = debian ]; then
  SUB=debian
  KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg
  DEF_COMPONENTS="main contrib non-free-firmware"
  DEF_OFFICIAL="http://deb.debian.org/debian"
fi

declare -A MIRRORS=(
  [aliyun]="https://mirrors.aliyun.com/$SUB"
  [tuna]="https://mirrors.tuna.tsinghua.edu.cn/$SUB"
  [ustc]="https://mirrors.ustc.edu.cn/$SUB"
  [huawei]="https://repo.huaweicloud.com/$SUB"
  [official]="$DEF_OFFICIAL"
)
if [ "$SUB" = ubuntu ]; then MIRRORS[azure]="http://azure.archive.ubuntu.com/ubuntu"; fi

NAME="${1:-}"
if [ "$NAME" = "auto" ]; then exec /usr/local/bin/sf-mirror-auto; fi
if [ -z "$NAME" ] || [ "$NAME" = "list" ] || [ "$NAME" = "--list" ]; then
  printf '可用镜像（%s）：\n' "$SUB"
  for k in "${!MIRRORS[@]}"; do printf '  %-9s %s\n' "$k" "${MIRRORS[$k]}"; done | sort
  printf '  %-9s %s\n' auto "按出口 IP 自动选择（国内/海外）"
  printf '\n当前配置（%s）：\n' "$SOURCES"
  grep -E '^URIs:' "$SOURCES" 2>/dev/null || echo '  （未找到 URIs）'
  exit 0
fi

if [ -n "${MIRRORS[$NAME]:-}" ]; then URI="${MIRRORS[$NAME]}"
elif [[ "$NAME" == http* ]]; then URI="${NAME%/}"
else echo "未知镜像：$NAME（先用 apt-mirror 看列表）" >&2; exit 1
fi

SUITE=$(awk '/^Suites:/{print $2; exit}' "$SOURCES" 2>/dev/null || true)
[ -n "$SUITE" ] || SUITE=$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")
COMPONENTS=$(awk '/^Components:/{sub(/^Components:[[:space:]]*/,""); print; exit}' "$SOURCES" 2>/dev/null || true)
[ -n "$COMPONENTS" ] || COMPONENTS="$DEF_COMPONENTS"
SIGNED_BY=$(awk '/^Signed-By:/{sub(/^Signed-By:[[:space:]]*/,""); print; exit}' "$SOURCES" 2>/dev/null || true)
[ -n "$SIGNED_BY" ] || SIGNED_BY="$KEYRING"

BACKUP=$(mktemp)
cp "$SOURCES" "$BACKUP"
cat > "$SOURCES" <<EOF
Types: deb
URIs: $URI
Suites: $SUITE $SUITE-updates $SUITE-security
Components: $COMPONENTS
Signed-By: $SIGNED_BY
EOF

echo "切换至 $URI（$SUITE / $COMPONENTS）"
if ! apt-get update -q; then
  echo '更新失败，回滚原配置' >&2
  cp "$BACKUP" "$SOURCES"
  rm -f "$BACKUP"
  exit 1
fi
rm -f "$BACKUP"
echo '完成。'
'''
write('files/usr/local/bin/apt-mirror', APT_MIRROR, also_up=True)

FETCH_KEYRING = r'''#!/usr/bin/env bash
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
'''
write('scripts/fetch-keyring.sh', FETCH_KEYRING, also_up=True)

# ============ 2. Debian 的 conf.sh ============
CONF = r'''#!/usr/bin/env bash
# ============================================================
# Debian 13/12 无 snap 服务器镜像 —— 构建参数（全部可用环境变量覆盖）
#   例：SUITE=bookworm MIRROR=http://deb.debian.org/debian ./build.sh
# ============================================================
KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export KIT_DIR

_as_bool(){ case "${1:-}" in true|TRUE|True|yes|YES|1) echo 1 ;; *) echo 0 ;; esac; }

# ---- 发行版 / 源 ----
export SUITE="${SUITE:-trixie}"
export MIRROR="${MIRROR:-http://deb.debian.org/debian}"
export GUEST_MIRROR="${GUEST_MIRROR:-http://deb.debian.org/debian}"
export GUEST_MIRROR_CN="${GUEST_MIRROR_CN:-https://mirrors.aliyun.com/debian}"
export GUEST_MIRROR_DEFAULT="${GUEST_MIRROR_DEFAULT:-http://deb.debian.org/debian}"
export MIRROR_AUTO="${MIRROR_AUTO:-1}"
export ARCH="${ARCH:-amd64}"
export KEYRING="${KEYRING:-}"

# ---- 产物 ----
export OUT_DIR="${OUT_DIR:-$KIT_DIR/out}"
export WORK_DIR="${WORK_DIR:-$KIT_DIR/work}"
case "$SUITE" in
  trixie)   _VER="13" ;;
  bookworm) _VER="12" ;;
  forky)    _VER="14" ;;
  *)        _VER="$SUITE" ;;
esac
export IMAGE_NAME="${IMAGE_NAME:-debian-${_VER}-server-snapfree-$ARCH}"
export IMAGE_HOSTNAME="${IMAGE_HOSTNAME:-debian-server}"

# ---- 磁盘 ----
export IMG_SIZE="${IMG_SIZE:-10G}"
export ESP_SIZE_MIB="${ESP_SIZE_MIB:-256}"
export QCOW2_COMPRESS="${QCOW2_COMPRESS:-1}"

# ---- 系统 ----
export TIMEZONE="${TIMEZONE:-Asia/Shanghai}"
export USER_NAME="${USER_NAME:-debian}"
export USER_PASSWORD="${USER_PASSWORD:-}"
export SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-yes}"
export GRUB_ID="${GRUB_ID:-debian}"
export SWAP_MODE="${SWAP_MODE:-auto}"

# ---- 组件开关 ----
export WITH_DOCKER="${WITH_DOCKER:-0}"
export WITH_OPS="${WITH_OPS:-1}"
export WITH_QGA="${WITH_QGA:-1}"
export WITH_FIRMWARE="${WITH_FIRMWARE:-0}"
export DNS_ADDRS="${DNS_ADDRS-223.5.5.5 119.29.29.29}"

# ---- 容器构建 ----
export DOCKER_IMAGE="${DOCKER_IMAGE:-debian:13}"

# ---- 归一化 ----
export WITH_DOCKER="$(_as_bool "$WITH_DOCKER")"
export WITH_OPS="$(_as_bool "$WITH_OPS")"
export WITH_QGA="$(_as_bool "$WITH_QGA")"
export WITH_FIRMWARE="$(_as_bool "$WITH_FIRMWARE")"
export QCOW2_COMPRESS="$(_as_bool "$QCOW2_COMPRESS")"
export MIRROR_AUTO="$(_as_bool "$MIRROR_AUTO")"
'''
write('conf.sh', CONF)

# ============ 3. Debian 的包清单 ============
PKGS = r'''# ============================================================
# 核心包清单（Debian 服务器向，必装）
#   运维常用工具在 packages-ops.list（WITH_OPS=0 可去掉）
#   黑名单在 packages.remove（误入会被 purge）
#
# 这里刻意不含：
#   - 任何业务软件（nginx / apache2 / php / mariadb / postgresql）
#   - nodejs / npm / docker / linux-firmware
# ============================================================

# ---- init / 基础 ----
systemd
systemd-sysv
udev
dbus
kmod
procps
psmisc
util-linux
e2fsprogs
dosfstools

# ---- 网络 / 下载（curl、wget 必须预装）----
iptables
iproute2
iputils-ping
curl
wget
ca-certificates
gnupg

# ---- 账户 / 区域 / 日志 ----
sudo
locales
tzdata
less
logrotate

# ---- 远程 / 初始化 ----
openssh-server
cloud-init
cloud-guest-utils
# 时间同步与 DNS：Debian 的 timesyncd / resolved 都是独立包，不装就没有对应服务
systemd-timesyncd
systemd-resolved

# ---- 启动链 ----
grub-common
grub2-common
grub-efi-amd64-bin
grub-pc
grub-pc-bin
initramfs-tools
linux-image-amd64
'''
write('packages.list', PKGS)

README = '''# distros/debian —— Debian 服务器镜像构建套件

与 `distros/ubuntu` 同构：同一套 `mmdebstrap` 管线、同一份优化（BBR、limits、timesyncd、
首启自动选源、按内存分档 swap）。差异只在发行版本身：源（deb.debian.org / aliyun debian）、
组件（main + contrib + non-free-firmware）、keyring（debian-archive-keyring）、内核元包（linux-image-amd64）。

## 构建

```bash
# 本机（root + mmdebstrap）
sudo SUITE=trixie ./build.sh
sudo SUITE=bookworm ./build.sh

# 只有 docker
SUITE=trixie ./build.sh
```

产物：`out/debian-13-server-snapfree-amd64.qcow2`（trixie）或 `debian-12-...`（bookworm）。

## 参数

见 `conf.sh`，全部可用环境变量覆盖：`SUITE` `MIRROR` `GUEST_MIRROR` `GUEST_MIRROR_CN`
`IMG_SIZE` `WITH_DOCKER` `WITH_OPS` `WITH_QGA` `WITH_FIRMWARE` `SWAP_MODE` `TIMEZONE`。

## 与 ubuntu 套件的共同点

`files/` 下的 sysctl、limits、timesyncd、sf-firstboot、sf-mirror-auto 与 ubuntu 套件保持一致，
改动其中一侧时另一侧也要同步。
'''
write('README.md', README)

# ============ 4. 源 / 组件 / keyring 替换 ============
H = 'hooks/10-prepare.sh'
sub(H, '/usr/share/keyrings/ubuntu-archive-keyring.gpg', '/usr/share/keyrings/debian-archive-keyring.gpg')
sub(H, 'ubuntu-archive-keyring.gpg', 'debian-archive-keyring.gpg')
sub(H, 'ubuntu.sources', 'debian.sources')
sub(H, 'Components: main universe', 'Components: main contrib non-free-firmware')
sub(H, 'https://mirrors.aliyun.com/ubuntu', 'https://mirrors.aliyun.com/debian')
sub(H, 'http://archive.ubuntu.com/ubuntu', 'http://deb.debian.org/debian')
sub(H, 'download.docker.com/linux/ubuntu', 'download.docker.com/linux/debian')
sub(H, 'systemd-networkd systemd-timesyncd', 'systemd-networkd systemd-resolved systemd-timesyncd', must=False)

R = 'scripts/10-rootfs.sh'
sub(R, '--components=main,universe', '--components=main,contrib,non-free-firmware')
sub(R, 'main universe', 'main contrib non-free-firmware')

I2 = 'scripts/20-image.sh'
sub(I2, '-L ubuntu-root', '-L debian-root')
sub(I2, 'UEFI: ubuntu', 'UEFI: debian')

B = 'build.sh'
sub(B, 'ubuntu-keyring kmod', 'debian-archive-keyring kmod')
sub(B, 'ubuntu:26.04 特权容器', 'debian:13 特权容器')
sub(B, 'Ubuntu 26.04 LTS 无 snap 服务器镜像', 'Debian 13/12 无 snap 服务器镜像', must=False)

S = 'files/usr/local/bin/sf-mirror-auto'
sub(S, 'https://mirrors.aliyun.com/ubuntu', 'https://mirrors.aliyun.com/debian', must=False)
sub(S, 'http://archive.ubuntu.com/ubuntu', 'http://deb.debian.org/debian', must=False)

if (db / 'files/etc/default/grub').exists():
    sub('files/etc/default/grub', 'Ubuntu', 'Debian', must=False)

p = db / 'files/etc/apt/preferences.d/nosnap.pref'
if p.exists():
    p.unlink()
    print('  removed', p)

write('files/etc/cloud/cloud.cfg.d/99-network.cfg', '# 网络交给 systemd-networkd 统一管理，避免 cloud-init 改配置\nnetwork:\n  config: disabled\n')

# ============ 5. 安装器补丁 ============
rp = root / 'installer/reinstall.sh'
t = rp.read_text()

OLD_MENU = 'set -- --img "$sf_sel_img" -- "$sf_sel_distro" "$sf_sel_release"'
NEW_MENU = 'set -- --img "$sf_sel_img" --ci -- "$sf_sel_distro" "$sf_sel_release"'
if OLD_MENU in t:
    t = t.replace(OLD_MENU, NEW_MENU)
    print('  patched menu injection (+ --ci)')
elif NEW_MENU not in t:
    print('[!] 菜单注入锚点缺失')
    sys.exit(1)

ANCHOR = '''        if is_use_cloud_image; then
            # cloud image
            if [ -z "$img" ]; then
                # https://salsa.debian.org/cloud-team/debian-cloud-images'''
INJECT = '''        if is_use_cloud_image; then
            # [snapfree] 只允许仓库 catalog 内的镜像
            if [ -z "$img" ]; then
                img=$(sf_lookup_img debian "$releasever")
            fi
            if [ -z "$img" ]; then
                error_and_exit "仓库中没有 debian $releasever 的镜像。\\n运行 $reinstall_____ 查看镜像菜单。"
            fi
            # cloud image
            if false; then
                # https://salsa.debian.org/cloud-team/debian-cloud-images'''
if ANCHOR in t:
    t = t.replace(ANCHOR, INJECT, 1)
    print('  patched setos_debian（catalog 校验 + 封死官方回落）')
elif 'sf_lookup_img debian' not in t:
    print('[!] debian cloud image 锚点缺失')
    sys.exit(1)

rp.write_text(t)

print('done')
