#!/usr/bin/env python3
# 1) 安装器：镜像站从「按顺序第一个可用」改成「测速取最快」
# 2) README 重写为普通用户向；构建/CI 细节移到 docs/BUILD.md
import pathlib
import re

# ---------- 1. installer/reinstall.sh ----------
P = pathlib.Path('installer/reinstall.sh')
t = P.read_text()

NEWBLOCK = '''# 测速：拉 1MB 区间，返回字节/秒；拿不到或是错误页就失败
# 很多代理会用 200 + text/html 返回错误页，所以要校验 content-type 与大小
sf_mirror_speed() {
    local _o _code _size _spd _ct
    _o=$(curl -sSL -o /dev/null --max-time 10 --connect-timeout 5 \\
        -r 0-1048575 --max-filesize 4194304 \\
        -w '%{http_code} %{size_download} %{speed_download} %{content_type}' "$1" 2>/dev/null) || return 1
    _code=${_o%%%% *}
    _o=${_o#* }
    _size=${_o%%%% *}
    _o=${_o#* }
    _spd=${_o%%%% *}
    _ct=${_o#* }
    case "$_code" in 200 | 206) ;; *) return 1 ;; esac
    case "$_ct" in *text/html*) return 1 ;; esac
    [ "$_size" -ge 65536 ] 2>/dev/null || return 1
    printf '%.0f\\n' "$_spd"
}

sf_accel_is_cn() {
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
}

# 逐个镜像站测速，输出最快的那一个（全不通则无输出）
sf_pick_mirror() {
    local _u=$1 _m _spd _best= _bestspd=0
    for _m in $(sf_mirrors); do
        _spd=$(sf_mirror_speed "$_m/$_u") || continue
        echo "mirror: $_m ${_spd} B/s" >&2
        if [ "$_spd" -gt "$_bestspd" ] 2>/dev/null; then
            _bestspd=$_spd
            _best=$_m
        fi
    done
    [ -n "$_best" ] && printf '%s' "$_best"
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

    # 同一趟安装只选一次站，后面直接复用；直连也是
    if [ -n "${_sf_mirror:-}" ]; then
        printf '%s/%s' "$_sf_mirror" "$_u"
        return 0
    fi
    if [ -n "${_sf_direct:-}" ]; then
        printf '%s' "$_u"
        return 0
    fi

    # 海外机器：GitHub 直连通就不加速
    if ! sf_accel_is_cn && curl -fsSLI -o /dev/null --max-time 8 --connect-timeout 5 https://github.com/ >/dev/null 2>&1; then
        _sf_direct=1
        printf '%s' "$_u"
        return 0
    fi

    _m=$(sf_pick_mirror "$_u")
    if [ -n "$_m" ]; then
        _sf_mirror=$_m
        echo "mirror: 选中最快站点 $_m" >&2
        printf '%s/%s' "$_m" "$_u"
        return 0
    fi
    echo "mirror: 所有镜像站均不可用，回落到 GitHub 直连" >&2
    _sf_direct=1
    printf '%s' "$_u"
}

'''

if 'sf_pick_mirror()' in t:
    print('installer: 已有测速逻辑，跳过')
else:
    start = t.index('# 探测镜像站是否能拿到目标文件')
    end = t.index('sf_lookup_img() {')
    t = t[:start] + NEWBLOCK + t[end:]
    P.write_text(t)
    print('installer: 已改成测速取最快')

