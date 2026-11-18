#!/usr/bin/env bash
# rootfs.tar -> GPT 磁盘（bios-boot + ESP + ext4 root）-> GRUB(BIOS+UEFI) -> qcow2
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/conf.sh"

ROOTFS_TAR="$WORK_DIR/rootfs.tar"
RAW="$WORK_DIR/image.raw"
MNT="$WORK_DIR/mnt"
QCOW2="$OUT_DIR/$IMAGE_NAME.qcow2"

log(){ printf '  · %s\n' "$*"; }
die(){ printf '[!] %s\n' "$*" >&2; exit 1; }

[ -s "$ROOTFS_TAR" ] || die "缺 $ROOTFS_TAR"
command -v qemu-img >/dev/null || die "缺 qemu-img（apt install qemu-utils）"
mkdir -p "$MNT" "$OUT_DIR"

LOOP=""
cleanup(){
  set +e
  umount -R "$MNT" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  true
}
trap cleanup EXIT

# ---------- 分区表 ----------
ESP_END=$((2 + ESP_SIZE_MIB))
log "创建 ${IMG_SIZE} 磁盘：1-2MiB bios-boot | 2-${ESP_END}MiB ESP | ${ESP_END}MiB-100% root"
rm -f "$RAW"
truncate -s "$IMG_SIZE" "$RAW"
parted -s "$RAW" mklabel gpt
parted -s "$RAW" mkpart bios-boot ext4 1MiB 2MiB
parted -s "$RAW" set 1 bios_grub on
parted -s "$RAW" mkpart EFI fat32 2MiB "${ESP_END}MiB"
parted -s "$RAW" set 2 esp on
parted -s "$RAW" mkpart root ext4 "${ESP_END}MiB" 100%

LOOP=$(losetup --find --show --partscan "$RAW")
for _ in $(seq 1 30); do [ -b "${LOOP}p3" ] && break; sleep 0.2; done
[ -b "${LOOP}p3" ] || die "分区设备没出现：${LOOP}p3"

# ---------- 文件系统 ----------
mkfs.vfat -F 32 -n EFI "${LOOP}p2" >/dev/null
mkfs.ext4 -q -F -L ubuntu-root -m 0 \
  -E lazy_itable_init=0,lazy_journal_init=0 "${LOOP}p3"

# ---------- 铺 rootfs ----------
mount "${LOOP}p3" "$MNT"
log "解包 rootfs"
tar -xpf "$ROOTFS_TAR" --numeric-owner -C "$MNT"
mkdir -p "$MNT/boot/efi"
mount "${LOOP}p2" "$MNT/boot/efi"

ROOT_UUID=$(blkid -s UUID -o value "${LOOP}p3")
ESP_UUID=$(blkid -s UUID -o value "${LOOP}p2")
cat > "$MNT/etc/fstab" <<EOF
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$ROOT_UUID /          ext4  discard,noatime,errors=remount-ro  0 1
UUID=$ESP_UUID  /boot/efi  vfat  umask=0077,shortname=lower          0 1
EOF
log "fstab: root=$ROOT_UUID esp=$ESP_UUID"

# ---------- 伪文件系统 ----------
for d in dev dev/pts proc sys run; do
  mkdir -p "$MNT/$d"
  mount --bind "/$d" "$MNT/$d"
done
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || true

# ---------- 引导 ----------
log "安装 GRUB（UEFI: ubuntu + removable fallback / BIOS: bios_grub）"
chroot "$MNT" /usr/bin/env \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  LOOPDEV="$LOOP" GRUB_ID="$GRUB_ID" \
  bash -eu -o pipefail <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive

# 镜像里只装了 grub-*-bin，没有 metapackage，/boot/grub 需自建
mkdir -p /boot/grub
grub-mkconfig -o /boot/grub/grub.cfg

# UEFI：正常条目（--no-nvram 不写虚拟机 NVRAM）+ 固件兜底路径
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
             --bootloader-id="$GRUB_ID" --no-nvram
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable

# BIOS：写进 GPT bios-boot 分区
grub-install --target=i386-pc --boot-directory=/boot --recheck "$LOOPDEV"

update-initramfs -u -k all
CHROOT

# 把构建机的 resolv.conf 换回镜像自己的方案
if [ -e "$MNT/lib/systemd/system/systemd-resolved.service" ] || \
   [ -e "$MNT/usr/lib/systemd/system/systemd-resolved.service" ]; then
  ln -sf ../run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"
else
  printf 'nameserver 223.5.5.5\nnameserver 1.1.1.1\n' > "$MNT/etc/resolv.conf"
fi

# ---------- 收尾 ----------
umount -R "$MNT"
losetup -d "$LOOP"; LOOP=""

# ---------- 转 qcow2 ----------
if [ "$QCOW2_COMPRESS" = "1" ]; then
  log "转 qcow2（压缩）"
  qemu-img convert -f raw -O qcow2 -c "$RAW" "$QCOW2"
else
  qemu-img convert -f raw -O qcow2 "$RAW" "$QCOW2"
fi
[ -s "$QCOW2" ] || die "qcow2 生成失败"
rm -f "$RAW"

sha256sum "$QCOW2" | sed "s|$OUT_DIR/||" > "$QCOW2.sha256"
log "qcow2：$(du -h "$QCOW2" | cut -f1)  虚拟大小：$(qemu-img info --output=json "$QCOW2" | grep -o '"virtual-size": [0-9]*' | awk '{print $2/1073741824"G"}')"
