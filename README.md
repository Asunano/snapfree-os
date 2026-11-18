# Ubuntu 26.04 LTS 无 snap 服务器镜像 · 使用文档

一个可直接装到服务器的 qcow2：无 snapd、无桌面/业务软件、**无 node/npm 预设、无 Docker、无 linux-firmware**，只保留服务器启动与基础运维必需的最小集合，业务运行时装完自己 `apt install`。UEFI 与 BIOS 都能启动。

```
ubuntu-26.04-server-snapfree-amd64.qcow2
文件 约 1.4G 容量，虚拟磁盘 10G（稀疏）
├─ GPT：p1 bios_grub ｜ p2 ESP vfat 256M ｜ p3 ext4 剩余
├─ GRUB 2.14：UEFI（ EFI/ubuntu + BOOTX64.EFI 兑底 ）与 BIOS 双启动
├─ 内核 7.0.0-43-generic，命令行带 console=ttyS0,115200n8
├─ 无 snapd（从未安装，apt Pin -10 永久封杀）
├─ 无 nodejs / npm / Docker / linux-firmware（按需自己装）
└─ cloud-init：NoCloud / ConfigDrive / None，首启扩分区
```

---

## 1. 账号与登录（先看这段）

| 账号 | 密码 | sudo | 默认能否登录 |
|---|---|---|---|
| `ubuntu` | **空（锁定）** | 免密 | 否，只认 SSH 密钥 |
| `root` | **空（锁定）** | — | 否，`PermitRootLogin prohibit-password` 且无 authorized_keys |

**结论：镜像里没有任何可用密码，也没有任何默认口令。** 没做下面两步之一，你既登不进 SSH，也登不进串口控制台（控制台会停在 login 提示没人应答）。这是故意的：镜像一旦被扫到端口就不该有弱口令。

### 方式 A：cloud-init 注入公钥（推荐）

```bash
# 1) 生成 seed 盘（在你自己的电脑上，需要 genisoimage / xorriso）
./scripts/make-seed.sh ~/.ssh/id_ed25519.pub      # 产出 out/seed.iso

# 2) 把 seed.iso 作为第二块盘挂给虚拟机
#    KVM：   -drive file=out/seed.iso,if=virtio,format=raw,readonly=on
#    Proxmox：上传为 ISO，挂到 CD/DVD
```

首次开机会自动创建用户 `ubuntu`、写入你的公钥、主机名 `ubuntu-server`，然后你就可以：

```bash
ssh ubuntu@<IP>
```

### 方式 B：构建时直接烧密码（内网/临时用）

```bash
USER_PASSWORD='你的密码' SSH_PASSWORD_AUTH=yes ./build.sh
```

这会把密码烧进镜像并打开 SSH 密码登录。**不要用它做对外暴露的机器。**

### 方式 C：构建时换用户名

```bash
USER_NAME=ops ./build.sh        # 默认 ubuntu
```

用户名、密码、是否允许密码登录，三件事都只在构建时决定，装好之后要改就得自己进系统改（`passwd` / `/etc/ssh/sshd_config.d/10-image.conf`）。

### 怎么知道自己该用哪种

| 场景 | 选 |
|---|---|
| 云主机 / KVM / 内网服务器 | A（seed 注入公钥） |
| 物理机装完要临时进去看看 | B（烧密码，装完改回密钥） |
| 批量同构部署 | A + 自动化平台下发 cloud-init |

---

## 2. 装到机器上

### 物理机（U 盘或直写硬盘）

```bash
# 整盘写入
dd if=ubuntu-26.04-server-snapfree-amd64.qcow2 of=/dev/sdX bs=4M status=progress conv=fsync

# 修复备份 GPT + 把根分区撑满整盘
sgdisk -e /dev/sdX
growpart /dev/sdX 3 && resize2fs /dev/sdXp3
```

BIOS 里要**关掉 Secure Boot**（GRUB 未签名）。

### KVM / libvirt / Proxmox

```bash
virt-install --name u2604 --memory 2048 --vcpus 2 --import \
  --disk ubuntu-26.04-server-snapfree-amd64.qcow2 \
  --disk out/seed.iso,device=cdrom \
  --os-variant ubuntu26.04 --network bridge=br0
```

Proxmox：上传 qcow2 → `qm importdisk <vmid> 镜像.qcow2 local-lvm` → 挂 seed.iso 到光驱 → 开机。

### VMware / VirtualBox

```bash
qemu-img convert -f qcow2 -O vmdk ubuntu-26.04-server-snapfree-amd64.qcow2 disk.vmdk
```

### 云主机

