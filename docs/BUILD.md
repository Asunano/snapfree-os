# 构建与维护

本文件面向需要自行构建镜像、修改构建套件或新增发行版的维护者。安装与使用说明见 [`../README.md`](../README.md)。

## 概览

镜像由 `distros/<distro>/` 下的套件自行构建，不依赖任何官方 cloud image；每个套件输出一个 qcow2 与对应 `.sha256`，由 `catalog/catalog.tsv` 索引，安装器只认该清单。

| 套件 | `SUITE` | 产物 | 默认组件 |
|---|---|---|---|
| `distros/ubuntu` | `resolute`（26.04）、`noble`（24.04） | `ubuntu-<ver>-server-snapfree-amd64.qcow2` | `main universe` |
| `distros/debian` | `trixie`（13）、`bookworm`（12） | `debian-<ver>-server-snapfree-amd64.qcow2` | `main contrib non-free-firmware` |

两套套件结构相同（`conf.sh` / `packages*.list` / `hooks/` / `scripts/` / `files/`），差异仅在源、keyring、内核包名与安全源拼法。四套镜像共用同一套优化基线，**改 `files/**` 时两个套件必须同步修改**，否则四套镜像会不一致。

## 环境依赖

| 依赖 | 用途 |
|---|---|
| `mmdebstrap` | 从官方源构建 rootfs |
| `qemu-img` | 生成 / 压缩 / 校验 qcow2 |
| `parted`、`dosfstools`、`e2fsprogs` | 分区、ESP 格式化、ext4 |
| `util-linux`、`kmod` | loop 设备、模块 |
| root 权限 | loop 设备挂载与 chroot |

缺少上述工具或当前用户非 root 时，`build.sh` 会自动进入容器构建，只需本机有 Docker（容器镜像由 `DOCKER_IMAGE` 指定，Ubuntu 套件默认 `ubuntu:26.04`，Debian 套件默认 `debian:13`）。

## 快速构建

```bash
cd distros/ubuntu && bash ./build.sh                     # Ubuntu 26.04（resolute）
cd distros/ubuntu && SUITE=noble bash ./build.sh          # Ubuntu 24.04
cd distros/debian && SUITE=trixie bash ./build.sh         # Debian 13
cd distros/debian && SUITE=bookworm bash ./build.sh       # Debian 12
```

产物位于 `distros/<distro>/out/`，中间文件在 `work/`。

## 构建参数

