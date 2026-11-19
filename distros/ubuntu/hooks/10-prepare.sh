#!/usr/bin/env bash
# mmdebstrap customize hook：在装完包的 chroot 里做系统配置
# $1 = rootfs 目录
set -Eeuo pipefail

ROOT="${1:?需要 rootfs 路径}"
KIT_DIR="${KIT_DIR:?KIT_DIR 未导出}"
export DEBIAN_FRONTEND=noninteractive

log(){ printf '  · %s\n' "$*"; }

# ---------- 伪文件系统（mmdebstrap 通常已挂，缺了再补） ----------
MOUNTED=()
on_exit(){ set +e; for d in "${MOUNTED[@]:-}"; do [ -n "$d" ] && mountpoint -q "$ROOT/$d" && umount -R "$ROOT/$d"; done; }
trap on_exit EXIT
ensure(){ [ -e "$ROOT/$1" ] || mkdir -p "$ROOT/$1"; if ! mountpoint -q "$ROOT/$1"; then mount --bind "/$1" "$ROOT/$1" && MOUNTED+=("$1"); fi; }
for d in dev dev/pts proc sys; do ensure "$d"; done

# ---------- 静态文件 ----------
cp -a "$KIT_DIR/files/." "$ROOT/"
chmod 0755 "$ROOT/usr/local/bin/apt-mirror"

# ---------- 主机名 / 时区 ----------
printf '%s\n' "$IMAGE_HOSTNAME" > "$ROOT/etc/hostname"
sed -i "s/__HOSTNAME__/$IMAGE_HOSTNAME/g" "$ROOT/etc/hosts"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$ROOT/etc/localtime"
printf '%s\n' "$TIMEZONE" > "$ROOT/etc/timezone"
sed -i "s/__USER_NAME__/$USER_NAME/g" "$ROOT/etc/cloud/cloud.cfg.d/99-image.cfg"

# ---------- 兜底网络（不写 netplan）----------
# reinstall 装机会生成 /etc/netplan/50-cloud-init.yaml；
# 镜像再放一份 netplan 会让同一网卡被定义两次，netplan 直接报错，
# 整份网络配置都不生效（表现为装完 ping 不通、SSH 连不上）。
# 所以这里只放 systemd-networkd 的兜底配置，能与 netplan 共存。
NC="$ROOT/etc/systemd/network/99-fallback-dhcp.network"
mkdir -p "$(dirname "$NC")"
if [ -n "${DNS_ADDRS:-}" ]; then
  sed -i "s|__DNS_ADDRS__|$DNS_ADDRS|" "$NC"
  log "兜底 DNS：$DNS_ADDRS"
else
  sed -i "/^DNS=/d" "$NC"
  log "兜底 DNS 沿用 DHCP 下发"
fi

# ---------- apt：写入镜像源（可与构建源不同）+ 关掉 snapd ----------
mkdir -p "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/preferences.d"
cat > "$ROOT/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $GUEST_MIRROR
Suites: $SUITE $SUITE-updates $SUITE-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
rm -f "$ROOT/etc/apt/sources.list"
log "镜像内源：$GUEST_MIRROR（可用 apt-mirror 切换）"

if [ ! -f "$ROOT/usr/share/keyrings/ubuntu-archive-keyring.gpg" ]; then
  log "warn: 缺 ubuntu-archive-keyring.gpg，镜像内 apt 可能报 NO_PUBKEY"
fi

# 构建期给 chroot 一个能用的 DNS
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true

# ---------- systemd 单元 ----------
# 构建机（容器）里通常没有 systemd，所以进 chroot 用离线模式操作
syscfg(){ chroot "$ROOT" systemctl --root=/ "$@" >/dev/null 2>&1 || log "warn: systemctl $* 失败"; }
syscfg enable ssh.service systemd-networkd.service systemd-timesyncd.service
syscfg enable fstrim.timer logrotate.timer
syscfg set-default multi-user.target

# 服务器不需要后台自动跑 apt / motd 广告
syscfg disable apt-daily.timer apt-daily-upgrade.timer motd-news.timer
rm -f "$ROOT/etc/update-motd.d/10-help-text" \
      "$ROOT/etc/update-motd.d/50-motd-news" \
      "$ROOT/etc/update-motd.d/50-cloud-init" \
      "$ROOT/etc/update-motd.d/60-cloudimg-settings"
if [ -f "$ROOT/etc/default/motd-news" ]; then
  sed -i 's/^ENABLED=.*/ENABLED=0/' "$ROOT/etc/default/motd-news"