大多数平台只收自己的镜像格式（qcow2/raw 常见）。导入后同样靠 cloud-init（NoCloud / ConfigDrive）下发公钥，不要指望控制台的密码。

---

## 3. 首次开机做什么

```bash
ssh ubuntu@<IP>          # 或者用平台控制台（已注入公钥时也要走密钥）

# 1) 看盘有没有自动扩到全盘（cloud-init 的 growpart 会跑一遍）
df -h /                  # 不是 10G？手动来一遍：
                         # sudo growpart /dev/vda 3 && sudo resize2fs /dev/vda3

# 2) 看网
ip -4 a                  # 网卡名固定 eth0（内核参数 net.ifnames=0）
ping -c1 223.5.5.5

# 3) 换源（镜像里默认写的是阿里云，海外或不通就换）
sudo apt-mirror            # 列可用镜像 + 当前源
sudo apt-mirror tuna       # 切清华源并 apt update，失败自动回滚
sudo apt-mirror ustc

# 4) 核对系统状态
apt list --installed 2>/dev/null | wc -l   # 包数量
sshd -T | head -3                          # sshd 有效配置

# 5) 确认真的没有 snap
which snap || echo 无 snap        # 应该输出：无 snap
```

改主机名：`sudo hostnamectl set-hostname your-host`（记得同步 `/etc/hosts` 里的 `127.0.1.1` 行）。

时区已经是 `Asia/Shanghai`，不用再改。

---

## 4. 镜像里有什么

### 装了的

| 类别 | 包 |
|---|---|
| 启动与基础 | systemd、udev、dbus、kmod、util-linux、e2fsprogs、dosfstools |
| 网络与下载 | **curl**、**wget**、ca-certificates、gnupg、iproute2、iptables、iputils-ping |
| 账户与区域 | sudo、locales、tzdata、less、logrotate |
| 远程与初始化 | openssh-server、netplan.io、cloud-init、cloud-guest-utils |
| 启动链 | grub-common、grub2-common、grub-efi-amd64-bin、grub-pc、grub-pc-bin、initramfs-tools、linux-image-generic |
| 虚拟化 | qemu-guest-agent（KVM/云主机可用，物理机无害） |
| 运维工具 | git、vim-tiny、htop、tmux、rsync、jq、unzip、xz-utils、zstd、ethtool、netcat-openbsd |

### 刻意没装的

nginx、apache2、php、mariadb-server、postgresql、snapd、ubuntu-pro-client、plymouth、wpa_supplicant、无线工具、桌面组件，以及 **nodejs / npm、Docker CE、linux-firmware**。

`packages.remove` 里还有一份黑名单：就算被某个依赖意外拖进来，构建期也会 `purge --auto-remove` 掉，并断言 `snapd` 与 `/snap` 不存在。业务软件与运行时请自己装：`sudo apt install nginx nodejs npm`（26.04 源内就是 node 22.x），Docker 按官方文档加 `download.docker.com` 源。

### 服务状态

| 已启用 | 已禁用 |
|---|---|
| `ssh`、`qemu-guest-agent` | `apt-daily.timer`、`apt-daily-upgrade.timer`、`motd-news.timer` |
| `fstrim.timer`、`logrotate.timer`、`systemd-timesyncd` | 默认目标 `/multi-user.target`（无图形） |

`systemd-resolved` **没有装**（省一个移动靶），`/etc/resolv.conf` 是静态文件，DNS 在 netplan 里写死。

---

## 5. 已经做过的调优（知道在哪，方便改）

| 文件 | 作用 |
|---|---|
| `/etc/sysctl.d/99-server.conf` | BBR + fq 擁塞控制、`somaxconn=4096`、`tcp_max_syn_backlog=8192`、`tcp_fastopen=3`、`ip_forward=1`、`swappiness=10`、`file-max=1M` |
| `/etc/modules-load.d/99-server.conf` | 开机加载 `tcp_bbr`（否则 sysctl 里的 bbr 不生效） |
| `/etc/security/limits.d/99-server.conf` | `nofile 65535`、`nproc 32768` |
| `/etc/systemd/journald.conf.d/99-server.conf` | 日志上限 200M / 单文件 50M / 保留 30 天 |
| `/etc/apt/apt.conf.d/99-server` | 全局 `Install-Recommends=false`、`Install-Suggests=false`、`Acquire::Languages=none` |
| `/etc/apt/apt.conf.d/20auto-upgrades` | 全 0，禁止后台自动升级 |
| `/usr/local/bin/apt-mirror` | 一键换源并回滚 |
| `/etc/netplan/10-image.yaml` | 所有 `e*` 网口 DHCP，DNS `223.5.5.5 / 119.29.29.29` |

