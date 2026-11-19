# 构建与维护

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