fi

RESOLVED_UNIT=""
for u in "$ROOT/lib/systemd/system/systemd-resolved.service" "$ROOT/usr/lib/systemd/system/systemd-resolved.service"; do
  if [ -e "$u" ]; then RESOLVED_UNIT="$u"; fi
done
if [ -n "$RESOLVED_UNIT" ]; then
  syscfg enable systemd-resolved.service
fi

if [ -e "$ROOT/lib/systemd/system/qemu-guest-agent.service" ] || \
   [ -e "$ROOT/usr/lib/systemd/system/qemu-guest-agent.service" ]; then
  syscfg enable qemu-guest-agent.service
fi

# ---------- Docker CE（官方源，不走 snap） ----------
if [ "$WITH_DOCKER" = "1" ]; then
  log "安装 Docker CE（download.docker.com / $SUITE）"
  chroot "$ROOT" bash -ec '
    set -e
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL --retry 3 https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
    gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg /tmp/docker.asc
    printf "deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n" \
      "$ARCH" "$SUITE" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-compose-plugin
    rm -f /tmp/docker.asc
  '
  syscfg enable docker.service containerd.service
fi

# ---------- 清掉误入的业务软件 / 桌面软件 ----------
if [ -s "$KIT_DIR/packages.remove" ]; then
  PURGE=""
  while read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    if chroot "$ROOT" dpkg-query -W -f='${db:Status-Status}' "$p" 2>/dev/null | grep -q installed; then
      PURGE="$PURGE $p"
    fi
  done < "$KIT_DIR/packages.remove"
  if [ -n "$PURGE" ]; then
    log "purge 黑名单命中：$PURGE"
    chroot "$ROOT" apt-get purge -y --auto-remove $PURGE >/dev/null
  else
    log "黑名单零命中（nginx/apache/php/db 本来就没进来）"
  fi
fi

# ---------- 用户 ----------
chroot "$ROOT" getent group sudo >/dev/null 2>&1 || chroot "$ROOT" groupadd --system sudo || true
if chroot "$ROOT" id -u "$USER_NAME" >/dev/null 2>&1; then
  log "用户 $USER_NAME 已存在，跳过创建"
else
  chroot "$ROOT" useradd -m -s /bin/bash -G sudo "$USER_NAME"
fi

if [ -n "$USER_PASSWORD" ]; then
  chroot "$ROOT" bash -ec "printf '%s:%s\\n' \"\$0\" \"\$1\" | chpasswd" "$USER_NAME" "$USER_PASSWORD"
  log "已设置 $USER_NAME 密码"
fi

# SSH：默认允许密码登录；没设密码时给出提示
if ! grep -qi '^PasswordAuthentication yes' "$ROOT/etc/ssh/sshd_config.d/10-image.conf"; then
  printf 'PasswordAuthentication yes\n' >> "$ROOT/etc/ssh/sshd_config.d/10-image.conf"
fi
if [ -z "$USER_PASSWORD" ]; then
  log "warn: 未设 USER_PASSWORD，$USER_NAME 没密码，密码登录不可用（密钥不限）"
fi

# ---------- 收尾：DNS ----------
if [ -n "$RESOLVED_UNIT" ]; then
  ln -sf ../run/systemd/resolve/stub-resolv.conf "$ROOT/etc/resolv.conf"
else
  printf 'nameserver %s\n' "${DNS_ADDRS%% *}" > "$ROOT/etc/resolv.conf"
  log "warn: 未发现 systemd-resolved，已写入静态 DNS"
fi

# ---------- 断言 ----------
if chroot "$ROOT" dpkg-query -W -f='${db:Status-Status}\n' snapd >/dev/null 2>&1; then
  printf '[!] snapd 被意外安装进来了\n' >&2; exit 1
fi
if [ -e "$ROOT/snap" ]; then
  printf '[!] rootfs 里出现了 /snap\n' >&2; exit 1
fi
if [ -e "$ROOT/etc/netplan/10-image.yaml" ]; then
  printf '[!] 镜像里不应再有 netplan 兜底文件（会与安装器生成的 50-cloud-init.yaml 冲突）\n' >&2; exit 1
fi
if [ ! -e "$ROOT/etc/systemd/network/99-fallback-dhcp.network" ]; then
  printf '[!] 缺兜底网络配置\n' >&2; exit 1
fi
log "校验通过：无 snapd，无 /snap，netplan 无重复定义，兜底网络就位"
