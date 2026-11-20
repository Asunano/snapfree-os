#!/usr/bin/env python3
import pathlib

R = pathlib.Path('README.md')
t = R.read_text()
OLD = '- **编辑器 / 常用工具**：`nano`、`vim-tiny`、`git`、`tmux`、`htop`、`rsync`、`jq`、`unzip`、`curl`、`wget`'
NEW = '''- **编辑器**：`nano`、`vim-tiny`
- **网络诊断**：`mtr-tiny`（路由逐跳质量）、`traceroute`、`bind9-dnsutils`（dig/nslookup）、`whois`、`tcpdump`、`iftop`（实时带宽）、`nmap`、`socat`、`net-tools`（ifconfig/netstat）、`lsof`（谁占了端口/文件）
- **系统观察**：`htop`、`sysstat`（sar/iostat/mpstat 历史数据）、`strace`、`ncdu`（磁盘占用排行）、`tree`、`file`、`bc`、`time`、`pv`
- **磁盘 / 分区**：`parted`、`gdisk`（VPS 扩容后用）
- **压缩**：`unzip`、`zip`、`xz-utils`、`bzip2`、`zstd`、`pigz`、`lz4`
- **日常**：`git`、`tmux`、`rsync`、`jq`、`bash-completion`、`openssl`、`pciutils`、`man-db`（有 `man`）'''
if NEW in t:
    print('README: already')
else:
    assert OLD in t
    R.write_text(t.replace(OLD, NEW, 1))
    print('README: 工具清单已分层列出')

for f in ['tools/ops-tools.py', 'tools/ops.flag', '.github/workflows/ops-tools.yml']:
    q = pathlib.Path(f)
    if q.exists():
        q.unlink()
        print('rm', f)