全部参数在 `conf.sh` 中以环境变量形式定义，不改文件即可覆盖：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SUITE` | Ubuntu `resolute` / Debian `trixie` | 目标代号，决定版本号与源 |
| `MIRROR` | Ubuntu `archive.ubuntu.com` / Debian `deb.debian.org` | **构建期**从该源拉包 |
| `GUEST_MIRROR` | 同 `MIRROR` | 写入镜像的初始源 |
| `GUEST_MIRROR_CN` | Ubuntu `mirrors.aliyun.com/ubuntu` / Debian `mirrors.ustc.edu.cn/debian` | 首启判定为国内时切到的源 |
| `MIRROR_AUTO` | `1` | 首启是否按出口 IP 自动选源 |
| `ARCH` | `amd64` | 目标架构，当前只提供 x86_64 |
| `IMG_SIZE` | `10G` | 虚拟盘容量 |
| `ESP_SIZE_MIB` | `256` | ESP 大小 |
| `QCOW2_COMPRESS` | `1` | 产物体积压缩 |
| `TIMEZONE` | `Asia/Shanghai` | 镜像时区 |
| `USER_NAME` | `root` | 默认登录用户；改 `ubuntu` / `debian` 可生成普通用户镜像 |
| `USER_PASSWORD` | 空 | 镜像内置密码；留空则由安装时下发的凭据决定 |
| `SSH_PASSWORD_AUTH` | `yes` | sshd 是否允许密码登录 |
| `GRUB_ID` | `ubuntu` / `debian` | GRUB 菜单标识 |
| `SWAP_MODE` | `auto` | `auto` 按内存分档；`none` 不建；数字为固定 MiB |
| `WITH_OPS` | `1` | 运维工具层（`packages-ops.list`），关闭约省 70MB |
| `WITH_QGA` | `1` | 安装 `qemu-guest-agent` |
| `WITH_DOCKER` | `0` | 安装 Docker CE（官方源，不走 snap） |
| `WITH_FIRMWARE` | `0` | 安装 `linux-firmware`，仅物理机需要 |
| `DNS_ADDRS` | `223.5.5.5 119.29.29.29` | 兜底 DNS；置空则沿用 DHCP |
| `SECURITY_MIRROR` | Debian 专用 | 安全源，必须为独立路径 |
| `KEYRING_PKG` | Debian 专用 | 归档 keyring 包名 |
| `OUT_DIR` / `WORK_DIR` | `out/` / `work/` | 产物与中间目录 |

## 构建流水线

`build.sh` 顺序执行：

1. **keyring 准备**：宿主发行版代号与 `SUITE` 不一致时，由 `scripts/fetch-keyring.sh` 拉取目标发行版 keyring
2. **`scripts/10-rootfs.sh`**：`mmdebstrap` 以 `--variant=apt` 构建 rootfs，包清单由 `packages.list` + 可选层拼接，装上后依次执行 `hooks/10-prepare.sh` 与 `hooks/99-cleanup.sh`
3. **`scripts/20-image.sh`**：创建 GPT 虚拟盘并写入 rootfs，安装 BIOS 与 UEFI 双引导 GRUB，转换为 qcow2
4. **`scripts/30-verify.sh`**：`qemu-img info/check`、生成 `.sha256`，并打印本地试启方法

`hooks/10-prepare.sh` 负责系统层配置：静态文件落地、`/etc/sf-image.conf`、主机名与时区、兜底 networkd 配置、写入 `ubuntu.sources` / `debian.sources`、启用/禁用 systemd 单元、用户与密码、sshd 落项、断言校验。

`hooks/99-cleanup.sh` 负责瘦身与去标识：清 apt 缓存与列表、删 ssh host key 与 `machine-id`、清日志与 `cloud-init clean`、删 changelog 与多余语言包（保留 copyright）；结尾二次确认无 snap。

## 磁盘布局

| 分区 | 范围 | 类型 | 标志 |
|---|---|---|---|
| bios-boot | 1–2 MiB | ext4（不挂载） | `bios_grub` |
| ESP | 2–258 MiB | FAT32 | `esp`（挂 `/boot/efi`） |
| root | 258 MiB–100% | ext4 | 挂 `/` |

虚拟盘 10 GB；镜像内不含独立 `/boot` 与 swap 分区，swap 由首启脚本以交换文件形式建立。

## 优化基线落地位置

四套镜像共用，位于 `distros/<distro>/files/`：

| 路径 | 作用 |
|---|---|
| `etc/sysctl.d/99-server.conf` | BBR+fq、连接队列、缓冲、端口范围、内存与 inotify 参数 |
| `etc/security/limits.d/99-server.conf` | `nofile` / `nproc`（`*` 与 `root` 各一份） |
| `etc/systemd/system.conf.d/99-limits.conf` | systemd 默认 `DefaultLimitNOFILE` |
| `etc/systemd/timesyncd.conf` | 国内 NTP |
| `etc/ssh/sshd_config.d/10-image.conf` | `PermitRootLogin`、密码登录、Keepalive |
| `etc/cloud/cloud.cfg.d/99-image.cfg` | datasource 限定 NoCloud/ConfigDrive、默认用户、时区 |
| `etc/systemd/system/sf-firstboot.service` | 首启一次性单元 |
| `usr/local/bin/sf-firstboot` | 时区/对时、选源、swap 分档 |
| `usr/local/bin/sf-mirror-auto` | 按地区选源（三级 IP 识别） |
| `usr/local/bin/apt-mirror` | 手动换源，自动识别 `ubuntu.sources` / `debian.sources` |
| `etc/systemd/network/99-fallback-dhcp.network` | networkd 兜底 DHCP（与 netplan 共存，不重复定义网卡） |

`files/**` 由 `10-prepare.sh` 直接 `cp -a` 到 rootfs 根。

## 构建期断言

以下任一项不满足即中断构建：

- rootfs 无 `snapd`、无 `/snap`
- `ubuntu.sources`（或 `debian.sources`）存在且含 `URIs:`
- `sf-firstboot.service` 与 `99-limits.conf` 存在
- `/usr/local/bin/sf-firstboot` 可执行
- `sysctl net.ipv4.tcp_congestion_control` 为 `bbr`

## CI

### image-build

`.github/workflows/image-build.yml` 为四套矩阵，`fail-fast: false`，并发按 ref 取消旧任务，超时 150 分钟：

| id | distro | suite | 构建源 | 国内源 |
|---|---|---|---|---|
| `ubuntu-26.04` | ubuntu | resolute | `archive.ubuntu.com` | `mirrors.aliyun.com/ubuntu` |
| `ubuntu-24.04` | ubuntu | noble | `archive.ubuntu.com` | `mirrors.aliyun.com/ubuntu` |
| `debian-13` | debian | trixie | `deb.debian.org/debian` | `mirrors.ustc.edu.cn/debian` |
| `debian-12` | debian | bookworm | `deb.debian.org/debian` | `mirrors.ustc.edu.cn/debian` |

步骤：脚本 `bash -n` → 构建 → 校验产物 → **真启动冒烟**（QEMU + OVMF，TCG，不需要 KVM；串口输出命中 `cloud-init` 或 `login:` 才算通过，并顺带确认 GRUB 菜单品牌字段）→ 上传 artifact。

发布：`publish-latest` 任务仅在 `main` 分支且 commit message 包含 `[publish]` 时执行，把四套 qcow2 与 `.sha256` 发布到 Release `image-latest`。日常提交只验证、不发布。

触发条件：`push` 到 `main` 且改动命中 `distros/**` 或本 workflow 文件；`workflow_dispatch`；每日 `0 17 * * *`（UTC，即北京时间 01:00）定时重建。

定时触发时 `gate` 任务会先随机 `sleep 0–3600` 秒，使每日开始时间不固定（上限一小时，避免所有用户与上游同时拉取官方源）。`gate` 只在上报定时事件时延迟，`push` / `workflow_dispatch` 直接开始。

发布条件：`main` 分支且（`schedule` 或 `workflow_dispatch` 或 commit message 含 `[publish]`）。发布时按 artifact 目录名拆出镜像 id，为每个 id 创建一个同名 tag 的 Release（`--latest=false`），随后把所有产物汇总写入 `image-latest` 并将其设为 latest，保证 `releases/latest/download/<file>` 旧链接不变。

发布完成后会按实际产物字节数回写 `catalog/catalog.tsv` 的 `size` 字段并以 `chore(catalog): 同步镜像体积 [skip ci]` 提交；`GITHUB_TOKEN` 提交不会再触发其他 workflow。

### installer-contract

`.github/workflows/installer-contract.yml` 在 `installer/**`、`catalog/**` 变更时运行，目前七项检查：

| 检查 | 内容 |
|---|---|
| 语法 | `bash -n installer/reinstall.sh`、`bash -n installer/trans.sh` |
| 指向本仓库 | `sf_menu`、`sf_lookup_img`、`confhome` 指向本仓库 `main/installer`、`sf_catalog` 指向本仓库清单 |
| 不回落官方镜像 | 保留 `if false; then` 封禁段与「仓库中没有 ubuntu」报错 |
| 版本号一致 | `reinstall.sh` 与 `trans.sh` 的 `SCRIPT_VERSION` 相同 |
| 清单字段 | `id|distro|release|arch|variant|name|size|url|sha256` 必填项非空、URL 合法 |
| 可下载 | 逐条 `curl -sSIL` 得到 200 |
| 菜单渲染 | 伪终端注入 `1` + `y`，断言输出 `GOT=ubuntu,26.04` |

> [!NOTE]
> 本仓库的批量修改通过一次性 workflow 内的脚本完成，这些提交由 `GITHUB_TOKEN` 发起，不会触发其他 workflow。修改 `installer/**` 后需要一次真实 push 才会让契约测试重跑。

### upstream-sync

`.github/workflows/upstream-sync.yml` 每日同步上游安装核心，`workflow_dispatch` 可手动跑：

1. 拉取上游 `trans.sh`、`reinstall.sh`，两者先过 `bash -n`
2. 兼容性门禁：上游 `trans.sh` 必须有 `^SCRIPT_VERSION=`、`^: main`、`cloud_image`；本地 `reinstall.sh` 必须有向 `trans.sh` 注入的锚点语句
3. `trans.sh` sha256 变化时覆盖本地文件，并把 `reinstall.sh` 的 `SCRIPT_VERSION` 改成与上游一致（重装时 `reinstall.sh` 会校验下载到的 `trans.sh` 版本号，两者必须相等），再提交 `[sync] ...`
4. 上游版本号变化时开 issue `上游 reinstall.sh 变更待评估：<version>`，说明不能自动合并的原因与人工步骤；已存在同名 issue 则跳过
5. `installer/.upstream-version` 记录已处理的上游版本，避免重复开 issue

> [!IMPORTANT]
> 只自动同步 `trans.sh`。`reinstall.sh` 含 catalog 菜单、下载加速、`setos_*` 校验等魔改，自动合并会冲突或覆盖这些逻辑，只能按 issue 人工搬。

## 清单字段

`catalog/catalog.tsv` 是唯一真源，注释行以 `#` 开头：

| 字段 | 含义 |
|---|---|
| `id` | 唯一标识 |
| `distro` | `ubuntu` / `debian` |
| `release` | 版本号，需与 `setos_*` 的入参匹配 |
| `arch` | `x86_64`，或 `any` 表示不限 |
| `variant` | 当前均为 `server` |
| `name` | 菜单展示名 |
| `size` | 菜单展示体积（仅展示用，不参与校验） |
| `url` | 直链，需可直接下载 |
| `sha256` | 校验值，`-` 表示不校验 |

安装器对清单外的版本直接报错，不会合成官方 cloud image 地址。

## 新增发行版

1. 复制 `distros/debian` 为 `distros/<os>`
2. 修改 `conf.sh`：`SUITE`、`MIRROR`、`GUEST_MIRROR_CN`、`IMAGE_NAME`、`IMAGE_HOSTNAME`、`GRUB_ID`、`KEYRING_PKG`、`SECURITY_MIRROR`、`DOCKER_IMAGE`、`USER_NAME`
3. 修改 `scripts/10-rootfs.sh`：`--components`、源文件格式（`.sources` 还是 `sources.list`）、`deb` 行拼法
4. 修改 `packages.list`：内核包名（`linux-image-generic` / `linux-image-amd64` 等）与引导包
5. 修改 `files/etc/apt/` 与 `apt-mirror` 中的源识别分支
6. `catalog/catalog.tsv` 加一行，`image-build.yml` matrix 加一条
7. 若新系统不在 `setos_*` 里，还需在安装器补 `setos_<os>` 分支并接入 `sf_lookup_img`

## 已知问题

| 问题 | 结论 |
|---|---|
| Debian 目标下 `mmdebstrap --keyring=<file>` 无效 | 三次 `NO_PUBKEY`，`--aptopt=Dir::Etc::Trusted` 也无效；有效做法是 `--setup-hook` 把 keyring 拷进 `$1/etc/apt/trusted.gpg.d/99-archive-keyring.gpg` |
| Debian 安全源 | 不能在 `deb.debian.org` 后拼 `-security`（404），必须用独立 `https://security.debian.org/debian-security`；组件仍为 `main contrib non-free-firmware` |
| `mirrors.aliyun.com/debian` | 构建环境返回 403（换 UA 无效），Debian 国内源因此定为 USTC |
| netplan 与 networkd 同时定义网卡 | netplan 直接报错、整份配置不生效，表现为装完 ping 不通；镜像只放 networkd 兜底配置 |
| `cloud-init` 在非 NoCloud 平台 | `datasource_list` 已限定 `NoCloud, ConfigDrive, None`，避免非预期平台重复初始化 |
| 镜像内 `systemd-timesyncd` | Ubuntu 26.04 已拆为独立包，`packages.list` 必须显式包含，否则无该 unit |

## 本地调试

| 脚本 | 用途 |
|---|---|
| `scripts/make-seed.sh <pubkey>` | 生成 NoCloud seed ISO，把公钥注入默认用户 |
| `scripts/test-boot.sh` | 本机 KVM + OVMF 试启动，SSH 端口转发到 2222 |
| `scripts/smoke-test.sh` | CI 用冒烟启动（TCG，无需 KVM），检查串口日志 |
| `scripts/30-verify.sh` | 仅校验已有产物并打印启动方法 |

## 目录结构

```
distros/<os>/
  conf.sh              构建参数（全部可用环境变量覆盖）
  build.sh             入口：检测环境 → 容器或本机构建 → 三阶段
  packages.list        必装包（注释里写明刻意排除的组件）
  packages-ops.list    运维工具层（WITH_OPS=0 可去掉）
  packages.remove      黑名单，误入则 purge
  hooks/10-prepare.sh  系统配置 + 断言
  hooks/99-cleanup.sh  瘦身 + 去标识 + 二次确认
  files/**             静态文件，整体拷入 rootfs
  scripts/10-rootfs.sh  mmdebstrap 构建 rootfs
  scripts/20-image.sh   组盘 + GRUB + qcow2
  scripts/30-verify.sh  产物校验
  scripts/*            keyring 拉取、seed 生成、本地试启、CI 冒烟
```
