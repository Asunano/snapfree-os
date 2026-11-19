#!/usr/bin/env bash
# ============================================================
#  snapfree-os 装机自检 v2（只读，不改系统）
#  验证用 snapfree-os 镜像 + reinstall 装出来的机器是否正常
#  用法：
#    sudo bash snapfree-check.sh                 # 常规自检
#    sudo bash snapfree-check.sh --deep          # 额外跑 apt-get update
#    sudo bash snapfree-check.sh --expect-tz=Asia/Shanghai
#  退出码：0 无 FAIL；1 存在 FAIL
# ============================================================
set -uo pipefail

DEEP=0
EXPECT_TZ="Asia/Shanghai"
for a in "$@"; do
  case "$a" in
    --deep) DEEP=1 ;;
    --expect-tz=*) EXPECT_TZ="${a#*=}" ;;
    -h|--help) sed -n '1,12p' "$0"; exit 0 ;;
  esac
done

if [ -t 1 ]; then
  C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_B=$'\e[36m'; C_0=$'\e[0m'
else
  C_G=; C_Y=; C_R=; C_B=; C_0=
fi

PASS=0; WARN=0; FAIL=0
ok(){   printf '  %s[ OK ]%s %s\n' "$C_G" "$C_0" "$*"; PASS=$((PASS+1)); }
warn(){ printf '  %s[WARN]%s %s\n' "$C_Y" "$C_0" "$*"; WARN=$((WARN+1)); }
bad(){  printf '  %s[FAIL]%s %s\n' "$C_R" "$C_0" "$*"; FAIL=$((FAIL+1)); }
info(){ printf '  %s[INFO]%s %s\n' "$C_B" "$C_0" "$*"; }
sec(){  printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
have(){ command -v "$1" >/dev/null 2>&1; }
pkg_installed(){ dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null | grep -q '^installed$'; }
unit_file_exists(){
  for d in /etc/systemd/system /run/systemd/system /usr/local/lib/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
    [ -e "$d/$1" ] && return 0
  done
  return 1
}
# 单元或配套 socket 任一为 enabled 即视为已设为开机自启
enabled_any(){
  local u st
  for u in "$@"; do
    st=$(systemctl is-enabled "$u" 2>/dev/null)
    case "$st" in enabled|enabled-runtime) return 0 ;; esac
  done
  return 1
}
active_any(){
  local u
  for u in "$@"; do
    systemctl is-active "$u" >/dev/null 2>&1 && return 0
  done
  return 1
}

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo bash $0" >&2
  exit 2
fi

# ---------------------------------------------------------------- 1 系统
sec "1. 系统身份"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  info "发行版：${PRETTY_NAME:-未知}  代号：${VERSION_CODENAME:-?}"
  case "${ID:-}:${VERSION_CODENAME:-}" in
    ubuntu:resolute)  ok "确认为 Ubuntu 26.04 LTS（resolute）" ;;
    ubuntu:noble)     ok "确认为 Ubuntu 24.04 LTS（noble）" ;;
    debian:trixie)    ok "确认为 Debian 13（trixie）" ;;
    debian:bookworm)  ok "确认为 Debian 12（bookworm）" ;;
    *)                warn "非预期发行版/代号：${ID:-?}:${VERSION_CODENAME:-?}（自己改的就忽略）" ;;
  esac
else
  bad "缺 /etc/os-release"
fi
info "内核：$(uname -r)  架构：$(uname -m)  主机名：$(hostname)"
info "运行时长：$(uptime -p 2>/dev/null | sed 's/up //')  启动于：$(uptime -s 2>/dev/null)"
systemd-detect-virt >/dev/null 2>&1 && info "虚拟化：$(systemd-detect-virt)"
[ -r /proc/cmdline ] && info "内核参数：$(cut -c1-170 /proc/cmdline)"

# ---------------------------------------------------------------- 2 snap
sec "2. snap 是否真的没有（本镜像的核心承诺）"
pkg_installed snapd && bad "snapd 被装进来了" || ok "snapd 未安装"
[ -d /snap ] && bad "/snap 目录存在" || ok "无 /snap 目录"
have snap && bad "snap 命令存在：$(command -v snap)" || ok "无 snap 命令"
if [ -f /etc/apt/preferences.d/nosnap.pref ]; then
  info "存在 nosnap.pref（阻止 apt 拉入 snapd，属正常配置）"
