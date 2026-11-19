#!/usr/bin/env bash
# ============================================================
#  snapfree-os 装机自检（只读，不改系统）
#  用途：验证用 snapfree-os 镜像 + reinstall 装出来的机器是否正常
#  用法：
#    sudo bash snapfree-check.sh            # 常规自检
#    sudo bash snapfree-check.sh --deep     # 额外跑 apt update / dpkg -C
#  退出码：0 全部通过（可能含 WARN）；1 存在 FAIL
# ============================================================
set -uo pipefail

DEEP=0
[ "${1:-}" = "--deep" ] && DEEP=1

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

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：sudo bash $0" >&2
  exit 2
fi

# ---------------------------------------------------------------- 1 系统
sec "1. 系统身份"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  info "发行版：${PRETTY_NAME:-未知}  代号：${VERSION_CODENAME:-?}"
  case "${VERSION_CODENAME:-}" in
    resolute) ok "确认为 Ubuntu 26.04 LTS（resolute）" ;;
    noble)    ok "确认为 Ubuntu 24.04 LTS（noble）" ;;
    *)        warn "非预期的发行版代号：${VERSION_CODENAME:-?}（若是自己改的，忽略）" ;;
  esac
else
  bad "缺 /etc/os-release"
fi
info "内核：$(uname -r)  架构：$(uname -m)  主机名：$(hostname)"
info "运行时长：$(uptime -p 2>/dev/null | sed 's/up //')"
systemd-detect-virt >/dev/null 2>&1 && info "虚拟化：$(systemd-detect-virt)"
[ -r /proc/cmdline ] && info "内核参数：$(cut -c1-160 /proc/cmdline)"

# ---------------------------------------------------------------- 2 snap
sec "2. snap 是否真的没有（本镜像的核心承诺）"
if pkg_installed snapd; then bad "snapd 被装进来了（不该出现）"; else ok "snapd 未安装"; fi
if [ -d /snap ]; then bad "/snap 目录存在"; else ok "无 /snap 目录"; fi
if have snap; then bad "snap 命令存在：$(command -v snap)"; else ok "无 snap 命令"; fi
if grep -rqs 'snap' /etc/apt/preferences.d/ 2>/dev/null; then
  warn "检测到 apt 偏好里针对 snap 的条目（通常无害）"
fi

# ---------------------------------------------------------------- 3 不该有的软件
sec "3. 不该预装的软件（纯净度）"
UNWANTED="docker-ce docker.io nodejs npm nginx nginx-core apache2 php-fpm mysql-server mariadb-server postgresql redis-server plymouth gnome-shell ubuntu-desktop linux-firmware"
FOUND_UNWANTED=""
for p in $UNWANTED; do
  pkg_installed "$p" && FOUND_UNWANTED="$FOUND_UNWANTED $p"
done
if [ -n "$FOUND_UNWANTED" ]; then
  warn "存在以下软件（若你自己装的请忽略）：$FOUND_UNWANTED"
else
  ok "docker / node / nginx / php / db / 桌面 / linux-firmware 均未预装"
fi
have docker && warn "docker 命令可用（你自己装的？）"
have node && warn "node 命令可用（你自己装的？）"

# ---------------------------------------------------------------- 4 必须有的软件
sec "4. 必须存在的基础软件"
MISSING=""
for p in openssh-server curl wget ca-certificates systemd systemd-networkd sudo less; do
  pkg_installed "$p" || MISSING="$MISSING $p"
done
if [ -n "$MISSING" ]; then bad "缺少：$MISSING"; else ok "openssh-server / curl / wget / ca-certificates / networkd / sudo 均在"; fi
for b in curl wget ssh sshd systemctl ip ss df; do
  have "$b" || bad "命令缺失：$b"
done
pkg_installed qemu-guest-agent && ok "qemu-guest-agent 已安装" || warn "qemu-guest-agent 未安装（KVM/云主机建议装，物理机可忽略）"

