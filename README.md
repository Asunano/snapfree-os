# snapfree-os

一个小仓库，同时放两件事：**服务器镜像的构建**（`distros/<os>`）和 **把这些镜像装到机器上的安装器**（fork 自 [bin456789/reinstall](https://github.com/bin456789/reinstall)）。镜像清单 `catalog/catalog.tsv` 是唯一真源，安装菜单只列清单里的条目。

## 可用镜像

| 镜像 | 基线 | 体积 | 下载 |
|---|---|---|---|
| `ubuntu-26.04-server-snapfree` | Ubuntu 26.04 LTS | 1.2G | [qcow2](https://github.com/Asunano/snapfree-os/releases/latest/download/ubuntu-26.04-server-snapfree-amd64.qcow2) |
| `ubuntu-24.04-server-snapfree` | Ubuntu 24.04 LTS | 1.1G | [qcow2](https://github.com/Asunano/snapfree-os/releases/latest/download/ubuntu-24.04-server-snapfree-amd64.qcow2) |
| `debian-13-server-snapfree` | Debian 13 trixie | 350M | [qcow2](https://github.com/Asunano/snapfree-os/releases/latest/download/debian-13-server-snapfree-amd64.qcow2) |
| `debian-12-server-snapfree` | Debian 12 bookworm | 380M | [qcow2](https://github.com/Asunano/snapfree-os/releases/latest/download/debian-12-server-snapfree-amd64.qcow2) |

四套镜像各自独立构建（各自的源、组件、keyring、内核包名），但**优化基线完全一致**（同一份 sysctl / limits / timesyncd / 首启脚本）。

## 一键安装

在要重装的机器上（root，只支持 KVM / 云主机 / VPS）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
```

会出现菜单（只能选仓库内镜像）：

```text
***** 可选镜像 *****
   1) ubuntu  26.04   server  1.2G  Ubuntu 26.04 LTS 无 snap 服务器镜像
   2) ubuntu  24.04   server  1.1G  Ubuntu 24.04 LTS 无 snap 服务器镜像
   3) debian  13      server  350M  Debian 13 (trixie) 纯净服务器镜像
   4) debian  12      server  380M  Debian 12 (bookworm) 纯净服务器镜像
   0) 退出
```

不想要菜单，直接指定（仍然只认仓库镜像，清单里没有的版本直接报错，不会回落到官方 cloud image）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh) \
  ubuntu 24.04 --ssh-key "ssh-ed25519 AAAA... you@host"

bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh) \
  debian 13 --username debian --password 'yourpass'
```

## 镜像下载加速

安装器下载 qcow2 会自动挑更快的地址：**国内机器直接用加速站**（`mirror-one.losn.cc` → `mirror.drxian.qzz.io` → `v4.gh-proxy.org` → `axisnow.gh-proxy.org`，按顺序探测，第一个可用的胜出）；**海外机器先直连 GitHub，只有直连不通才退到加速站**。地区识别依次尝试 `api.ip.sb` → `ipinfo.io` → `qualcomm trace`，任一命中 CN 即算国内。探测会过滤 `text/html` 之类的伪 200 错误页，四站全挂时回落 GitHub 原地址。细节见 [`installer/MIRRORS.md`](installer/MIRRORS.md)。

## 装完之后

- 默认用户：Ubuntu 镜像 `ubuntu`、Debian 镜像 `debian`，`sudo` 免密
- 镜像内 `PasswordAuthentication yes`，但**没有预置密码**：不传 `--password` 就只能用密钥进（建议用 `--ssh-key`）
- 网卡命名固定 `eth0`（`net.ifnames=0 biosdevname=0`），网络由 systemd-networkd 接管，另有一份 DHCP 兜底配置
- cloud-init 只认 NoCloud / ConfigDrive，其他平台开机不会重复跑

## 镜像里有什么

| 项 | 状态 |
|---|---|
| snapd / `/snap` | **无**（Ubuntu 镜像也不带） |
| nodejs / npm | **无**（自己 `apt install` 或 nvm） |
| Docker | **无**（`WITH_DOCKER=1` 才装） |
| nginx / apache / php / 数据库 | **无** |
| linux-firmware | **无**（`WITH_FIRMWARE=1` 才装，物理机才需要） |
| curl / wget / ca-certificates / openssh-server | **有** |
| qemu-guest-agent | **有**（`WITH_QGA=0` 关） |
| git / vim-tiny / htop / tmux / rsync / jq | **有**（`WITH_OPS=0` 关） |
| 启动 | GPT + `bios_grub` + ESP + ext4，UEFI/BIOS 双启动；虚拟盘 10G，qcow2 压缩 |