fi

# ---------------------------------------------------------------- 3 纯净度
sec "3. 不该预装的软件（纯净度）"
UNWANTED="docker-ce docker.io nodejs npm nginx apache2 php-fpm mysql-server mariadb-server postgresql redis-server plymouth gnome-shell ubuntu-desktop linux-firmware snapd"
FOUND_UNWANTED=""
for p in $UNWANTED; do
  pkg_installed "$p" && FOUND_UNWANTED="$FOUND_UNWANTED $p"
done
if [ -n "$FOUND_UNWANTED" ]; then
  warn "存在以下软件（自己装的忽略）：$FOUND_UNWANTED"
else
  ok "docker / node / nginx / php / db / 桌面 / linux-firmware 均未预装"
fi
have docker && warn "docker 命令可用（自己装的？）"
have node && warn "node 命令可用（自己装的？）"

# ---------------------------------------------------------------- 4 基础软件
sec "4. 必须存在的基础组件"
MISSING=""
for p in openssh-server curl wget ca-certificates systemd sudo less; do
  pkg_installed "$p" || MISSING="$MISSING $p"
done
[ -n "$MISSING" ] && bad "缺少包：$MISSING" || ok "openssh-server / curl / wget / ca-certificates / sudo 均在"
for b in curl wget ssh sshd systemctl ip ss df; do
  have "$b" || bad "命令缺失：$b"
done
# networkd 以「单元是否存在 + 是否在跑」判定，避免包名拆分导致的误报
if unit_file_exists systemd-networkd.service; then
  if active_any systemd-networkd.service; then
    ok "systemd-networkd 单元存在且运行中"
  else
    warn "systemd-networkd 单元存在但未运行（若用 netplan 其它渲染器可忽略）"
  fi
  OWNER=$(dpkg -S /usr/lib/systemd/system/systemd-networkd.service 2>/dev/null | head -1 | cut -d: -f1)
  [ -n "$OWNER" ] && info "networkd 单元由包 $OWNER 提供"
else
  warn "未发现 systemd-networkd 单元（网络可能由 NetworkManager 接管）"
fi
pkg_installed qemu-guest-agent && ok "qemu-guest-agent 已安装" || warn "qemu-guest-agent 未安装（KVM/云主机建议装，物理机可忽略）"

