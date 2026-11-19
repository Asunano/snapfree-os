#!/usr/bin/env bash
# ============================================================
# 构建参数：全部可用环境变量覆盖，不改文件也能定制
#   例： SUITE=resolute MIRROR=http://archive.ubuntu.com/ubuntu ./build.sh
#   GitHub Actions 的 workflow_dispatch 输入直接映射到这些变量
# ============================================================
KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export KIT_DIR

# 布尔量归一化：接受 true/false/yes/no/1/0
_as_bool(){ case "${1:-}" in true|TRUE|True|yes|YES|1) echo 1 ;; *) echo 0 ;; esac; }

# ---- 发行版 / 源 ----
export SUITE="${SUITE:-resolute}"
export MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu}"
# 写进镜像的源（可与构建源不同：CI 在海外用官方源构建，装机在国内用阿里云）
export GUEST_MIRROR="${GUEST_MIRROR:-https://mirrors.aliyun.com/ubuntu}"
export ARCH="${ARCH:-amd64}"
# 宿主 keyring 与目标发行版不匹配时，由 scripts/fetch-keyring.sh 填充
export KEYRING="${KEYRING:-}"

# ---- 产物 ----
export OUT_DIR="${OUT_DIR:-$KIT_DIR/out}"
export WORK_DIR="${WORK_DIR:-$KIT_DIR/work}"
case "$SUITE" in
  resolute) _VER="26.04" ;;
  noble)    _VER="24.04" ;;
  *)        _VER="$SUITE" ;;
esac
export IMAGE_NAME="${IMAGE_NAME:-ubuntu-${_VER}-server-snapfree-$ARCH}"
export IMAGE_HOSTNAME="${IMAGE_HOSTNAME:-ubuntu-server}"

# ---- 磁盘 ----
export IMG_SIZE="${IMG_SIZE:-10G}"
export ESP_SIZE_MIB="${ESP_SIZE_MIB:-256}"
export QCOW2_COMPRESS="${QCOW2_COMPRESS:-1}"

# ---- 系统 ----
export TIMEZONE="${TIMEZONE:-Asia/Shanghai}"
export USER_NAME="${USER_NAME:-ubuntu}"
export USER_PASSWORD="${USER_PASSWORD:-}"        # 留空 = 不设密码
export SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-yes}"
export GRUB_ID="${GRUB_ID:-ubuntu}"
# 首启自动建 swapfile 的上限（MB，0 = 不建）；实际取 min(该值, 内存的一半)
export SWAP_MIN_MB="${SWAP_MIN_MB:-2048}"

# ---- 组件开关 ----
export WITH_DOCKER="${WITH_DOCKER:-0}"           # Docker CE（默认关闭，纯净系统；需要时 WITH_DOCKER=1）
export WITH_OPS="${WITH_OPS:-1}"                 # 运维工具层（git/vim/htop/tmux...）
export WITH_QGA="${WITH_QGA:-1}"                 # qemu-guest-agent（虚拟机/云主机用）
export WITH_FIRMWARE="${WITH_FIRMWARE:-0}"       # linux-firmware（默认不装；物理机/独服才需要）
export DNS_ADDRS="${DNS_ADDRS-223.5.5.5 119.29.29.29}"   # 留空则沿用 DHCP 下发的 DNS

# ---- 容器构建（本机没有 root/mmdebstrap 时用） ----
export DOCKER_IMAGE="${DOCKER_IMAGE:-ubuntu:26.04}"

# ---- 归一化（workflow 输入可能是 true/false 字符串） ----
export WITH_DOCKER="$(_as_bool "$WITH_DOCKER")"
export WITH_OPS="$(_as_bool "$WITH_OPS")"
export WITH_QGA="$(_as_bool "$WITH_QGA")"
export WITH_FIRMWARE="$(_as_bool "$WITH_FIRMWARE")"
export QCOW2_COMPRESS="$(_as_bool "$QCOW2_COMPRESS")"
