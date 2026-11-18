# ubuntu-snapfree-image

用 GitHub Actions 从 Ubuntu 官方源构建**不含 snap 的服务器 qcow2**。
一条 `Run workflow` 出镜像，打 tag 自动发 Release。

```
ubuntu-26.04-server-snapfree-amd64.qcow2
├─ GPT：bios_grub + ESP(256M) + ext4 root
├─ GRUB：UEFI(EFI/ubuntu + BOOTX64.EFI 兜底) 与 BIOS 双启动
├─ 无 snapd（从未安装，且 apt Pin -10 永久封杀）
├─ nodejs 22.22.1 + npm 9.2.0，apt 直装，零第三方 JS 源
├─ Docker CE（download.docker.com 的 resolute 源）
└─ cloud-init：[NoCloud, ConfigDrive, None]，首启自动扩分区
```

## 为什么用 26.04 而不是 24.04

| | 24.04 noble | 26.04 resolute |
|---|---|---|
| `nodejs` | 18.19.1（上游 Node 18 已于 2025-04 EOL） | **22.22.1** |
| `npm` | 9.2.0 | 9.2.0（独立包） |
| 不加第三方源就拿到现代 Node | ❌ | ✅ |
| 标准支持 | 2029-04 | 2031-04 |

24.04 上要 node 22 只能挂 NodeSource，等于又把“额外加源”背回来了。

## 在 Actions 里构建

1. 推到 GitHub：

```bash
git init && git add . && git commit -m "init"
git remote add origin git@github.com:<你>/ubuntu-snapfree-image.git
git push -u origin main
```

2. 仓库 → **Actions** → 左侧 `build-qcow2` → **Run workflow**，填参数：

| 输入 | 默认 | 说明 |
|---|---|---|
| `suite` | `resolute` | Ubuntu 代号 |
| `mirror` | `https://archive.ubuntu.com/ubuntu` | **构建**用源（runner 在海外，走官方最快） |
| `guest_mirror` | `https://mirrors.aliyun.com/ubuntu` | **写进镜像**的源（装机在国内直连） |
| `img_size` | `10G` | 磁盘虚拟大小（稀疏，实际占用约 1.5G） |
| `with_docker` | `true` | 预装 Docker CE |
| `with_ops` | `true` | 运维工具层（git/vim/htop/tmux/rsync/jq…） |
| `with_firmware` | `true` | `linux-firmware`，物理机网卡/RAID 卡需要，约 +500MB |
| `smoke_test` | `false` | 构建后用 TCG 启动一次，验证能进 cloud-init/login |

3. 跑完在 run 页面底部下载 Artifact：`qcow2-<run_number>`（保留 14 天）。

4. 想长期分发 → 打 tag 即自动发 Release：

```bash
git tag v26.04-20261118 && git push origin v26.04-20261118
```

`release` job 会把 qcow2 + sha256 传到 Release 资产里，下载地址稳定。

> runner 是 `ubuntu-24.04`，其 keyring 只有 noble 的密钥。构建时 `build.sh` 会自动探测宿主代号 ≠ 目标代号，从目标发行版的 `Packages.gz` 里取 `ubuntu-keyring` 并传给 `mmdebstrap --keyring`，**不需要任何手工干预**。

工作流每月 1 日定时重建一次，保证镜像里的 deb 是最新安全补丁版本。

## 本地构建

```bash
# 有 docker 就行（自动进 ubuntu:26.04 特权容器）
./build.sh

# 或 Ubuntu 26.04 上以 root 直接跑
sudo apt install mmdebstrap qemu-utils dosfstools parted gdisk
sudo ./build.sh
```

常用覆盖：

```bash
WITH_DOCKER=false ./build.sh          # 去掉 Docker，省约 500MB
WITH_OPS=false ./build.sh             # 不带 git/vim/htop/tmux，纯运行环境
WITH_QGA=false ./build.sh             # 物理机不要 qemu-guest-agent
WITH_FIRMWARE=false ./build.sh        # 省 500MB，网卡缺固件时再开
IMG_SIZE=20G ./build.sh
MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu ./build.sh
GUEST_MIRROR=https://mirrors.ustc.edu.cn/ubuntu ./build.sh
DNS_ADDRS= ./build.sh                 # 不留静态 DNS，沿用 DHCP
```

`make build / seed / boot / smoke / lint / clean` 也可用。

## 装到机器上

```bash
# 物理机整盘写
dd if=ubuntu-26.04-server-snapfree-amd64.qcow2 of=/dev/sdX bs=4M status=progress conv=fsync

# 修复备份 GPT 并扩容
sgdisk -e /dev/sdX
growpart /dev/sdX 3 && resize2fs /dev/sdXp3

# KVM / Proxmox / libvirt
virt-install --name u2604 --memory 2048 --vcpus 2 --import \
  --disk ubuntu-26.04-server-snapfree-amd64.qcow2 --os-variant ubuntu24.04
```

登录方式（二选一）：

```bash
# A. cloud-init 注入公钥（推荐）
./scripts/make-seed.sh ~/.ssh/id_ed25519.pub     # 生成 seed.iso，挂成第二块盘

# B. 构建时直接带密码（内网/临时用）
USER_PASSWORD=xxx SSH_PASSWORD_AUTH=yes ./build.sh
```

镜像里 root 锁定、SSH 默认只认密钥，**没有 seed 也没有密码时是登不进去的**（串口控制台也一样）。

## 镜像规格

