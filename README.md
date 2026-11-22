# snapfree-os

[![Release](https://img.shields.io/github/v/release/Asunano/snapfree-os?style=flat-square&label=image-latest)](https://github.com/Asunano/snapfree-os/releases/latest)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square)](installer/LICENSE)
[![image-build](https://img.shields.io/github/actions/workflow/status/Asunano/snapfree-os/image-build.yml?style=flat-square&label=image-build)](https://github.com/Asunano/snapfree-os/actions/workflows/image-build.yml)

自建纯净服务器镜像 + 魔改版 reinstall 安装器。安装器 fork 自 [bin456789/reinstall](https://github.com/bin456789/reinstall)，安装核心逻辑保持上游实现，仅替换镜像来源与菜单。

## 介绍

- 四套自建镜像，基于官方源从零构建，非官方 cloud image 的二次加工：Ubuntu 26.04 LTS / 24.04 LTS、Debian 13 (trixie) / 12 (bookworm)
- 镜像不含 snap/snapd、Docker、nodejs/npm、nginx/数据库、linux-firmware；需要的组件由使用者自行安装
- 四套镜像套件独立（各自的源、组件、keyring、内核包名），优化基线完全一致
- 默认用户为 `root`，镜像内不预置任何密码，登录凭据由安装时下发
- 安装器菜单只列 `catalog/catalog.tsv` 中的镜像；清单外的版本直接报错，不会回落到官方 cloud image
- 镜像下载按实测带宽选站：国内机器走加速站，海外机器优先 GitHub 直连
- 每套镜像发布前均经 QEMU + OVMF 真启动冒烟，串口出现 cloud-init / login 才允许发布

## 快速开始

- [支持范围](#支持范围)
- [系统要求](#系统要求)
- [获取安装器](#获取安装器)
- [交互安装](#交互安装)
- [非交互安装与参数](#非交互安装与参数)
- [自动更新与发布](#自动更新与发布)
- [镜像清单](#镜像清单)
- [镜像内容](#镜像内容)
- [优化基线](#优化基线)
- [首次启动行为](#首次启动行为)
- [镜像下载加速](#镜像下载加速)
- [更换软件源](#更换软件源)
- [装机后自检](#装机后自检)
- [故障排查](#故障排查)
- [自己构建镜像](#自己构建镜像)

## 支持范围

| 项 | 支持情况 |
|---|---|
| KVM / 云主机 / VPS | 支持 |
| Hyper-V / VMware / Xen HVM | 支持（需自行确认网卡与引导兼容） |
| OpenVZ / LXC | 不支持（无独立内核，无法引导） |
| 物理机 / 独立服务器 | 不支持（镜像不含 linux-firmware） |

> [!WARNING]
> 安装过程会清空目标磁盘**全部分区**。执行前请确认机器上没有需要保留的数据，并确保拥有服务商控制台（VNC/串行）的救援入口。

> [!NOTE]
> 安装器保留上游的 `windows`、`alpine`、`dd`、`redhat` 等入口，但本项目只为上表四套镜像提供支持与验证，其余入口行为以上游为准。

## 系统要求

| 项 | 要求 |
|---|---|
| CPU | x86_64，支持 BIOS 或 UEFI 引导 |
| 内存 | ≥ 512 MB，推荐 ≥ 1 GB |
| 硬盘 | ≥ 12 GB（镜像虚拟盘为 10 GB ext4 + 256 MiB ESP） |
| 网络 | IPv4 或 IPv6，能访问 GitHub 或加速站 |
| 现有系统 | 任意 Linux（脚本以 root 运行） |

## 获取安装器

海外服务器：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
```

国内服务器（走加速站）：

```bash
bash <(curl -fsSL https://mirror-one.losn.cc/https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
```

## 交互安装

不带参数运行会读取 `catalog/catalog.tsv` 渲染菜单：

```text
***** 可选镜像 *****
   1) ubuntu  26.04   server  1.2G  Ubuntu 26.04 LTS 无 snap 服务器镜像
   2) ubuntu  24.04   server  1.1G  Ubuntu 24.04 LTS 无 snap 服务器镜像
   3) debian  13      server  365M  Debian 13 (trixie) 纯净服务器镜像
   4) debian  12      server  410M  Debian 12 (bookworm) 纯净服务器镜像
   0) 退出
```

选择编号后需二次确认。确认后依次执行：下载镜像 → 写入目标盘 → 安装引导 → 重启进新系统。

安装过程中 SSH 会中断一次，属预期行为；进度可通过服务商 VNC 控制台或串行控制台观察。

## 非交互安装与参数

```bash
bash reinstall.sh debian 13 --username root --password 'PASSWORD'
bash reinstall.sh ubuntu 24.04 --ssh-key 'ssh-ed25519 AAAA... user@host'
```

参数沿用上游定义，与本项目相关的部分：

| 参数 | 说明 |
|---|---|
| `--username USERNAME` | 新系统用户名，默认 `root` |
| `--password PASSWORD` | 新系统密码，留空则该账户无密码 |
| `--ssh-key KEY` | 写入 `authorized_keys` 的 SSH 公钥；与 `--password` 可同时使用，也可只用其一 |
| `--ssh-port PORT` | 修改 SSH 端口 |
| `--web-port PORT` | 修改安装期间日志页端口 |
| `--hold 1` | 仅重启到安装环境，不执行安装，用于验证网络连通性 |
| `--hold 2` | 安装完成后不重启，用于进入目标系统修正配置 |
| `--img URL` | 指定自定义镜像，跳过 catalog 校验 |

> [!IMPORTANT]
> `--password` 与 `--ssh-key` 至少提供一项。两者皆空时新系统没有任何登录凭据，SSH 无法登录。

> [!NOTE]
> 通过 `--img` 指定的链接不参与镜像加速改写，直连原始地址。

## 自动更新与发布

| 对象 | 频率 | 行为 |
|---|---|---|
| 镜像 | 每天 01:00 后随机开始（随机延迟 0–60 分钟） | 从官方源重建四套镜像 → 冒烟启动 → 发布 |
| 安装核心 `trans.sh` | 每天 04:00 后随机开始 | 拉取上游同名文件，锚点兼容性校验通过后覆盖并提交 |
| 魔改安装器 `reinstall.sh` | 仅提醒 | 上游有变更时开 issue，不自动合并 |

发布标签：每套镜像一个独立 tag（当前为 `ubuntu-26.04`、`ubuntu-24.04`、`debian-13`、`debian-12`），另有一个汇总 tag `image-latest`，内含全部镜像。

```text
https://github.com/Asunano/snapfree-os/releases/download/ubuntu-26.04/ubuntu-26.04-server-snapfree-amd64.qcow2
https://github.com/Asunano/snapfree-os/releases/download/debian-13/debian-13-server-snapfree-amd64.qcow2
https://github.com/Asunano/snapfree-os/releases/latest/download/debian-13-server-snapfree-amd64.qcow2   # 汇总，兼容旧链接
```

`catalog/catalog.tsv` 中的 `size` 会在发布后自动回写，`url` 保持指向 `image-latest`，所以旧链接不会失效。

手动发布：在 Actions 里手动跑 `image-build` 会直接发布；或推入 commit 并在 message 里带 `[publish]`。

## 镜像清单

`catalog/catalog.tsv` 是唯一真源，为安装器菜单与下载地址的唯一来源。

| ID | 系统 | 版本 | 体积 | 虚拟盘 |
|---|---|---|---|---|
| `ubuntu-26.04-server-snapfree` | Ubuntu | 26.04 LTS (resolute) | 1.2G | 10G |
| `ubuntu-24.04-server-snapfree` | Ubuntu | 24.04 LTS (noble) | 1.1G | 10G |
| `debian-13-server-snapfree` | Debian | 13 (trixie) | 365M | 10G |
| `debian-12-server-snapfree` | Debian | 12 (bookworm) | 410M | 10G |

单条记录字段：`id|distro|release|arch|variant|name|size|url|sha256`。镜像与对应 `.sha256` 均发布在 Release `image-latest`。

## 镜像内容

已预装：

| 分组 | 内容 |
|---|---|
| 基础 | `systemd`、`udev`、`kmod`、`util-linux`、`e2fsprogs`、`dosfstools` |
| 网络 | `systemd-networkd`、`systemd-resolved`、`iptables`、`iproute2`、`iputils-ping`、`curl`、`wget`、`ca-certificates`、`gnupg` |
| 远程 | `openssh-server`、`cloud-init`（NoCloud / ConfigDrive）、`qemu-guest-agent` |
| 引导 | GRUB（BIOS + UEFI 双启动）、`initramfs-tools` |
| 运维 | `nano`、`vim-tiny`、`bash-completion`、`man-db`、`git`、`tmux`、`rsync`、`jq` |
| 网络诊断 | `mtr-tiny`、`traceroute`、`bind9-dnsutils`、`whois`、`tcpdump`、`iftop`、`nmap`、`socat`、`net-tools`、`lsof`、`ethtool`、`netcat-openbsd` |
| 观测排错 | `htop`、`sysstat`、`strace`、`ncdu`、`tree`、`file`、`bc`、`time`、`pv` |
| 磁盘 | `parted`、`gdisk`、`pciutils` |
| 压缩 | `zip`、`unzip`、`xz-utils`、`bzip2`、`zstd`、`pigz`、`lz4` |

刻意不含：

| 组件 | 说明 |
|---|---|
| snap / snapd | Ubuntu 镜像不带，构建期有断言阻止误入 |
| Docker | `WITH_DOCKER=1` 构建时才装；装好可用官方脚本安装 |
| nodejs / npm | 需自行 `apt install` 或使用 nvm |
| nginx / apache / php / 数据库 | 构建期黑名单，误入会 purge |
| linux-firmware | `WITH_FIRMWARE=1` 构建时才装，虚拟机无需 |
| cron / fail2ban / ufw | 未预装，避免默认常驻服务与防火墙拦截 |

`WITH_OPS=0` 可整体去掉运维工具层（约减少 70MB）。

## 优化基线

四套镜像使用同一份配置，逐项如下：

| 类别 | 配置 |
|---|---|
| 拥塞控制 | `net.ipv4.tcp_congestion_control=bbr`，`default_qdisc=fq` |
| 连接队列 | `somaxconn=4096`、`netdev_max_backlog=16384`、`tcp_max_syn_backlog=8192` |
| 端口与复用 | `ip_local_port_range=1024 65535`、`tcp_tw_reuse=1`、`tcp_max_tw_buckets=262144` |
| 缓冲 | `tcp_rmem`/`tcp_wmem` 上限 16MiB、`tcp_notsent_lowat=131072`、`tcp_mtu_probing=1` |
| 内存与磁盘 | `vm.swappiness=10`、`vm.vfs_cache_pressure=50`、`dirty_ratio=20`、`dirty_background_ratio=10` |
| 句柄与进程 | `fs.file-max=2097152`、`fs.nr_open=1048576`、`nofile 65536/524288`（`*` 与 `root`）、`nproc=65536` |
| inotify | `max_user_watches=524288`、`max_user_instances=1024` |
| 时间同步 | `systemd-timesyncd` + 国内 NTP，时区 `Asia/Shanghai` |
| 后台任务 | `apt-daily`、`apt-daily-upgrade`、`motd-news` 定时器禁用并 mask |

构建期断言（任一不满足即中断构建）：无 snapd 与 `/snap`；`ubuntu.sources` / `debian.sources` 存在且含 `URIs:`；`sf-firstboot.service` 与 `99-limits.conf` 存在；首启脚本可执行；`tcp_congestion_control = bbr`。

## 首次启动行为

`sf-firstboot.service` 为一次性单元，读取 `/etc/sf-image.conf`，依次执行：

1. 设置时区并启用 `systemd-timesyncd`
2. 调用 `sf-mirror-auto`，按出口 IP 所在地区选择软件源（国内 → 国内镜像源，其它 → 官方源），日志 `/var/log/sf-mirror.log`
3. 按内存容量建立 swap 并写入 `/etc/fstab`：`<1G` → 2 倍内存；`1–2G` → 2G；`2–4G` → 等于内存；`4–16G` → 4G；`≥16G` → 不建；结果限制在 512M–8G 区间

执行完成后写入 `/var/lib/sf-firstboot.done` 并自我禁用。

## 镜像下载加速

镜像下载地址按可用带宽动态选择，规则：

- 国内机器：对全部候选站逐个测速，取最快者
- 海外机器：先探测 GitHub 直连，可用则直连；不可用再测速选站
- 全部不可用：回落 GitHub 原始地址

地区判定多级兜底，命中任一即视为国内：`_loc` → `api.ip.sb/geoip` → `ipinfo.io/country` → `qualcomm cdn-cgi/trace`。

候选站（顺序仅决定测速先后）：`mirror-one.losn.cc`、`mirror.drxian.qzz.io`、`v4.gh-proxy.org`、`axisnow.gh-proxy.org`。

测速方式与限制：

- 每站拉取 1 MB 区间（`Range: 0-1048575`），`--max-filesize 4MB` 防止不支持 Range 的站点整包传输
- 返回码非 200/206、`content-type` 为 `text/html`、或有效数据不足 64 KB 的候选直接排除
- 单站超时 10 秒，串行执行；选中站结果在当前安装进程内缓存

规则细节见 [`installer/MIRRORS.md`](installer/MIRRORS.md)。

## 更换软件源

镜像内提供 `apt-mirror`：

```bash
apt-mirror            # 查看当前源
apt-mirror auto       # 按出口 IP 自动选择
apt-mirror aliyun     # 可选：tuna / ustc / huawei / official
```

Debian 会把安全源写成独立的 `security.debian.org/debian-security` stanza；Ubuntu 的三类 suite 共用同一 URI。

## 装机后自检

```bash
curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/tools/snapfree-check.sh | sudo bash
```

检查项：发行版与版本、BBR 与实际值、swap 挂载、软件源归属（国内/官方，识别 Ubuntu 与 Debian 两种源文件格式）、SSH 服务状态、时区、内核参数、snap/docker 残留。

## 故障排查

| 现象 | 排查方式 |
|---|---|
| 安装后无法 SSH | 先在服务商 VNC 登录：`systemctl status ssh ssh.socket`；确认安装时提供过 `--password` 或 `--ssh-key` |
| 安装后 ping 不通 | 确认机器已完成重启；`ip a` 确认 `eth0` 已获得地址；`systemctl status systemd-networkd` |
| 确认 BBR 是否生效 | `sysctl net.ipv4.tcp_congestion_control` 应输出 `bbr` |
| 确认 swap 是否建立 | `swapon --show`；`cat /etc/fstab` 中应有对应条目 |
| 时间不正确 | `timedatectl status`；`systemctl restart systemd-timesyncd` |
| 换普通用户 | 重建镜像时 `USER_NAME=ubuntu`，或安装时 `--username ubuntu` |
| 主机名/DNS 不对 | 重装时在安装器提示处填写，或进系统后手工改（`sf-firstboot` 不回改这些项） |

日志位置：安装器 `/trans.sh` 阶段日志在 SSH 会话中输出；首启换源日志 `/var/log/sf-mirror.log`。

## 自己构建镜像

```bash
cd distros/ubuntu && bash ./build.sh              # Ubuntu 26.04（resolute）
cd distros/ubuntu && SUITE=noble bash ./build.sh  # Ubuntu 24.04
cd distros/debian && SUITE=trixie bash ./build.sh   # Debian 13
cd distros/debian && SUITE=bookworm bash ./build.sh # Debian 12
```

依赖 `mmdebstrap`、`qemu-img`、`parted`、`dosfstools`、`e2fsprogs`；非 root 或缺少 mmdebstrap 时自动进入容器构建（需要 Docker）。

构建流程、CI 矩阵、catalog 字段、新增发行版的注意事项见 [`docs/BUILD.md`](docs/BUILD.md)；套件参数与环境变量见 [`distros/README.md`](distros/README.md)。

## 目录结构

```
catalog/catalog.tsv        镜像清单（唯一真源）
installer/reinstall.sh     安装器（菜单、catalog 校验、下载加速）
installer/trans.sh         上游安装核心（未修改）
installer/MIRRORS.md       下载加速规则
installer/LICENSE          GPL-3.0
distros/ubuntu/            Ubuntu 26.04 / 24.04 构建套件
distros/debian/            Debian 13 / 12 构建套件
docs/BUILD.md              构建、CI、扩展说明
tools/snapfree-check.sh    装机后自检脚本
.github/workflows/         image-build（构建矩阵）/ installer-contract（契约校验）
```

## 验证状态

四套镜像在 GitHub Actions 中完成构建，并以 QEMU + OVMF（TCG）实际启动，串口输出出现 cloud-init / login 后方发布至 Release。真实云厂商环境存在网卡命名、引导模式、控制台差异，首次部署建议保留服务商救援入口。

## 致谢与许可

安装器基于 [bin456789/reinstall](https://github.com/bin456789/reinstall) 修改，遵循 GPL-3.0，许可证见 `installer/LICENSE`。镜像构建套件、首启脚本、catalog 与菜单逻辑为本仓库新增。
