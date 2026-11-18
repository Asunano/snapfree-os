# snapfree-os

一个仓库同时装两件事：**服务器镜像的构建** 和 **把这些镜像装到机器上的安装器**。镜像清单是唯一真源，安装菜单只列清单里的条目。

现在只有 Ubuntu，结构上可直接加 Debian 等（`distros/<os>/` + `catalog/catalog.tsv` 加一行）。

## 目录

```
catalog/catalog.tsv      镜像清单（菜单/安装器只认这里）
installer/               魔改版 reinstall（菜单 + 安装核心）
distros/ubuntu/          Ubuntu 镜像构建套件（mmdebstrap）
.github/workflows/       image-ubuntu / installer-contract
```

## 一键安装（推荐）

在要重装的机器上（root）执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)
```

会出菜单，只能选本仓库镜像：

```
***** 可选镜像 *****
   1) ubuntu  26.04   server       1.2G  Ubuntu 26.04 LTS 无 snap 服务器镜像
   0) 退出
```

选完会依次问用户名/密码（不填可回车跳过自行处理），然后重启进安装环境自动装机。

不想交互就直接指定（**仍然只认仓库镜像**，清单里没有的版本会直接报错，不会退回去拉官网 cloud image）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh) \
  ubuntu 26.04 --username ubuntu --password '你的密码'
```

只要密钥不要密码：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh) \
  ubuntu 26.04 --ssh-key "ssh-ed25519 AAAA... 你@邮箱"
```

## 镜像里有什么

| 项 | 状态 |
|---|---|
| snapd / snap 目录 | **无** |
| nodejs / npm | **无**（自己 `apt install` 或 nvm） |
| Docker | **无**（CI 可开关） |
| nginx / php / 数据库 | **无** |
| wget / curl / ca-certificates / openssh-server | **有** |
| 运维工具 git / vim-tiny / htop / tmux / rsync / jq | 有 |
| linux-firmware | 默认无（物理机需自己装） |
| qemu-guest-agent | 有 |
| 启动 | UEFI + BIOS 双启动（GPT） |

磁盘虚拟 10G，qcow2 实测 1.23 GB。apt 源默认阿里云，可用 `apt-mirror` 换源。

## 账号

- 用户 `ubuntu`，sudo 免密
- **镜像内置 `PasswordAuthentication no`**，只能用密钥登录
- 想让 reinstall 直接烧密码，就传 `--password`（安装器会在目标磁盘上改 sshd 配置）
- cloud-init 保留但只认 NoCloud/ConfigDrive，其他平台开机不会重复跑

## 自己构建镜像

```bash
git clone https://github.com/Asunano/snapfree-os && cd snapfree-os/distros/ubuntu
bash ./build.sh        # 需要 mmdebstrap / qemu-img / parted / dosfstools；非 root 会自动走容器
```

CI：改 `distros/ubuntu/**` 会自动跑 `image-ubuntu`（lint → build → smoke 真启动）；commit message 含 `[publish]` 才会发布到 `image-latest` Release。

## 加一个发行版（例如 Debian 13）

1. 新建 `distros/debian/`，复用同一套 `build.sh` 约定（conf.sh + hooks + scripts + files）；
2. 构建并上传到 Release（或以任何方式拿到直链）；
3. 在 `catalog/catalog.tsv` 加一行：

```
debian-13-server|debian|13|any|server|Debian 13 纯净服务器|700M|<url>|-
```

菜单会自动多一项；安装核心走 `trans.sh` 已有的 debian 分支，不需要改菜单代码。

## 声明

安装器是 [bin456789/reinstall](https://github.com/bin456789/reinstall) 的最小改造（GPL-3.0，见 `installer/LICENSE`）。核心 `trans.sh` 未改。
