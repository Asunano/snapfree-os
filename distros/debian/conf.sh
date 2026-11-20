#!/usr/bin/env bash
# ============================================================
# Debian 13/12 无 snap 服务器镜像 —— 构建参数（全部可用环境变量覆盖）
#   例：SUITE=bookworm MIRROR=http://deb.debian.org/debian ./build.sh
# ============================================================
KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export KIT_DIR

_as_bool(){ case "${1:-}" in true|TRUE|True|yes|YES|1) echo 1 ;; *) echo 0 ;; esac; }

# ---- 发行版 / 源 ----
export SUITE="${SUITE:-trixie}"
export MIRROR="${MIRROR:-http://deb.debian.org/debian}"
export GUEST_MIRROR="${GUEST_MIRROR:-http://deb.debian.org/debian}"
export GUEST_MIRROR_CN="${GUEST_MIRROR_CN:-https://mirrors.ustc.edu.cn/debian}"
export GUEST_MIRROR_DEFAULT="${GUEST_MIRROR_DEFAULT:-http://deb.debian.org/debian}"
export MIRROR_AUTO="${MIRROR_AUTO:-1}"
export ARCH="${ARCH:-amd64}"
export KEYRING="${KEYRING:-}"
export KEYRING_PKG="${KEYRING_PKG:-debian-archive-keyring}"
export SECURITY_MIRROR="${SECURITY_MIRROR:-https://security.debian.org/debian-security}"

# ---- 产物 ----
export OUT_DIR="${OUT_DIR:-$KIT_DIR/out}"
export WORK_DIR="${WORK_DIR:-$KIT_DIR/work}"
case "$SUITE" in
  trixie)   _VER="13" ;;
  bookworm) _VER="12" ;;
  forky)    _VER="14" ;;
  *)        _VER="$SUITE" ;;
esac
export IMAGE_NAME="${IMAGE_NAME:-debian-${_VER}-server-snapfree-$ARCH}"
export IMAGE_HOSTNAME="${IMAGE_HOSTNAME:-debian-server}"

# ---- 磁盘 ----
export IMG_SIZE="${IMG_SIZE:-10G}"
export ESP_SIZE_MIB="${ESP_SIZE_MIB:-256}"
export QCOW2_COMPRESS="${QCOW2_COMPRESS:-1}"

# ---- 系统 ----
export TIMEZONE="${TIMEZONE:-Asia/Shanghai}"
export USER_NAME="${USER_NAME:-root}"     # 默认直接 root 登录；想要普通用户就改成 ubuntu/debian 重建
export USER_PASSWORD="${USER_PASSWORD:-}"
export SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-yes}"
export GRUB_ID="${GRUB_ID:-debian}"
export SWAP_MODE="${SWAP_MODE:-auto}"

# ---- 组件开关 ----
export WITH_DOCKER="${WITH_DOCKER:-0}"
export WITH_OPS="${WITH_OPS:-1}"
export WITH_QGA="${WITH_QGA:-1}"
export WITH_FIRMWARE="${WITH_FIRMWARE:-0}"
export DNS_ADDRS="${DNS_ADDRS-223.5.5.5 119.29.29.29}"

# ---- 容器构建 ----
export DOCKER_IMAGE="${DOCKER_IMAGE:-debian:13}"

# ---- 归一化 ----
export WITH_DOCKER="$(_as_bool "$WITH_DOCKER")"
export WITH_OPS="$(_as_bool "$WITH_OPS")"
export WITH_QGA="$(_as_bool "$WITH_QGA")"
export WITH_FIRMWARE="$(_as_bool "$WITH_FIRMWARE")"
export QCOW2_COMPRESS="$(_as_bool "$QCOW2_COMPRESS")"
export MIRROR_AUTO="$(_as_bool "$MIRROR_AUTO")"
