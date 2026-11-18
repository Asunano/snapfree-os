# installer（魔改版 reinstall）

本目录是 `snapfree-os` 仓库自带的安装器，基于 [bin456789/reinstall](https://github.com/bin456789/reinstall)（GPL-3.0）最小改造。

## 跟上游的区别

| 项 | 上游 | 本仓库 |
|---|---|---|
| 镜像来源 | 各发行版官方 cloud image | **只能选本仓库 `catalog/catalog.tsv` 里的镜像** |
| 启动方式 | 必须带参数 `ubuntu 26.04` | 无参数启动进**镜像菜单** |
| `confhome` | 上游仓库 | 本仓库 `installer/` |
| 云镜像内存门槛 | 256M | 512M |
| 安装核心 | `trans.sh` 搬分区 + `modify_<os>` + `basic_init` | **完全保留，未改代码** |

## 用法

```bash
# 菜单（推荐）
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh)

# 直接指定（仍然只认仓库镜像）
bash <(curl -fsSL https://raw.githubusercontent.com/Asunano/snapfree-os/main/installer/reinstall.sh) \
  ubuntu 26.04 --username ubuntu --password '你的密码'
```

菜单长这样：

```
***** 可选镜像（.../catalog/catalog.tsv） *****
   1) ubuntu  26.04   server       1.2G  Ubuntu 26.04 LTS 无 snap 服务器镜像
   0) 退出

请选择镜像编号 [1]:
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `reinstall.sh` | 入口：镜像菜单 + 参数解析 + 准备安装环境 |
| `trans.sh` | 安装核心（在安装环境里执行，未修改） |
| `initrd-network.sh` | initrd 阶段联网 |
| `fix-eth-name.*` | 网卡命名修正 |
| `deprecated/` | 上游历史配置（部分分支仍会拉取） |
| `windows*` / `wmic.ps1` | 上游 Windows 安装路径（本仓库不提供 Windows 镜像） |

## 添加新镜像

1. 把镜像传到 Release，或以其他方式获得直链；
2. 在 `catalog/catalog.tsv` 加一行：

```
debian-13-server|debian|13|any|server|Debian 13 纯净服务器|700M|<url>|-
```

3. 菜单自动多一项，`ubuntu`/`debian` 的安装核心由 `trans.sh` 原有分支处理。
