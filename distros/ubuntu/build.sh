#!/usr/bin/env bash
# ============================================================
# Ubuntu 26.04 LTS 无 snap 服务器镜像 —— 构建入口
#   产物：out/*.qcow2（GPT + UEFI/BIOS 双启动 + cloud-init）
#
#   本机有 root + mmdebstrap  -> 直接构建（GitHub Actions 走这条）
#   否则自动进 ubuntu:26.04 特权容器构建（只需 docker）
# ============================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

log() { printf '\033[1;36m[*]\033[0m %s\n' "$*"; }
ok()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2; exit 1; }

INNER=0
for a in "$@"; do
  case "$a" in
    --inner) INNER=1 ;;
    -h|--help)
      sed -n '2,17p' "$0"; exit 0 ;;
    *) die "未知参数：$a" ;;
  esac
done

# ---------- 0. 决定在哪儿构建 ----------
if [ "$INNER" -eq 0 ]; then
  if [ "$(id -u)" -eq 0 ] && command -v mmdebstrap >/dev/null 2>&1; then
    log "本机构建（root + mmdebstrap 已就绪）"
  else
    command -v docker >/dev/null 2>&1 || die "本机没有 mmdebstrap 也没有 docker。请装 docker，或在 Ubuntu 26.04 上以 root 运行。"
    log "进入容器构建：$DOCKER_IMAGE（--privileged，需要 loop 设备）"
    exec docker run --rm --privileged \
      -v "$HERE:/build" -w /build \
      -e KIT_DIR=/build \
      -e SUITE="$SUITE" -e MIRROR="$MIRROR" -e ARCH="$ARCH" \
      -e GUEST_MIRROR="$GUEST_MIRROR" -e DNS_ADDRS="$DNS_ADDRS" \
      -e IMG_SIZE="$IMG_SIZE" -e ESP_SIZE_MIB="$ESP_SIZE_MIB" \
      -e IMAGE_NAME="$IMAGE_NAME" -e IMAGE_HOSTNAME="$IMAGE_HOSTNAME" \
      -e TIMEZONE="$TIMEZONE" -e USER_NAME="$USER_NAME" \
      -e USER_PASSWORD="$USER_PASSWORD" -e SSH_PASSWORD_AUTH="$SSH_PASSWORD_AUTH" \
      -e WITH_DOCKER="$WITH_DOCKER" -e WITH_OPS="$WITH_OPS" -e WITH_QGA="$WITH_QGA" \
      -e WITH_FIRMWARE="$WITH_FIRMWARE" \
      -e QCOW2_COMPRESS="$QCOW2_COMPRESS" \
      "$DOCKER_IMAGE" bash -c '
        set -e
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
          mmdebstrap qemu-utils dosfstools parted gdisk e2fsprogs util-linux \
          ubuntu-keyring kmod >/dev/null
        INNER=1 bash /build/build.sh --inner
      '
  fi
fi

[ "$(id -u)" -eq 0 ] || die "构建阶段需要 root（loop 设备 / chroot）"

mkdir -p "$OUT_DIR" "$WORK_DIR"
log "SUITE=$SUITE  ARCH=$ARCH  MIRROR=$MIRROR  GUEST_MIRROR=$GUEST_MIRROR"
log "Docker=$WITH_DOCKER  ops=$WITH_OPS  qga=$WITH_QGA  firmware=$WITH_FIRMWARE  磁盘=${IMG_SIZE}"

# ---------- keyring：宿主代号与目标不一致时自动拉取 ----------
if [ -z "${KEYRING:-}" ]; then
  HOST_CODENAME=""
  if [ -r /etc/os-release ]; then
    HOST_CODENAME=$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")
  fi
  if [ "$HOST_CODENAME" != "$SUITE" ]; then
    log "宿主代号(${HOST_CODENAME:-unknown}) != $SUITE，拉取目标发行版 keyring"
    KEYRING=$(bash "$HERE/scripts/fetch-keyring.sh")
    export KEYRING
    [ -s "$KEYRING" ] || die "keyring 拉取失败"
  fi
fi

# ---------- 1. rootfs ----------
log "1/3 构建最小 rootfs（mmdebstrap，无 snapd / 无 node / 无 docker）"
bash "$HERE/scripts/10-rootfs.sh"

# ---------- 2. 磁盘镜像 ----------
log "2/3 组盘 + GRUB 双启动 + 转 qcow2"
bash "$HERE/scripts/20-image.sh"

# ---------- 3. 校验 ----------
log "3/3 校验产物"
bash "$HERE/scripts/30-verify.sh"

ok "完成：$OUT_DIR/$IMAGE_NAME.qcow2"