# ---------- 2. README 重写（面向普通用户） ----------
pathlib.Path('README.md').write_text('''# snapfree-os

一个给 **VPS / 云服务器 / KVM 虚拟机** 用的重装系统工具。

特点一句话说完：系统里不塞垃圾（没有 snap、没有 Docker、没有 nodejs），装完就是干净的服务器，但你常用的优化（BBR 加速、swap、国内软件源、对时）都已经配好。

只能装在 **KVM / 云主机 / VPS** 上，不支持 OpenVZ/LXC，也不能装在物理机上。

## 能装哪些系统

| 系统 | 版本 | 下载大小 |
|---|---|---|
| Ubuntu | 26.04 LTS / 24.04 LTS | 1.2G / 1.1G |
| Debian | 13 (trixie) / 12 (bookworm) | 350M / 380M |

四套都是 64 位 x86_64。系统都是从零构建的纯净版，优化配置四套完全一致。

## 怎么装

用 root 登录你的服务器（SSH 或服务商网页控制台都行），把下面这一整行复制粘贴进去，回车：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
```

> 如果这一步卡住或报错（国内访问 GitHub 经常很慢），换成这条走加速的：
>
> ```bash
> bash <(curl -fsSL https://mirror-one.losn.cc/https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
> ```

然后会出现一个菜单，用数字选你要装的系统：

```text
***** 可选镜像 *****
   1) ubuntu  26.04   server  1.2G  Ubuntu 26.04 LTS 无 snap 服务器镜像
   2) ubuntu  24.04   server  1.1G  Ubuntu 24.04 LTS 无 snap 服务器镜像
   3) debian  13      server  350M  Debian 13 (trixie) 纯净服务器镜像
   4) debian  12      server  380M  Debian 12 (bookworm) 纯净服务器镜像
   0) 退出
```

菜单里**只能选仓库里有的镜像**，选完就会自动下载、写入磁盘、重启进新系统。整个过程中途会断一次 SSH，属正常。

### 建议顺便设置的东西

- **密码**：安装时会问。不想设密码就设置 SSH 密钥（更安全，推荐）
- **主机名、DNS、时区**：安装器都会问，一路回车用默认也可以

不想用菜单也可以直接指定（同样只认仓库里的镜像）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh) \
  debian 13 --username debian --password '你的密码'
```

## 装完怎么用

1. 等机器重启（一般 1～3 分钟）
2. 用你设的密码或密钥 SSH 登录
3. 默认用户：Ubuntu 镜像叫 `ubuntu`，Debian 镜像叫 `debian`，`sudo` 不用输密码

```bash
ssh ubuntu@你的服务器IP     # 装的是 Ubuntu
ssh debian@你的服务器IP     # 装的是 Debian
```

系统默认**没有预置密码**，所以安装时如果既没填密码也没加密钥，是登录不进去的——重装一次并设好密码即可。

## 装完就已经有的东西

不用你动手，下面这些开箱就是好的：

- **BBR 拥塞控制 + fq**：网络提速的标配，`sysctl net.ipv4.tcp_congestion_control` 能看到 `bbr`
- **swap 自动分档**：按内存大小自动建（1G 内存建 2G，4G 内存建 4G，16G 以上不建），开机自动挂载
- **国内软件源**：开机时自动判断机器在国内还是国外，国内的自动换成国内源
- **自动对时**：`systemd-timesyncd` + 国内 NTP，时区 `Asia/Shanghai`
- **文件句柄、连接数上限**：按服务器场景调过，不会动辄报 `too many open files`
- **qemu-guest-agent**：云平台能看到虚拟机 IP 和状态
- 常用工具：`curl wget git vim tmux htop rsync jq`

## 系统里没有的东西

按需求刻意没装，想要自己装：

| 没有 | 怎么装 |
|---|---|
| snap / snapd | Ubuntu 镜像本来就不带，也不要装 |
| Docker | `curl -fsSL https://get.docker.com \\| sh` |
| nodejs / npm | 用 nvm，或 `apt install nodejs npm` |
| nginx / mysql / php | 自己 `apt install` |
| linux-firmware | 虚拟机用不到；装物理机才需要 |

## 关于下载速度

安装器下载镜像时会**自动测速**：国内机器会把几个加速站各试一下（各拉 1MB 计时），挑最快那个下载；海外机器能直连 GitHub 就直连，直连不通才走加速站。四个加速站全挂时回落 GitHub 原地址，不会卡住。

下载到的文件和官方发布的是同一个文件，校验值一致。

## 常见问题

**装完 ping 不通 / SSH 连不上？**
先确认机器真的重启完成（云控制台看状态），再确认安装时设了密码或加了 SSH 密钥。想临时用 ping 排查，可以登录后在控制台里 `systemctl status ssh` 看 ssh 是否在跑。

**想换软件源？**
装完就有 `apt-mirror` 命令：

```bash
apt-mirror            # 看当前用的是哪个源
apt-mirror auto       # 按所在地自动选
apt-mirror aliyun     # 也可以指定：tuna / ustc / huawei / official
```

**时间不对？**
镜像首启已经设好时区和自动对时；如果还不对，`timedatectl status` 看一下，`systemctl restart systemd-timesyncd` 重来一次。

**安装中途 SSH 断了？**
正常，安装器要往磁盘写系统，会重启。等几分钟重新连。

**能不能装别的系统（Arch / Alpine / CentOS）？**
目前只做 Ubuntu 和 Debian。加新系统的方式见 [`docs/BUILD.md`](docs/BUILD.md)。

## 装完之后自检

不确定装得对不对，跑这个（不会改任何东西，只检查）：

```bash
curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/tools/snapfree-check.sh | sudo bash
```

它会检查：系统版本、BBR 是否生效、swap 是否挂上、软件源是否为国内源、SSH 是否在跑、时区对不对、各项内核参数、有没有混进 snap/docker。

## 想自己做镜像 / 改配置

构建方式、CI、怎么加一个新发行版，全部在 [`docs/BUILD.md`](docs/BUILD.md)。

## 声明

安装器改造自 [bin456789/reinstall](https://github.com/bin456789/reinstall)（GPL-3.0，见 `installer/LICENSE`）：菜单换成只选本仓库镜像，下载走测速选站，其余安装流程与上游一致。
''')
print('README.md: 已重写')

