#!/usr/bin/env python3
# 1) 四套镜像默认用户改 root（sshd/cloud-init 同步放开 root 登录）
# 2) 运维工具层加 nano
# 3) 安装器测速改回串行
# 4) README / MIRRORS / docs 同步
import pathlib

DISTROS = ['distros/ubuntu', 'distros/debian']

for d in DISTROS:
    # ---- conf.sh：默认用户 root ----
    p = pathlib.Path(d) / 'conf.sh'
    t = p.read_text()
    for old in ['export USER_NAME="${USER_NAME:-ubuntu}"', 'export USER_NAME="${USER_NAME:-debian}"']:
        if old in t:
            t = t.replace(old, 'export USER_NAME="${USER_NAME:-root}"     # 默认直接 root 登录；想要普通用户就改成 ubuntu/debian 重建')
            p.write_text(t)
            print(d, 'conf.sh: USER_NAME -> root')
            break

    # ---- packages-ops.list：加 nano ----
    p = pathlib.Path(d) / 'packages-ops.list'
    t = p.read_text()
    if '\nnano' not in t and not t.startswith('nano'):
        t = t.replace('vim-tiny', 'nano\nvim-tiny', 1)
        p.write_text(t)
        print(d, 'packages-ops.list: + nano')

    # ---- sshd：允许 root ----
    p = pathlib.Path(d) / 'files/etc/ssh/sshd_config.d/10-image.conf'
    t = p.read_text()
    if 'PermitRootLogin prohibit-password' in t:
        t = t.replace('PermitRootLogin prohibit-password',
                      '# 镜像默认用户就是 root，放开 root 登录（密码可用即密码登录）\nPermitRootLogin yes')
        p.write_text(t)
        print(d, 'sshd: PermitRootLogin yes')

    # ---- cloud-init：别锁 root、放开密码登录 ----
    p = pathlib.Path(d) / 'files/etc/cloud/cloud.cfg.d/99-image.cfg'
    t = p.read_text()
    changed = False
    for a, b in [('disable_root: true', 'disable_root: false'),
                 ('ssh_pwauth: false', 'ssh_pwauth: true'),
                 ('lock_passwd: true', 'lock_passwd: false')]:
        if a in t:
            t = t.replace(a, b)
            changed = True
    if changed:
        p.write_text(t)
        print(d, 'cloud-init: root 不锁 + 允许密码登录')

    # ---- hook：root 的 /root 与 .ssh 权限 ----
    p = pathlib.Path(d) / 'hooks/10-prepare.sh'
    t = p.read_text()
    if '默认用户为 root' not in t:
        anchor = '  log "已设置 $USER_NAME 密码"\nfi\n'
        assert anchor in t, d + ' hook 锚点缺失'
        t = t.replace(anchor, anchor + '''
# 默认用户是 root 时，确保 /root 与 .ssh 权限正确
if [ "$USER_NAME" = root ]; then
  chmod 700 "$ROOT/root"
  mkdir -p "$ROOT/root/.ssh"
  chmod 700 "$ROOT/root/.ssh"
  if [ -f "$ROOT/root/.ssh/authorized_keys" ]; then
    chmod 600 "$ROOT/root/.ssh/authorized_keys"
  fi
  log "默认用户为 root（PermitRootLogin yes）"
fi
''', 1)
        p.write_text(t)
        print(d, 'hook: root 权限处理'
              .replace('权限处理', '目录权限'))

# ---------- 安装器：测速改回串行 ----------
P = pathlib.Path('installer/reinstall.sh')
t = P.read_text()
SERIAL = '''# 逐个镜像站测速（各拉 1MB），输出最快的那一个；全不通则无输出
sf_pick_mirror() {
    local _u=$1 _m _spd _best= _bestspd=0
    for _m in $(sf_mirrors); do
        _spd=$(sf_mirror_speed "$_m/$_u") || continue
        echo "mirror: $_m ${_spd} B/s" >&2
        if [ "$_spd" -gt "$_bestspd" ] 2>/dev/null; then
            _bestspd=$_spd
            _best=$_m
        fi
    done
    [ -n "$_best" ] && printf '%s' "$_best"
}

'''
start = t.index('# 并行给所有镜像站测速')
end = t.index('sf_accel_url() {')
if 'mktemp -d' in t[start:end]:
    t = t[:start] + SERIAL + t[end:]
    P.write_text(t)
    print('installer: 测速改回串行')
else:
    print('installer: 已经串行，跳过')

# ---------- MIRRORS.md ----------
m = pathlib.Path('installer/MIRRORS.md')
t = m.read_text()
if '- **中国大陆的机器**：给所有加速站并行测速，选最快的那个' in t:
    t = t.replace('- **中国大陆的机器**：给所有加速站并行测速，选最快的那个',
                  '- **中国大陆的机器**：逐个加速站测速，选最快的那个')
if '所有候选站**并行**发一个 1MB 区间请求' in t:
    t = t.replace('''- 所有候选站**并行**发一个 1MB 区间请求（`Range: 0-1048575`，`--max-filesize 4MB` 防误拉整包）''',
                  '''- 逐个候选站发一个 1MB 区间请求（`Range: 0-1048575`，`--max-filesize 4MB` 防误拉整包）''')
if '- 并行测速的总耗时约等于最慢的那一个（上限约 10 秒），不会四站串行叠加' in t:
    t = t.replace('- 并行测速的总耗时约等于最慢的那一个（上限约 10 秒），不会四站串行叠加',
                  '- 串行测速，单个站上限 10 秒；全部不可用时最多多等 40 秒')
m.write_text(t)
print('MIRRORS.md: 已改回串行描述')

for f in ['tools/root-user.py', 'tools/root.flag', '.github/workflows/root-user.yml']:
    q = pathlib.Path(f)
    if q.exists():
        q.unlink()
        print('rm', f)
