# snapfree-os

给 **VPS / 云服务器 / KVM 虚拟机** 用的重装系统工具。

一句话：系统里不塞垃圾（没有 snap、没有 Docker、没有 nodejs），装完不光秃秃也安全，常用优化（BBR、swap、国内源、对时）已经配好。

只能装在 **KVM / 云主机 / VPS** 上，不支持 OpenVZ/LXC，也不能装在物理机上。

## 能装哪些系统

| 系统 | 版本 | 下载大小 |
|---|---|---|
| Ubuntu | 26.04 LTS / 24.04 LTS | 1.2G / 1.1G |
| Debian | 13 (trixie) / 12 (bookworm) | 350M / 380M |

四套都是 64 位 x86_64，从零构建的纯净版，优化配置四套完全一致。**默认用户全部是 root**。

## 怎么装

用 root 登录你的服务器（SSH 或服务商网页控制台都行），把下面这一整行复制粘贴进去，回车：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
```

> 这一步卡住或报错（国内访问 GitHub 经常很慢），换成这条走加速的：
>
> ```bash
> bash <(curl -fsSL https://mirror-one.losn.cc/https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
> ```

然后会出现菜单，用数字选你要装的系统：

```text
***** 可选镜像 *****
   1) ubuntu  26.04   server  1.2G  Ubuntu 26.04 LTS 无 snap 服务器镜像
   2) ubuntu  24.04   server  1.1G  Ubuntu 24.04 LTS 无 snap 服务器镜像
   3) debian  13      server  350M  Debian 13 (trixie) 纯净服务器镜像
   4) debian  12      server  380M  Debian 12 (bookworm) 纯净服务器镜像
   0) 退出
```

菜单里**只能选仓库里有的镜像**，选完自动下载、写入磁盘、重启进新系统。中途 SSH 会断一次，正常。

## 安装时它问你什么

1. **用户名**：直接回车就是 `root`（默认）。想用普通用户就把名字写成 `ubuntu` / `debian` 或随便什么，安装器会自己建。
2. **密码**：可以留空。
3. **SSH 公钥**：可以留空。
4. 主机名、DNS、时区：一路回车用默认就行。

**密码和公钥两样都不给，装完谁都登不上**——镜像里没任何预置密码，安全也就不怕扫。

### “不想设密码就设置 SSH 密钥”到底是什么意思

SSH 登录只认两种凭据：**密码** 或 **密钥**。二选一都行，都能进。

- 设了密码：以后 `ssh root@IP`，输密码进去。简单，但密码被猜中/被暴破的风险一直在。
- 只给密钥、密码留空：以后 `ssh -i 你的私钥 root@IP`，不输密码直接进。安全性高得多，这是服务器圈子的常规做法。

想要密钥的话，在自己电脑上先生成一对（没有的话）：

```bash
ssh-keygen -t ed25519        # 一路回车，默认存到 ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub    # 这个是公钥，整行复制
```

安装器问 SSH 公钥时，把 `ssh-keygen` 生成的那一行公钥粘进去。私钥（`id_ed25519`，没有 `.pub`）留在自己电脑，永不外传。

不想用菜单也可以直接指定（同样只认仓库里的镜像）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh) \
  debian 13 --username root --password '你的密码'
```

## 装完怎么用

1. 等机器重启（一般 1～3 分钟）
2. 用密码或密钥 SSH 登录：

```bash
ssh root@你的服务器IP
```

默认就是 root，不需要 sudo，也没 sudo 这回事。

## 装完就已经有的东西

不用你动手，下面这些开箱就是好的：

