# distros/debian —— Debian 服务器镜像构建套件

与 `distros/ubuntu` 同构：同一套 `mmdebstrap` 管线、同一份优化（BBR、limits、timesyncd、
首启自动选源、按内存分档 swap）。差异只在发行版本身：源（deb.debian.org / aliyun debian）、
组件（main + contrib + non-free-firmware）、keyring（debian-archive-keyring）、内核元包（linux-image-amd64）。

## 构建

```bash
# 本机（root + mmdebstrap）
sudo SUITE=trixie ./build.sh
sudo SUITE=bookworm ./build.sh

# 只有 docker
SUITE=trixie ./build.sh
```

产物：`out/debian-13-server-snapfree-amd64.qcow2`（trixie）或 `debian-12-...`（bookworm）。

## 参数

见 `conf.sh`，全部可用环境变量覆盖：`SUITE` `MIRROR` `GUEST_MIRROR` `GUEST_MIRROR_CN`
`IMG_SIZE` `WITH_DOCKER` `WITH_OPS` `WITH_QGA` `WITH_FIRMWARE` `SWAP_MODE` `TIMEZONE`。

## 与 ubuntu 套件的共同点

`files/` 下的 sysctl、limits、timesyncd、sf-firstboot、sf-mirror-auto 与 ubuntu 套件保持一致，
改动其中一侧时另一侧也要同步。