| 项 | 值 |
|---|---|
| 基座 | `mmdebstrap --variant=apt`，main+universe，**不含 ubuntu-minimal/ubuntu-server 等种子包** |
| 分区 | p1 `bios_grub` 1–2MiB ／ p2 ESP vfat 2–258MiB ／ p3 ext4 剩余 |
| 内核参数 | `net.ifnames=0 biosdevname=0`（网卡固定 eth0）+ 串口 `ttyS0,115200n8` |
| 网络 | netplan：所有 `e*` 网口 DHCP，DNS 固定 `223.5.5.5 / 119.29.29.29`（`DNS_ADDRS=` 可关） |
| 预装 | `curl`、`wget`、`ca-certificates`、`nodejs/npm`、`openssh-server`、`cloud-init`、Docker CE（可选） |
| 不装 | nginx、apache2、php、mariadb/postgresql、snapd、ubuntu-pro-client、plymouth、wpa_supplicant |
| 已清 | machine-id、ssh host key、apt 缓存/日志、changelog、非中英文语言包 |

## 服务器向精简与调优

这一层是“装机即用、但不背日用/桌面包袱”的部分，全部在构建时写死，不需要装完再手工改。

**源**

- 构建源 `MIRROR` 与镜像内源 `GUEST_MIRROR` 分离：CI 在海外用官方源加速，镜像里写阿里云。
- 镜像内置 `/usr/local/bin/apt-mirror`，一条命令换源并自动回滚：

```bash
sudo apt-mirror                 # 列可用镜像 + 当前源
sudo apt-mirror tuna            # 切清华源并 apt update
sudo apt-mirror https://xxx/ubuntu
```

- `/etc/apt/apt.conf.d/99-server`：全局 `Install-Recommends=false`、`Install-Suggests=false`、`Acquire::Languages=none`、重试 3 次。从源头卡住“装一个带十个”。
- `/etc/apt/apt.conf.d/20auto-upgrades` + 关掉 `apt-daily.timer`/`apt-daily-upgrade.timer`：后台不再自动跑 apt。

**清理**

- `packages.remove` 黑名单（nginx/apache/php/mariadb/postgresql/snapd/plymouth/wpasupplicant…）：如果被依赖意外拖进来，构建期自动 `purge --auto-remove`，并断言 snapd 不存在。
- 收尾删 `changelog`、`/usr/share/locale` 里除 `en*/zh*` 之外的全部目录（这一项通常省 150MB+），保留 `copyright` 满足许可证要求。

**调优**

| 文件 | 内容 |
|---|---|
| `/etc/sysctl.d/99-server.conf` | BBR + fq、`somaxconn=4096`、`tcp_fastopen=3`、`ip_forward=1`、`swappiness=10`、`file-max=1M` |
| `/etc/modules-load.d/99-server.conf` | `tcp_bbr`（开机加载，否则 sysctl 里的 bbr 生不效） |
| `/etc/systemd/journald.conf.d/99-server.conf` | 日志上限 200M，保留 30 天 |
| `/etc/security/limits.d/99-server.conf` | `nofile 65535`、`nproc 32768` |
| `motd` | 删掉 help-text / motd-news / cloudimg 广告脚本，只留 header |

`fstrim.timer`、`logrotate.timer`、`systemd-timesyncd` 已启用；`multiuser.target` 为默认目标。

## 已知限制

1. **不支持 Secure Boot**：GRUB 未签名，BIOS 里要关掉。
2. **npm 是 9.2.0**（Ubuntu 打包版本）；要新版 `sudo npm i -g npm@latest`，不涉及 apt 源。
3. **systemd 259 已移除 cgroup v1**：极老的服务/容器运行时会起不来，Docker CE 2.x 正常。
4. **`linux-firmware` 默认装**（网卡/RAID 卡需要）；`with_firmware=false` 可省约 500MB，但部分 Intel/Realtek 网卡会缺固件。
5. **全局关闭了 recommends**：后续 `apt install nginx` 只装必需包，需要推荐包时显式 `--install-recommends`。
6. **arm64 未适配**：需改 `scripts/20-image.sh` 的 GRUB target 为 `arm64-efi`，并从 `packages.list` 去掉 `grub-pc-bin`。

## 仓库结构

```
.
├─ .github/workflows/build.yml   lint / build / smoke / release
├─ build.sh                      入口（root 直跑或 docker 容器）
├─ conf.sh                       全部参数（workflow 输入映射到这里）
├─ packages.list                 核心包清单（无种子包，故无 snapd）
├─ packages-ops.list             运维工具层（WITH_OPS=0 关闭）
├─ packages.remove               黑名单，误入即 purge
├─ files/                        直接拷进镜像的静态文件
│  ├─ etc/apt/apt.conf.d/{20auto-upgrades,99-server}
│  ├─ etc/apt/preferences.d/nosnap.pref
│  ├─ etc/cloud/cloud.cfg.d/99-image.cfg
│  ├─ etc/default/grub
│  ├─ etc/security/limits.d/99-server.conf
│  ├─ etc/sysctl.d/99-server.conf
│  ├─ etc/systemd/journald.conf.d/99-server.conf
│  ├─ etc/modules-load.d/99-server.conf
│  ├─ etc/netplan/10-image.yaml
│  ├─ etc/ssh/sshd_config.d/10-image.conf
│  └─ usr/local/bin/apt-mirror   镜像内换源工具
├─ hooks/10-prepare.sh           源/时区/用户/Docker/黑名单/断言无 snapd
├─ hooks/99-cleanup.sh           清缓存、主机标识、changelog、多余语言包
└─ scripts/
   ├─ 10-rootfs.sh               mmdebstrap 构建 rootfs
   ├─ 20-image.sh                分区 + GRUB 双启动 + qcow2
   ├─ 30-verify.sh               产物校验与提示
   ├─ fetch-keyring.sh           目标发行版 keyring（CI 必需）
   ├─ smoke-test.sh              TCG 冒烟启动
   ├─ make-seed.sh               cloud-init seed.iso
   └─ test-boot.sh               本地 KVM 试启动
```

## License

MIT