# ---------------------------------------------------------------- 5 netplan / 网络配置
sec "5. 网络配置（本镜像最容易出事的地方）"
NP_FILES=$(ls /etc/netplan/*.yaml 2>/dev/null | wc -l)
if [ "$NP_FILES" -eq 0 ]; then
  info "无 netplan 配置文件，走 systemd-networkd 兜底"
elif [ "$NP_FILES" -eq 1 ]; then
  ok "netplan 只有 1 份配置：$(ls /etc/netplan/*.yaml 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')"
else
  bad "netplan 有 $NP_FILES 份配置（$(ls /etc/netplan/*.yaml 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')）——同一网卡被多次定义会让整份配置失效"
fi
if [ -e /etc/netplan/10-image.yaml ]; then
  bad "镜像自带的 /etc/netplan/10-image.yaml 还在（会和安装器生成的 50-cloud-init.yaml 冲突）"
else
  ok "无镜像自带 netplan 兜底文件 10-image.yaml"
fi
if have netplan; then
  if netplan generate >/dev/null 2>&1; then ok "netplan generate 无报错"; else bad "netplan generate 报错，配置有冲突：$(netplan generate 2>&1 | head -3 | tr '\n' ' ')"; fi
fi
if [ -f /etc/systemd/network/99-fallback-dhcp.network ]; then
  ok "systemd-networkd 兜底配置存在"
else
  warn "无 systemd-networkd 兜底配置（用的是纯 netplan 配置，也能正常工作）"
fi

# ---------------------------------------------------------------- 6 实际连通性
sec "6. 实际网络连通性"
IPS=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2"="$4}' | tr '\n' ' ')
if [ -n "$IPS" ]; then ok "IPv4 地址：$IPS"; else bad "没有全局 IPv4 地址"; fi
GW=$(ip -4 route show default 2>/dev/null | awk '/default/{print $3; exit}')
[ -n "$GW" ] && ok "默认网关：$GW" || bad "没有默认路由（这就是 ping 不通、SSH 连不上的根因）"
DEFAULT_IF=$(ip -4 route show default 2>/dev/null | awk '/default/{print $5; exit}')
if [ -n "$DEFAULT_IF" ]; then
  MTU=$(cat "/sys/class/net/$DEFAULT_IF/mtu" 2>/dev/null)
  STATE=$(cat "/sys/class/net/$DEFAULT_IF/operstate" 2>/dev/null)
  info "出口网卡：$DEFAULT_IF  状态：$STATE  MTU：$MTU"
  [ "$STATE" = "up" ] || bad "网卡 $DEFAULT_IF 状态为 $STATE"
fi

if [ -n "$GW" ] && ping -c2 -W2 "$GW" >/dev/null 2>&1; then
  ok "网关 ICMP 可达"
else
  warn "网关 ICMP 不通（云厂商常封 ICMP，不一定有问题，继续看 TCP）"
fi

if have curl; then
  if curl -fsS -m 8 -o /dev/null https://mirrors.aliyun.com/ 2>/dev/null; then
    ok "出站 HTTPS(443) 正常"
  else
    bad "出站 HTTPS(443) 不通：DNS 或安全组问题"
  fi
  if curl -fsS -m 8 -o /dev/null https://github.com/ 2>/dev/null; then
    ok "出站到 github.com 正常"
  else
    warn "github.com 不通（国内常见，装东西时用镜像/代理）"
  fi
fi

if have getent; then
  if getent hosts mirrors.aliyun.com >/dev/null 2>&1; then
    ok "DNS 解析正常（mirrors.aliyun.com）"
  else
    bad "DNS 解析失败：检查 /etc/resolv.conf 与 systemd-resolved"
  fi
fi
info "resolv.conf → $(readlink -f /etc/resolv.conf 2>/dev/null || echo 缺失)"
DNS_NS=$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
[ -n "$DNS_NS" ] && info "生效 DNS：$DNS_NS"

if have ss; then
  LISTEN=$(ss -H -ltn 2>/dev/null | awk '{print $4}' | sed 's/.*:/:/' | sort -u | tr '\n' ' ')
  info "监听端口：${LISTEN:-无}"
  ss -H -ltn 2>/dev/null | grep -q ':22 ' && ok "SSH(22) 在监听" || bad "SSH 未监听 22 端口"
fi

# ---------------------------------------------------------------- 7 SSH 与登录
sec "7. SSH 服务与登录方式"
if /usr/sbin/sshd -t >/dev/null 2>&1 || sshd -t >/dev/null 2>&1; then
  ok "sshd 配置语法校验通过"
else
  bad "sshd 配置有语法错误：$(/usr/sbin/sshd -t 2>&1 | head -3 | tr '\n' ' ')"
fi
if SSHD_T=$(/usr/sbin/sshd -T 2>/dev/null || sshd -T 2>/dev/null); then
  PA=$(echo "$SSHD_T" | awk '/^passwordauthentication/{print $2}')
  RK=$(echo "$SSHD_T" | awk '/^permitrootlogin/{print $2}')
  PKD=$(echo "$SSHD_T" | awk '/^pubkeyauthentication/{print $2}')
  info "生效配置：PasswordAuthentication=$PA  PubkeyAuthentication=$PKD  PermitRootLogin=$RK"
  [ "$PA" = "yes" ] || warn "密码登录被禁用（要用密码登录就改 /etc/ssh/sshd_config.d/10-image.conf）"
  [ "$RK" = "no" ] && info "root 禁止直接登录（正常，用普通用户 sudo）"
else
  bad "sshd -T 执行失败，无法读取生效配置"
fi
if ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then ok "SSH 主机密钥存在"; else bad "缺 SSH 主机密钥"; fi
DEPLOY_KEYS=$(find /home -maxdepth 3 -name authorized_keys 2>/dev/null | wc -l)
[ "$DEPLOY_KEYS" -gt 0 ] && ok "已部署 $DEPLOY_KEYS 份 authorized_keys（密钥登录可用）" || warn "没有 authorized_keys（当前只能密码登录）"

# ---------------------------------------------------------------- 8 防火墙
sec "8. 防火墙/过滤规则（本镜像默认不设防）"
if pkg_installed ufw; then
  info "ufw 已安装，状态：$(ufw status 2>/dev/null | head -1)"
  ufw status 2>/dev/null | grep -q "Status: active" && warn "ufw 处于启用状态（本镜像默认不开；确认是你开的）"
else
  ok "未安装 ufw"
fi
if have nft; then
  NFT=$(nft list ruleset 2>/dev/null | grep -c . )
  [ "${NFT:-0}" -eq 0 ] && ok "nftables 规则为空" || warn "nftables 有 ${NFT} 行规则（docker/其他软件可能写入）"
fi
IPT=$(iptables -S 2>/dev/null | grep -vc -- '-N ' || true)
if [ "${IPT:-0}" -le 6 ]; then
  ok "iptables 仅有默认规则（未做拦截）"
else
  warn "iptables 有 ${IPT} 条规则（若装了 docker 属正常）"
fi

# ---------------------------------------------------------------- 9 磁盘
sec "9. 磁盘 / 分区 / 文件系统"
ROOTDEV=$(findmnt -no SOURCE / 2>/dev/null)
info "根设备：${ROOTDEV:-?}"
df -h / | tail -1 | awk '{printf "  根分区：总量 %s 已用 %s 可用 %s (%s)\n", $2,$3,$4,$5}'
USE_PCT=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
[ "${USE_PCT:-0}" -ge 90 ] && bad "根分区使用率 ${USE_PCT}%（快满了）" || ok "根分区使用率 ${USE_PCT}%"
DISK=$(lsblk -no NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1; exit}')
if [ -n "$DISK" ]; then
  DISK_SZ=$(lsblk -bno SIZE "$DISK" 2>/dev/null | head -1)
  PART_LAST_END=$(lsblk -bno END "$DISK" 2>/dev/null | tail -1)
  if [ -n "${PART_LAST_END:-}" ] && [ -n "${DISK_SZ:-}" ]; then
    GAP=$(( DISK_SZ - PART_LAST_END ))
    info "整盘：$DISK  $(( DISK_SZ / 1073741824 )) GiB"
    if [ "$GAP" -lt 33554432 ]; then
      ok "分区已用到盘尾（reinstall 的 resize 生效，剩余 ${GAP} 字节）"
    else
      warn "盘尾还有约 $(( GAP / 1073741824 )) GiB 未分配，安装器 resize 可能没跑完"
    fi
  fi
else
  info "未识别到常规整盘设备（LVM/特殊布局请自行核对）"
fi
if [ -n "$ROOTDEV" ] && [ -b "$ROOTDEV" ]; then
  FS=$(blkid -o value -s TYPE "$ROOTDEV" 2>/dev/null)
  info "根文件系统：${FS:-未知}"
  if [ "$FS" = "ext4" ] && have tune2fs; then
    tune2fs -l "$ROOTDEV" 2>/dev/null | grep -q 'Filesystem state: clean' \
      && ok "ext4 状态 clean" || warn "ext4 状态不是 clean（可能异常关机，建议 fsck）"
  fi
fi
if [ -f /etc/fstab ]; then
  awk '$1 ~ /^UUID=/ {print $1, $2}' /etc/fstab | while read -r u m; do
    uu=${u#UUID=}
    blkid -U "$uu" >/dev/null 2>&1 || echo "        [FAIL] fstab 里 UUID=$uu 找不到设备（挂载点 $m）"
  done
  ok "fstab 条目 $(grep -cvE '^[[:space:]]*(#|$)' /etc/fstab) 条"
fi
systemctl is-enabled fstrim.timer >/dev/null 2>&1 && ok "fstrim.timer 已启用（定期 TRIM）" || warn "fstrim.timer 未启用"

# ---------------------------------------------------------------- 10 内存
sec "10. 内存 / swap"
MEM_TOTAL=$(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)
MEM_AVAIL=$(awk '/MemAvailable/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)
info "内存：总计 $MEM_TOTAL，可用 $MEM_AVAIL"
SWAP=$(swapon --show=SIZE --noheadings 2>/dev/null | tr -d ' ')
[ -n "$SWAP" ] && info "swap：$SWAP" || info "swap：无（小内存机器建议加 swapfile）"

# ---------------------------------------------------------------- 11 时间
sec "11. 时间与时区"
TZ=$(timedatectl show -p Timezone --value 2>/dev/null)
info "时区：${TZ:-未知}  当前时间：$(date '+%F %T %Z')"
if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q '^yes'; then
  ok "NTP 已同步"
else
  warn "NTP 未同步（timesyncd 没起来或 UDP 123 被封）"
fi
systemctl is-enabled systemd-timesyncd >/dev/null 2>&1 && ok "systemd-timesyncd 已启用" || warn "systemd-timesyncd 未启用"

# ---------------------------------------------------------------- 12 systemd
sec "12. systemd 单元状态"
STATE=$(systemctl is-system-running 2>/dev/null)
[ "$STATE" = "running" ] && ok "systemd 状态 running" || warn "systemd 状态 ${STATE:-未知}（看下面失败单元）"
FAILED_UNITS=$(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
if [ -n "$FAILED_UNITS" ]; then bad "失败单元：$FAILED_UNITS"; else ok "无失败 unit"; fi
systemctl is-enabled ssh >/dev/null 2>&1 && ok "ssh 开机自启" || bad "ssh 未设置开机自启"
systemctl is-enabled systemd-networkd >/dev/null 2>&1 && ok "systemd-networkd 开机自启" || warn "systemd-networkd 未开机自启（纯 netplan 场景可能正常）"
if systemctl is-enabled qemu-guest-agent >/dev/null 2>&1; then
  systemctl is-active qemu-guest-agent >/dev/null 2>&1 && ok "qemu-guest-agent 运行中" || warn "qemu-guest-agent 已启用但未运行"
fi

# ---------------------------------------------------------------- 13 日志
sec "13. 本次启动的错误日志"
if have journalctl; then
  ERR_N=$(journalctl -b -p err --no-pager 2>/dev/null | grep -c . || true)
  if [ "${ERR_N:-0}" -le 3 ]; then
    ok "本次启动 error 级日志 ${ERR_N} 行"
  else
    warn "本次启动 error 级日志 ${ERR_N} 行，抽样："
    journalctl -b -p err --no-pager 2>/dev/null | tail -3 | sed 's/^/         /'
  fi
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
    ST=$(systemctl is-enabled cloud-init 2>/dev/null)
    [ "$ST" = "enabled" ] && warn "cloud-init 仍 enabled，重启可能覆盖网络配置（建议 disable）" || ok "cloud-init 未开机自启（${ST:-未启用}）"
  fi
else
  ok "未安装 cloud-init"
fi

# ---------------------------------------------------------------- 15 apt
sec "15. apt 源与包状态"
if [ -r /etc/apt/sources.list.d/ubuntu.sources ]; then
  URIS=$(awk -F': ' '/^URIs:/{print $2}' /etc/apt/sources.list.d/ubuntu.sources | tr '\n' ' ')
  info "镜像源：${URIS:-?}"
  echo "$URIS" | grep -q 'mirrors.aliyun.com' && ok "使用国内阿里云源" || info "当前非阿里云源（自己换过就忽略）"
else
  warn "缺 /etc/apt/sources.list.d/ubuntu.sources（源可能被手动改过）"
fi
if apt-get check -q >/dev/null 2>&1; then ok "apt 依赖关系一致"; else bad "apt-get check 报依赖破损"; fi
broken=$(dpkg -C 2>/dev/null | grep -c . || true)
[ "${broken:-0}" -eq 0 ] && ok "dpkg 无半安装状态的包" || warn "dpkg 有破损包，跑 dpkg --configure -a"
if [ "$DEEP" -eq 1 ]; then
  info "deep：执行 apt-get update"
  if apt-get update -qq 2>/dev/null; then ok "apt-get update 成功（源可用）"; else bad "apt-get update 失败（源不可达或 key 失效）"; fi
fi

# ---------------------------------------------------------------- 16 账号
sec "16. 账号与 sudo"
USERS=$(awk -F: '$3>=1000 && $7 !~ /(nologin|false)/ {print $1}' /etc/passwd | tr '\n' ' ')
info "普通登录用户：${USERS:-无}"
for u in $USERS; do
  if id -nG "$u" 2>/dev/null | grep -qw sudo; then ok "$u 在 sudo 组"; else warn "$u 不在 sudo 组"; fi
done
[ -f /etc/sudoers.d/90-cloud-init-users ] && warn "存在 cloud-init 生成的 sudoers 文件（安装器遗留，一般无害）"
[ -f /root/.ssh/authorized_keys ] && info "root 也有 authorized_keys（注意 root 是否允许登录）"

# ---------------------------------------------------------------- 17 其他
sec "17. 其他"
grep -qs 'net.ifnames=0' /proc/cmdline \
  && ok "网卡命名已固定为传统名" \
  || warn "内核参数无 net.ifnames=0（可预测命名通常也正常）"
info "网卡列表：$(ls /sys/class/net | grep -v lo | tr '\n' ' ')"
if have ss; then info "已建立 TCP 连接数：$(ss -H -tn state established 2>/dev/null | wc -l)"; fi
info "熵池：$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null) bit  句柄上限：$(ulimit -n)"

# ---------------------------------------------------------------- 汇总
printf '\n%s== 汇总 ==%s\n' "$C_B" "$C_0"
printf '  通过 %s%d%s  警告 %s%d%s  失败 %s%d%s\n' "$C_G" "$PASS" "$C_0" "$C_Y" "$WARN" "$C_0" "$C_R" "$FAIL" "$C_0"
if [ "$FAIL" -gt 0 ]; then
  echo "  结论：存在需要处理的失败项（见上面 [FAIL] 行）"
  exit 1
fi
echo "  结论：没有发现致命问题"
[ "$WARN" -gt 0 ] && echo "        警告项多为环境差异（ICMP 被封、github 不通等），按提示判断即可"
exit 0
