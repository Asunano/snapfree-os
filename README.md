# snapfree-os

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
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)   debian 13 --username debian --password '你的密码'
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
| Docker | `curl -fsSL https://get.docker.com \| sh` |
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
