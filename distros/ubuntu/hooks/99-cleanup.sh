#!/usr/bin/env bash
# mmdebstrap 收尾 hook：清缓存、去标识、精简文档与语言包、二次确认无 snap
set -Eeuo pipefail
ROOT="${1:?需要 rootfs 路径}"

log(){ printf '  · %s\n' "$*"; }

chroot "$ROOT" bash -ec '
  set -e
  apt-get clean
  rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /var/cache/apt/archives/*
  rm -f /etc/ssh/ssh_host_* /etc/ssh/ssh_host_*_key.pub
  : > /etc/machine-id
  rm -rf /var/log/* /var/log/journal/* /tmp/* /var/tmp/* /root/.bash_history
  cloud-init clean --logs >/dev/null 2>&1 || true
' 2>/dev/null || log "warn: 基础清理有非致命报错"

# ---------- 精简：changelog、非中英文语言包 ----------
# 保留 copyright 文件（许可证合规要求）
find "$ROOT/usr/share/doc" -type f \( -name 'changelog*' -o -name 'NEWS*' \) -delete 2>/dev/null || true
for d in "$ROOT/usr/share/locale" "$ROOT/usr/share/locale-langpack"; do
  [ -d "$d" ] || continue
  find "$d" -mindepth 1 -maxdepth 1 -type d \
       ! -name 'en*' ! -name 'zh*' ! -name 'C' \
       -exec rm -rf {} + 2>/dev/null || true
done

if chroot "$ROOT" dpkg-query -W -f='${db:Status-Status}\n' snapd >/dev/null 2>&1; then
  printf '[!] snapd 仍在，构建中止\n' >&2; exit 1
fi

log "清理完成：machine-id/ssh host key/apt 缓存已清，changelog 与非中英文语言包已删"