# ---------- 3. docs/BUILD.md ----------
b = pathlib.Path('docs')
b.mkdir(exist_ok=True)
(b / 'BUILD.md').write_text('''# 构建与维护

面向要自己造镜像 / 改配置的人。普通用户看 [`../README.md`](../README.md) 就够了。

## 仓库结构

```
catalog/catalog.tsv        镜像清单（安装菜单与安装器只认这里）
installer/reinstall.sh     改造版安装器（菜单 + catalog 校验 + 下载测速选站）
installer/trans.sh         上游安装核心，未改
installer/MIRRORS.md       下载加速规则
installer/LICENSE          GPL-3.0
distros/ubuntu/            Ubuntu 26.04 / 24.04 构建套件
distros/debian/            Debian 13 / 12 构建套件
tools/snapfree-check.sh    装机后自检
docs/                      本文件
.github/workflows/         image-build（矩阵构建）/ installer-contract（契约测试）
```

## 本地构建

```bash
# Ubuntu 26.04 / 24.04
cd distros/ubuntu && bash ./build.sh              # 默认 resolute（26.04）
cd distros/ubuntu && SUITE=noble bash ./build.sh  # 24.04

# Debian 13 / 12
cd distros/debian && SUITE=trixie bash ./build.sh   # 13
cd distros/debian && SUITE=bookworm bash ./build.sh # 12
```

依赖 `mmdebstrap / qemu-img / parted / dosfstools / e2fsprogs`；不是 root 或没有 mmdebstrap 会自动进容器构建（只需 docker）。常用开关：`WITH_OPS` `WITH_QGA` `WITH_DOCKER` `WITH_FIRMWARE` `SWAP_MODE` `IMG_SIZE` `MIRROR` `GUEST_MIRROR_CN`。

## 四套共用优化（`distros/*/files/**`）

- `etc/sysctl.d/99-server.conf`：BBR+fq、`somaxconn 4096`、`netdev_max_backlog 16384`、`tcp_max_syn_backlog 8192`、`tcp_fastopen 3`、`tcp_tw_reuse`、端口 1024-65535、`mtu_probing`、16MiB 收发缓冲、`ip_forward`、`swappiness 10`、`vfs_cache_pressure 50`、dirty 20/10、`fs.file-max 2097152`、`fs.nr_open 1048576`、inotify 524288/1024
- `etc/security/limits.d/99-server.conf`：`*` 与 `root` 各四行，nofile 65536/524288、nproc 65536
- `etc/systemd/system.conf.d/99-limits.conf`、`etc/systemd/timesyncd.conf`（阿里/腾讯 NTP）
- `usr/local/bin/sf-firstboot`：读 `/etc/sf-image.conf`，设时区 + 启 timesyncd → `sf-mirror-auto` 选源 → 按内存分档建 swap（<1G ×2、1–2G 2G、2–4G 等内存、4–16G 4G、≥16G 不建；512M–8G 夹取）→ 写 `/var/lib/sf-firstboot.done` 并自我禁用
- `usr/local/bin/sf-mirror-auto`、`usr/local/bin/apt-mirror`（自动识别 `ubuntu.sources` / `debian.sources`）

构建期 hook 会断言：无 snapd/`/snap`、源文件有 `URIs:`、`sf-firstboot.service` 存在、`99-limits.conf` 存在、首启脚本可执行、`tcp_congestion_control = bbr`。任一项不满足即中断构建。

## CI

`.github/workflows/image-build.yml` 是 4 套矩阵（`ubuntu-26.04` / `ubuntu-24.04` / `debian-13` / `debian-12`）：

1. `bash -n` 语法检查
2. mmdebstrap 构 rootfs → 组 GPT 盘 → GRUB 双启动 → qcow2
3. **真启动冒烟**：QEMU + OVMF 在 TCG 下开机，串口看到 cloud-init/login 才算过
4. commit message 含 `[publish]` 才把产物发布到 `image-latest` Release

`installer-contract.yml` 校验安装器：菜单渲染、`catalog` 字段完整、每个 URL HEAD 200、`reinstall.sh` / `trans.sh` 版本号一致。

## catalog 字段

```text
id|distro|release|arch|variant|name|size|url|sha256
```

`catalog/catalog.tsv` 是唯一真源：菜单列什么、安装器下载什么，都从这来。清单里没有的版本，安装器直接报错，不会回落到官方 cloud image。

## 加一个发行版

1. 复制 `distros/debian` 成 `distros/<os>`
2. 改 `conf.sh`：`SUITE` / `MIRROR` / `IMAGE_NAME` / `KEYRING_PKG` / `SECURITY_MIRROR` / `DOCKER_IMAGE` / `USER_NAME` / `GRUB_ID`
3. 改 `packages.list`（内核元包名）、`hooks/10-prepare.sh` 里的源文件名与 keyring 路径
4. `catalog/catalog.tsv` 加一行
5. `image-build.yml` 的 matrix 加一条
6. 注意：Debian 系 keyring 必须用 `--setup-hook` 拷进 `trusted.gpg.d`（`--keyring` / `Dir::Etc::Trusted` 在 mmdebstrap 上都无效）；Debian 安全源必须是独立的 `security.debian.org/debian-security`，不能在 `deb.debian.org` 后面拼 `-security`
''')
print('docs/BUILD.md: 已写入')

# ---------- 4. 清理一次性脚手架 ----------
for p in [
    'tools/speed-pick.py', 'tools/speed.flag',
    '.github/workflows/speed-pick.yml',
]:
    f = pathlib.Path(p)
    if f.exists():
        f.unlink()
        print('rm', p)