# ---------------------------------------------------------------- 5 netplan
sec "5. 网络配置（本镜像最容易出事的地方）"
NP_FILES=$(ls /etc/netplan/*.yaml 2>/dev/null | wc -l)
if [ "$NP_FILES" -eq 0 ]; then
  info "无 netplan 配置，由 systemd-networkd/其它渲染器接管"
elif [ "$NP_FILES" -eq 1 ]; then
  ok "netplan 只有 1 份：$(ls /etc/netplan/*.yaml 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')"
else
  bad "netplan 有 $NP_FILES 份（$(ls /etc/netplan/*.yaml 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')）——同一网卡重复定义会让整份配置失效"
fi
[ -e /etc/netplan/10-image.yaml ] \
  && bad "镜像自带 10-image.yaml 仍在（与安装器生成的 50-cloud-init.yaml 冲突）" \
  || ok "无镜像自带 netplan 兜底（10-image.yaml 已移除）"
if have netplan; then
  if netplan generate >/dev/null 2>&1; then
    ok "netplan generate 无报错"
  else
    bad "netplan generate 报错：$(netplan generate 2>&1 | head -2 | tr '\n' ' ')"
  fi
fi
[ -f /etc/systemd/network/99-fallback-dhcp.network ] \
  && ok "systemd-networkd 兜底配置存在" \
  || info "无 networkd 兜底配置（纯 netplan 场景正常）"
RENDERER=$(grep -rhoE 'renderer: *[a-zA-Z]+' /etc/netplan/*.yaml 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ' ')
[ -n "$RENDERER" ] && info "netplan renderer：$RENDERER"

# ---------------------------------------------------------------- 6 连通性
sec "6. 实际网络连通性"
IPS=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2"="$4}' | tr '\n' ' ')
[ -n "$IPS" ] && ok "IPv4 地址：$IPS" || bad "没有全局 IPv4 地址"
GW=$(ip -4 route show default 2>/dev/null | awk '/default/{print $3; exit}')
[ -n "$GW" ] && ok "默认网关：$GW" || bad "没有默认路由（ping 不通/SSH 连不上的根因）"
DEFAULT_IF=$(ip -4 route show default 2>/dev/null | awk '/default/{print $5; exit}')
if [ -n "$DEFAULT_IF" ]; then
  info "出口网卡：$DEFAULT_IF  状态：$(cat "/sys/class/net/$DEFAULT_IF/operstate" 2>/dev/null)  MTU：$(cat "/sys/class/net/$DEFAULT_IF/mtu" 2>/dev/null)"
  [ "$(cat "/sys/class/net/$DEFAULT_IF/operstate" 2>/dev/null)" = "up" ] || bad "网卡 $DEFAULT_IF 未处于 up"
fi
if [ -n "$GW" ] && ping -c2 -W2 "$GW" >/dev/null 2>&1; then
  ok "网关 ICMP 可达"
else
  warn "网关 ICMP 不通（云厂商常封 ICMP，继续看 TCP）"
fi
if have curl; then
  curl -fsS -m 8 -o /dev/null https://mirrors.aliyun.com/ 2>/dev/null \
    && ok "出站 HTTPS(443) 正常" || bad "出站 HTTPS(443) 不通（DNS 或安全组）"
  curl -fsS -m 8 -o /dev/null https://github.com/ 2>/dev/null \
    && ok "出站到 github.com 正常" || warn "github.com 不通（国内常见）"
fi
have getent && { getent hosts mirrors.aliyun.com >/dev/null 2>&1 && ok "DNS 解析正常" || bad "DNS 解析失败"; }
info "resolv.conf → $(readlink -f /etc/resolv.conf 2>/dev/null || echo 缺失)  DNS：$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"
if have ss; then
  info "监听端口：$(ss -H -ltn 2>/dev/null | awk '{print $4}' | sed 's/.*:/:/' | sort -u | tr '\n' ' ')"
  ss -H -ltn 2>/dev/null | grep -q ':22 ' && ok "SSH(22) 在监听" || bad "SSH 未监听 22 端口"
fi

# ---------------------------------------------------------------- 7 SSH
sec "7. SSH 服务与登录方式"
if /usr/sbin/sshd -t >/dev/null 2>&1 || sshd -t >/dev/null 2>&1; then
  ok "sshd 配置语法校验通过"
  if SSHD_T=$(/usr/sbin/sshd -T 2>/dev/null || sshd -T 2>/dev/null); then
    PA=$(echo "$SSHD_T" | awk '/^passwordauthentication/{print $2}')
    RK=$(echo "$SSHD_T" | awk '/^permitrootlogin/{print $2}')
    PKD=$(echo "$SSHD_T" | awk '/^pubkeyauthentication/{print $2}')
    info "生效配置：PasswordAuthentication=$PA  PubkeyAuthentication=$PKD  PermitRootLogin=$RK  Port=$(echo "$SSHD_T" | awk '/^port /{print $2; exit}')"
    [ "$PA" = "yes" ] && warn "允许密码登录（公网机器建议改密钥，或装 fail2ban）" || ok "密码登录已禁用（仅密钥）"
    [ "$RK" = "yes" ] && warn "允许 root 直接登录（建议 PermitRootLogin no，用普通用户 sudo）" || ok "root 直接登录已限制（$RK）"
  else
    bad "sshd -T 执行失败，读不到生效配置"
  fi
else
  bad "sshd 配置有语法错误：$(/usr/sbin/sshd -t 2>&1 | head -2 | tr '\n' ' ')"
fi
ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 && ok "SSH 主机密钥存在" || bad "缺 SSH 主机密钥"
DEPLOY_KEYS=$(find /home -maxdepth 3 -name authorized_keys 2>/dev/null | wc -l)
[ "$DEPLOY_KEYS" -gt 0 ] && ok "已部署 $DEPLOY_KEYS 份 authorized_keys（密钥登录可用）" || warn "无 authorized_keys，只能密码登录"

# ---------------------------------------------------------------- 8 防火墙
sec "8. 防火墙/过滤规则（本镜像默认不设防）"
if pkg_installed ufw; then
  info "ufw 已安装：$(ufw status 2>/dev/null | head -1)"
  ufw status 2>/dev/null | grep -q "Status: active" && warn "ufw 处于启用状态（自己开的？）"
else
  ok "未安装 ufw"
fi
if have nft; then
  NFT=$(nft list ruleset 2>/dev/null | grep -c .)
  [ "${NFT:-0}" -eq 0 ] && ok "nftables 规则为空" || warn "nftables 有 ${NFT} 行规则（docker 等会写入）"
fi
IPT=$(iptables -S 2>/dev/null | grep -vc -- '-N ' || true)
[ "${IPT:-0}" -le 6 ] && ok "iptables 仅默认规则（未做拦截）" || warn "iptables 有 ${IPT} 条规则（装过 docker 属正常）"

# ---------------------------------------------------------------- 9 磁盘
sec "9. 磁盘 / 分区 / 文件系统"
ROOTDEV=$(findmnt -no SOURCE / 2>/dev/null)
info "根设备：${ROOTDEV:-?}"
df -h / | tail -1 | awk '{printf "  根分区：总量 %s 已用 %s 可用 %s (%s)\n", $2,$3,$4,$5}'
USE_PCT=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
[ "${USE_PCT:-0}" -ge 90 ] && bad "根分区使用率 ${USE_PCT}%（快满了）" || ok "根分区使用率 ${USE_PCT}%"

DISK=$(lsblk -no NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1; exit}')
if [ -n "$DISK" ]; then
  DISK_SZ=$(blockdev --getsize64 "$DISK" 2>/dev/null || echo 0)
  LAST_END=$(lsblk -bno NAME,START,SIZE "$DISK" 2>/dev/null | awk 'NF==3 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {e=$2+$3; if(e>m)m=e} END{print m+0}')
  info "整盘：$DISK  $(( DISK_SZ / 1073741824 )) GiB  最后分区结束于 $(( LAST_END / 1073741824 )) GiB"
  GAP=$(( DISK_SZ - LAST_END ))
  if [ "$GAP" -lt 33554432 ]; then
    ok "分区已用到盘尾（安装器 resize 生效，尾部余 ${GAP} 字节）"
  else
    warn "盘尾还有约 $(( GAP / 1073741824 )) GiB 未分配（安装器 resize 可能没跑完）"
  fi
else
  info "未识别到整盘设备（LVM/特殊布局请自行核对）"
fi

if [ -n "$ROOTDEV" ] && [ -b "$ROOTDEV" ]; then
  FS=$(blkid -o value -s TYPE "$ROOTDEV" 2>/dev/null)
  info "根文件系统：${FS:-未知}"
  if [ "$FS" = "ext4" ]; then
    ST=$(dumpe2fs -h "$ROOTDEV" 2>/dev/null | awk -F': *' '/^Filesystem state/{print $2; exit}')
    [ -z "$ST" ] && ST=$(tune2fs -l "$ROOTDEV" 2>/dev/null | awk -F': *' '/^Filesystem state/{print $2; exit}')
    if [ -n "$ST" ] && echo "$ST" | grep -q clean; then
      ok "ext4 状态 clean"
    else
      warn "ext4 状态为「${ST:-读不到}」（多为装机时未干净卸载，可稍后 fsck 确认）"
    fi
    ERRORS_BEHAVIOR=$(dumpe2fs -h "$ROOTDEV" 2>/dev/null | awk -F': *' '/^Errors behavior/{print $2; exit}')
    [ -n "$ERRORS_BEHAVIOR" ] && info "ext4 错误策略：$ERRORS_BEHAVIOR"
  fi
fi

if [ -f /etc/fstab ]; then
  awk '$1 ~ /^UUID=/ {print $1, $2}' /etc/fstab | while read -r u m; do
    blkid -U "${u#UUID=}" >/dev/null 2>&1 || echo "        [FAIL] fstab UUID=${u#UUID=} 找不到设备（挂载点 $m）"
  done
  ok "fstab 条目 $(grep -cvE '^[[:space:]]*(#|$)' /etc/fstab) 条"
fi
systemctl is-enabled fstrim.timer >/dev/null 2>&1 && ok "fstrim.timer 已启用（定期 TRIM）" || warn "fstrim.timer 未启用"

# ---------------------------------------------------------------- 10 内存
sec "10. 内存 / swap"
info "内存：总计 $(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)，可用 $(awk '/MemAvailable/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
SWAP=$(swapon --show=SIZE --noheadings 2>/dev/null | tr -d ' ')
if [ -n "$SWAP" ]; then
  ok "swap：$SWAP"
else
  warn "无 swap（小内存机器跑编译/容器容易 OOM，建议加 1–2G swapfile）"
fi
info "OOM 历史（本次启动）：$(dmesg 2>/dev/null | grep -ci 'out of memory' || true) 次"

# ---------------------------------------------------------------- 11 时间
sec "11. 时间与时区"
TZ=$(timedatectl show -p Timezone --value 2>/dev/null)
info "时区：${TZ:-未知}  当前：$(date '+%F %T %Z')  期望：$EXPECT_TZ"
[ "$TZ" = "$EXPECT_TZ" ] && ok "时区符合预期" || warn "时区不是 $EXPECT_TZ（日志时间会差 8 小时）"
timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q '^yes' \
  && ok "NTP 已同步" || warn "NTP 未同步（时间漂移会影响 TLS/证书）"
enabled_any systemd-timesyncd && ok "systemd-timesyncd 已启用" || warn "systemd-timesyncd 未启用"
enabled_any chrony chronyd && ok "chrony 已启用" || true

# ---------------------------------------------------------------- 12 systemd
sec "12. systemd 单元状态"
STATE=$(systemctl is-system-running 2>/dev/null)
[ "$STATE" = "running" ] && ok "systemd 状态 running" || warn "systemd 状态 ${STATE:-未知}"
FAILED_UNITS=$(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
[ -n "$FAILED_UNITS" ] && bad "失败单元：$FAILED_UNITS" || ok "无失败 unit"
if enabled_any ssh.service ssh.socket; then
  ok "ssh 已设为开机自启（$(systemctl is-enabled ssh.service 2>/dev/null || echo socket)）"
else
  bad "ssh 未设为开机自启（重启后连不上的风险）→ systemctl enable ssh"
fi
active_any ssh.service ssh.socket && ok "ssh 当前运行中" || bad "ssh 当前未运行"
if unit_file_exists systemd-networkd.service; then
  enabled_any systemd-networkd.service && ok "systemd-networkd 开机自启" || warn "systemd-networkd 未开机自启"
fi
if unit_file_exists qemu-guest-agent.service; then
  enabled_any qemu-guest-agent.service && active_any qemu-guest-agent.service \
    && ok "qemu-guest-agent 已启用并在运行" || warn "qemu-guest-agent 未正常启用/运行"
fi
# 镜像里禁掉的定时器有没有被 preset 复活
for t in apt-daily.timer apt-daily-upgrade.timer motd-news.timer; do
  if unit_file_exists "$t"; then
    st=$(systemctl is-enabled "$t" 2>/dev/null)
    case "$st" in
      enabled) warn "$t 被启用了（镜像本意是关掉，如需纯净可 mask）" ;;
      *) info "$t 状态：${st:-未启用}" ;;
    esac
  fi
done

# ---------------------------------------------------------------- 13 日志
sec "13. 本次启动的错误日志"
if have journalctl; then
  ERR_N=$(journalctl -b -p err --no-pager 2>/dev/null | grep -c . || true)
  if [ "${ERR_N:-0}" -le 3 ]; then
    ok "本次启动 error 级日志 ${ERR_N} 行"
  else
    warn "本次启动 error 级日志 ${ERR_N} 行（公网机器常见被扫的 kex 报错），抽样："
    journalctl -b -p err --no-pager 2>/dev/null | tail -3 | sed 's/^/         /'
  fi
  KEX=$(journalctl -b --no-pager 2>/dev/null | grep -c 'kex_exchange_identification' || true)
  [ "${KEX:-0}" -gt 0 ] && info "SSH 被外网扫描 $KEX 次（正常现象，说明机器暴露在公网）"
fi
FW_ERR=$(dmesg 2>/dev/null | grep -ci 'failed to load firmware' || true)
[ "${FW_ERR:-0}" -gt 0 ] \
  && warn "dmesg 有 ${FW_ERR} 条固件加载失败（KVM/云主机正常，物理机才需要 linux-firmware）" \
  || ok "无固件加载失败（与不装 linux-firmware 一致）"

# ---------------------------------------------------------------- 14 cloud-init
sec "14. cloud-init 残留（装完应被中和）"
if pkg_installed cloud-init; then
  info "cloud-init 已安装（安装器用它生成网络配置，正常）"
  if [ -e /etc/cloud/cloud-init.disabled ]; then
    ok "cloud-init 已禁用（重启不会重写网络）"
  else
    st=$(systemctl is-enabled cloud-init 2>/dev/null)
    [ "$st" = "enabled" ] && warn "cloud-init 仍 enabled，重启可能覆盖网络（建议 disable）" || ok "cloud-init 未开机自启（${st:-未启用}）"
  fi
else
  ok "未安装 cloud-init"
fi

# ---------------------------------------------------------------- 15 apt
sec "15. apt 源与包状态"
SRC=""
for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/debian.sources; do
  [ -r "$f" ] && { SRC="$f"; break; }
done
if [ -n "$SRC" ]; then
  URIS=$(awk -F': ' '/^URIs:/{print $2}' "$SRC" | tr '\n' ' ')
  info "镜像源（$SRC）：${URIS:-?}"
  echo "$URIS" | grep -qE 'mirrors\.aliyun\.com|mirrors\.ustc\.edu\.cn|tuna\.tsinghua' && ok "使用国内镜像源" || info "非国内源（自己换过就忽略）"
  awk '/^URIs:/{u=$2} /^Suites:/{print u" "$2}' "$SRC" | grep -q 'security' && info "已配置 security suite"
else
  warn "缺 deb822 源文件（ubuntu.sources / debian.sources，源可能被手动改过）"
fi
apt-get check -q >/dev/null 2>&1 && ok "apt 依赖关系一致" || bad "apt-get check 报依赖破损"
broken=$(dpkg -C 2>/dev/null | grep -c . || true)
[ "${broken:-0}" -eq 0 ] && ok "dpkg 无半安装状态的包" || warn "dpkg 有破损包，跑 dpkg --configure -a"
[ -f /etc/apt/apt.conf.d/20auto-upgrades ] && info "存在 20auto-upgrades（会自动跑 apt update）"
if [ "$DEEP" -eq 1 ]; then
  info "deep：执行 apt-get update"
  apt-get update -qq 2>/dev/null && ok "apt-get update 成功（源可用）" || bad "apt-get update 失败（源不可达或 key 失效）"
fi

# ---------------------------------------------------------------- 16 账号
sec "16. 账号与 sudo"
USERS=$(awk -F: '$3>=1000 && $7 !~ /(nologin|false)/ {print $1}' /etc/passwd | tr '\n' ' ')
info "普通登录用户：${USERS:-无}"
for u in $USERS; do
  id -nG "$u" 2>/dev/null | grep -qw sudo && ok "$u 在 sudo 组" || warn "$u 不在 sudo 组"
done
[ -f /etc/sudoers.d/90-cloud-init-users ] && warn "存在 cloud-init 生成的 sudoers（安装器遗留，一般无害）"
[ -f /root/.ssh/authorized_keys ] && info "root 也有 authorized_keys（配合 PermitRootLogin 一起看）"

# ---------------------------------------------------------------- 17 其他
sec "17. 其他系统参数"
grep -qs 'net.ifnames=0' /proc/cmdline && ok "网卡命名已固定为传统名" || warn "无 net.ifnames=0（可预测命名通常也正常）"
info "网卡：$(ls /sys/class/net | grep -v lo | tr '\n' ' ')  已建立 TCP 连接：$(ss -H -tn state established 2>/dev/null | wc -l)"
info "熵池：$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null) bit"
FD=$(ulimit -n)
if [ "$FD" -ge 4096 ]; then ok "句柄上限 $FD"; else warn "句柄上限仅 $FD（并发高的服务需要调高到 65536）"; fi
info "TCP 拥塞控制：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)  文件最大打开：$(sysctl -n fs.file-max 2>/dev/null)"

# ---------------------------------------------------------------- 汇总
printf '\n%s== 汇总 ==%s\n' "$C_B" "$C_0"
printf '  通过 %s%d%s  警告 %s%d%s  失败 %s%d%s\n' "$C_G" "$PASS" "$C_0" "$C_Y" "$WARN" "$C_0" "$C_R" "$FAIL" "$C_0"
if [ "$FAIL" -gt 0 ]; then
  echo "  结论：存在需要处理的失败项（见上面 [FAIL] 行）"
  exit 1
fi
echo "  结论：没有发现致命问题"
[ "$WARN" -gt 0 ] && echo "        警告项多为环境差异或安全加固建议，按提示判断"
exit 0