不想要哪条就删对应文件后 `sudo sysctl --system` / `sudo netplan apply`。

---

## 6. 常见问题

| 现象 | 原因 / 处置 |
|---|---|
| `Permission denied (publickey)` | 没挂 seed，也没烧密码。重启挂 seed.iso；不行就重建镜像带 `USER_PASSWORD` |
| 串口黑屏或乱码 | 控制台要 `115200`；本镜像已配 `console=ttyS0,115200n8` 和 `GRUB_TERMINAL=console serial` |
| 开不了机 / 安全启动报错 | BIOS 关 Secure Boot，GRUB 未签名 |
| 开机卡在 GRUB 命令行 | 磁盘未按 GPT 写入，或 dd 写到了分区而非整盘 |
| `apt update` 403 / 超时 | `sudo apt-mirror tuna` 换个源；阿里云对部分出口段有拦截 |
| 根分区还是 10G | `sudo growpart /dev/sdX 3 && sudo resize2fs /dev/sdXp3`，物理机还需 `sgdisk -e` |
| 网卡不是 eth0 | 本镜像只匹配 `e*`；改成 `match: name: en*` 或其他，改完 `netplan apply` |
| `apt install nginx` 装的东西很少 | 全局关了 recommends，`--install-recommends` 显式开 |
| 想要 node / npm | 镜像不带，直接 `sudo apt install nodejs npm`（26.04 源内是 22.x，零第三方源） |
| 想要 Docker | 自己加官方源：`download.docker.com/linux/ubuntu resolute`；注意 systemd 259 无 cgroup v1，用新版 Docker |
| 想要容器又不想装守护进程 | `sudo apt install podman`，兼容 docker 命令行的大部分用法 |

---

## 7. 附录：自己重新构建

### 用 GitHub Actions（无需本地环境）

```bash
git tag v26.04-20261218 && git push origin v26.04-20261218
```

跑完 `lint → build → smoke → release`，Release 里直接下 qcow2。也可以在 Actions 页点 `Run workflow` 改参数。

| 参数 | 默认 | 说明 |
|---|---|---|
| `suite` | `resolute` | Ubuntu 代号 |
| `mirror` | 官方源 | 构建用源（runner 在海外） |
| `guest_mirror` | 阿里云 | 写进镜像的源 |
| `img_size` | `10G` | 虚拟磁盘大小 |
| `with_docker` | `false` | 预装 Docker CE（默认不装） |
| `with_ops` | `true` | 运维工具层 |
| `with_firmware` | `false` | `linux-firmware`，仅物理机/独服需要 |

改 `build.sh` / `conf.sh` / `scripts/**` / `hooks/**` / `packages*` / `files/**` 会自动触发一次构建；改 README 不会。

### 本地构建

```bash
./build.sh                     # 有 docker 就行（自动进 ubuntu:26.04 特权容器）
sudo ./build.sh               # 或 Ubuntu 26.04 上以 root 直接跑
```

常用覆盖：

```bash
WITH_DOCKER=true ./build.sh    # 需要 Docker 时才装（默认不装）
WITH_OPS=false ./build.sh      # 不带 git/vim/htop
WITH_QGA=false ./build.sh      # 物理机不要 guest agent
WITH_FIRMWARE=true ./build.sh  # 物理机/独服才需要（默认不装）
USER_NAME=ops USER_PASSWORD=xx SSH_PASSWORD_AUTH=yes ./build.sh
DNS_ADDRS= ./build.sh          # DNS 跟 DHCP 走
```

### 已知限制

1. 不支持 Secure Boot（GRUB 未签名）。
2. 镜像不含 nodejs/npm/Docker/linux-firmware，装完自己 `apt install` 或加官方源。
3. systemd 259 无 cgroup v1，极老运行时起不来。
4. arm64 未适配：需改 GRUB target 为 `arm64-efi` 并去掩 `grub-pc-bin`。
5. 默认拒绝密码登录，忘了挂 seed 就只能重建或改盘。

### 仓库结构

```
├─ .github/workflows/build.yml   lint / build / smoke / release
├─ build.sh                      入口（root 直跑或 docker 容器）
├─ conf.sh                       全部参数
├─ packages.list                 核心包（无种子包，故无 snapd）
├─ packages-ops.list             运维工具层
├─ packages.remove               黑名单，误入即 purge
├─ files/                        拷进镜像的静态配置
├─ hooks/10-prepare.sh           源 / 用户 / 可选 Docker / 断言无 snapd
├─ hooks/99-cleanup.sh           清缓存、主机标识、语言包
└─ scripts/                      rootfs、组盘、校验、keyring、seed、冒烟、试启动
```

## License

MIT
