#!/usr/bin/env bash
# ============================================================
# 构建参数：全部可用环境变量覆盖，不改文件也能定制
# ============================================================

# ---------- 发行版 ----------
export SUITE="${SUITE:-resolute}"                    # Ubuntu 26.04 LTS
export ARCH="${ARCH:-amd64}"

# ---------- 源 ----------
export MIRROR="${MIRROR:-https://archive.ubuntu.com/ubuntu}"        # 构建源
export GUEST_MIRROR="${GUEST_MIRROR:-https://mirrors.aliyun.com/ubuntu}"  # 写进镜像的 apt 源

# ---------- 镜像规格 ----------
export IMG_SIZE="${IMG_SIZE:-10G}"                   # 虚拟磁盘大小
export ESP_SIZE_MIB="${ESP_SIZE_MIB:-256}"           # EFI 分区大小
export QCOW2_COMPRESS="${QCOW2_COMPRESS:-1}"         # qemu-img convert -c

# ---------- 系统 ----------
export TIMEZONE="${TIMEZONE:-Asia/Shanghai}"
export IMAGE_HOSTNAME="${IMAGE_HOSTNAME:-ubuntu-server}"
export IMAGE_NAME="${IMAGE_NAME:-ubuntu-26.04-server-snapfree-${ARCH}}"

# ---------- 账号 ----------
export USER_NAME="${USER_NAME:-ubuntu}"
export USER_PASSWORD="${USER_PASSWORD:-}"             # 留空 = 不设密码（只能密钥登录）
export SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-yes}"  # 镜像内 sshd 是否允许密码登录
export GRUB_ID="${GRUB_ID:-ubuntu}"

# ---------- 可选组件（=1 才装）----------
_as_bool(){ case "${1:-0}" in 1|true|yes|on) echo 1 ;; *) echo 0 ;; esac; }
export WITH_DOCKER="${WITH_DOCKER:-0}"               # Docker CE（默认关闭，纯净系统；需要时 WITH_DOCKER=1）
export WITH_OPS="${WITH_OPS:-1}"                     # 运维小工具（git/vim-tiny/htop/tmux/rsync/jq/unzip）
export WITH_QGA="${WITH_QGA:-1}"                     # qemu-guest-agent
export WITH_FIRMWARE="${WITH_FIRMWARE:-0}"           # linux-firmware（物理机/独服才需要）
export WITH_QGA="$(_as_bool "$WITH_QGA")"
export WITH_OPS="$(_as_bool "$WITH_OPS")"
export WITH_DOCKER="$(_as_bool "$WITH_DOCKER")"
export WITH_FIRMWARE="$(_as_bool "$WITH_FIRMWARE")"

# ---------- DNS ----------
export DNS_ADDRS="${DNS_ADDRS-223.5.5.5 119.29.29.29}"   # 留空则沿用 DHCP 下发的 DNS

# ---------- 构建容器 ----------
export DOCKER_IMAGE="${DOCKER_IMAGE:-ubuntu:26.04}"