- **BBR 拥塞控制 + fq**：网络提速标配，`sysctl net.ipv4.tcp_congestion_control` 能看到 `bbr`
- **swap 自动分档**：按内存自动建（1G 内存建 2G，4G 内存建 4G，16G 以上不建），开机自动挂载
- **国内软件源**：首启自动判断国内/国外，国内机自动换成国内源
- **自动对时**：`systemd-timesyncd` + 国内 NTP，时区 `Asia/Shanghai`
- **文件句柄 / 连接数上限**：按服务器场景调过，不会动辄报 `too many open files`
- **qemu-guest-agent**：云平台能看虚拟机 IP 和状态
- **编辑器**：`nano`、`vim-tiny`
- **网络诊断**：`mtr-tiny`（路由逐跳质量）、`traceroute`、`bind9-dnsutils`（dig/nslookup）、`whois`、`tcpdump`、`iftop`（实时带宽）、`nmap`、`socat`、`net-tools`（ifconfig/netstat）、`lsof`（谁占了端口/文件）
- **系统观察**：`htop`、`sysstat`（sar/iostat/mpstat 历史数据）、`strace`、`ncdu`（磁盘占用排行）、`tree`、`file`、`bc`、`time`、`pv`
- **磁盘 / 分区**：`parted`、`gdisk`（VPS 扩容后用）
- **压缩**：`unzip`、`zip`、`xz-utils`、`bzip2`、`zstd`、`pigz`、`lz4`
- **日常**：`git`、`tmux`、`rsync`、`jq`、`bash-completion`、`openssl`、`pciutils`、`man-db`（有 `man`）

## 系统里没有的东西

按需求刻意没装，想要自己装：

| 没有 | 怎么装 |
|---|---|
| snap / snapd | Ubuntu 镜像本来就不带，也不要装 |
| Docker | `curl -fsSL https://get.docker.com \\| sh` |
| nodejs / npm | 用 nvm，或 `apt install nodejs npm` |
| nginx / mysql / php | 自己 `apt install` |
| linux-firmware | 虚拟机用不上；装物理机才需要 |

## 关于下载速度

安装器下载镜像时会逐个加速站测一下（各拉 1MB 计时），挑最快那个下载；海外机器能直连 GitHub 就直连，直连不通才走加速站。四个站全挂时回落 GitHub 原地址，不会卡住。

下载到的文件与官方发布的是同一个，校验值一致。

## 常见问题

**装完 ping 不通 / SSH 连不上？**
先在云控制台确认机器真重启完了，再确认安装时设了密码或加了公钥（两样都没给就肯定进不去）。

**为什么默认是 root？想改回去怎么办？**
自己开机器，省掉建用户的麻烦。想要普通用户：安装时把用户名写成 `ubuntu`，或者在安装器参数里加 `--username ubuntu`。

**想换软件源？**

```bash
apt-mirror            # 看当前用的哪个源
apt-mirror auto       # 按所在地自动选
apt-mirror aliyun     # 也可指定：tuna / ustc / huawei / official
```

**时间不对？**
`timedatectl status` 看看，不对就 `systemctl restart systemd-timesyncd`。

**安装中途 SSH 断了？**
正常，安装器要往磁盘写系统然后重启。等几分钟重新连。

**能不能装别的系统（Arch / Alpine / CentOS）？**
目前只做 Ubuntu 和 Debian。加新系统见 [`docs/BUILD.md`](docs/BUILD.md)。

## 装完之后自检

不确定装得对不对，跑这个（只检查，不改任何东西）：

```bash
curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/tools/snapfree-check.sh | sudo bash
```

它会查：系统版本、BBR 是否生效、swap 是否挂上、软件源是否为国内源、SSH 是否在跑、时区、各项内核参数、有没有混进 snap/docker。

## 想自己做镜像 / 改配置

构建方式、CI、怎么加发行版： [`docs/BUILD.md`](docs/BUILD.md)；两套构建套件的说明： [`distros/README.md`](distros/README.md)。

## 声明

安装器改造自 [bin456789/reinstall](https://github.com/bin456789/reinstall)（GPL-3.0，见 `installer/LICENSE`）：菜单只选本仓库镜像，下载走测速选站，其余安装流程与上游一致。