## 四套镜像共同的优化

- **文件句柄 / 进程**：`fs.file-max 2097152`、`fs.nr_open 1048576`，`nofile 65536/524288`（`*` 和 `root` 各一份，:root 登录不再只有 1024），systemd `DefaultLimitNOFILE=65536:1048576`
- **网络**：BBR + fq、`tcp_mtu_probing=1`、`tcp_tw_reuse`、16MiB 收发缓冲、`somaxconn 4096`、`tcp_max_syn_backlog 8192`、端口范围 1024-65535、IP 转发
- **内存/磁盘**：`swappiness 10`、`vfs_cache_pressure 50`、dirty 20/10、inotify 上限 524288
- **时间**：`systemd-timesyncd` + 阿里/腾讯 NTP + `Asia/Shanghai`（安装器写死的 `Etc/UTC` 会被首启纠正）
- **首启 `sf-firstboot`**（一次性，跑完写 `/var/lib/sf-firstboot.done` 并自我禁用）：
  1. 按 `https://api.ip.sb/geoip` 识别地区：中国大陆→国内镜像源，其他→官方源（日志 `/var/log/sf-mirror.log`）
  2. 按内存分档建 swap（<1G → ×2，1–2G → 2G，2–4G → 等内存，4–16G → 4G，≥16G 不建；带 512M–8G 上下限，写入 `/etc/fstab`）
- 后台自动 apt / motd 广告定时器全部禁用并 mask

## 换源

```bash
apt-mirror                # 看可选源
apt-mirror auto           # 按出口 IP 自动选（国内/海外）
apt-mirror aliyun|tuna|ustc|huawei|official
```

Debian 会自动把安全源写成独立的 `security.debian.org/debian-security` stanza，Ubuntu 则三类 suite 同源。

## 自己构建

```bash
# Ubuntu 26.04 / 24.04
cd distros/ubuntu && bash ./build.sh              # 默认 resolute（26.04）
cd distros/ubuntu && SUITE=noble bash ./build.sh  # 24.04

# Debian 13 / 12
cd distros/debian && SUITE=trixie bash ./build.sh   # 13
cd distros/debian && SUITE=bookworm bash ./build.sh # 12
```

需要 `mmdebstrap / qemu-img / parted / dosfstools / e2fsprogs`；不是 root 或没有 mmdebstrap 会自动进容器构建（只需 docker）。常用开关：`WITH_OPS` `WITH_QGA` `WITH_DOCKER` `WITH_FIRMWARE` `SWAP_MODE` `IMG_SIZE` `MIRROR` `GUEST_MIRROR_CN`。

## CI

`.github/workflows/image-build.yml` 是 4 套矩阵（`ubuntu-26.04` / `ubuntu-24.04` / `debian-13` / `debian-12`）：

1. `bash -n` 语法检查
2. mmdebstrap 构 rootfs → 组 GPT 盘 → GRUB 双启动 → qcow2
3. **真启动冒烟**：QEMU + OVMF 在 TCG 下开机，串口看到 cloud-init/login 才算过
4. commit message 含 `[publish]` 才把产物发布到 `image-latest` Release

`installer-contract.yml` 校验安装器：菜单渲染、`catalog` 字段完整、每个 URL HEAD 200、`reinstall.sh` / `trans.sh` 版本号一致。

## 装机后自检

```bash
curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/tools/snapfree-check.sh | sudo bash
```

## 目录

```
catalog/catalog.tsv        镜像清单（菜单/安装器只认这里）
installer/                 fork 的 reinstall（菜单 + 安装核心，trans.sh 未改）
installer/MIRRORS.md       镜像下载加速规则与开关
distros/ubuntu/            Ubuntu 26.04 / 24.04 构建套件
distros/debian/            Debian 13 / 12 构建套件
tools/snapfree-check.sh    装机后自检
.github/workflows/         image-build（矩阵构建）/ installer-contract（契约测试）
```

## 加一个发行版

复制 `distros/debian` 成 `distros/<os>`，改 `conf.sh`（`SUITE`/`MIRROR`/`IMAGE_NAME`/`KEYRING_PKG`/`SECURITY_MIRROR`）、`packages.list`（内核元包名）、`hooks/10-prepare.sh` 里的源文件名与 keyring 路径，然后在 `catalog/catalog.tsv` 加一行、在 `image-build.yml` 的 matrix 里加一条即可。

## 声明

安装器是 [bin456789/reinstall](https://github.com/bin456789/reinstall) 的改造版（GPL-3.0，见 `installer/LICENSE`）：菜单换成仓库镜像选择，`setos_*` 里加了 catalog 校验，其余安装逻辑与上游一致。
