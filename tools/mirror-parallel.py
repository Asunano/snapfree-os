#!/usr/bin/env python3
# 测速改并行，同步更新 installer/MIRRORS.md 规则描述
import pathlib

P = pathlib.Path('installer/reinstall.sh')
t = P.read_text()

NEW = '''# 并行给所有镜像站测速（各拉 1MB），输出最快的那一个；全不通则无输出
sf_pick_mirror() {
    local _u=$1 _m _s _best= _bestspd=0 _d
    _d=$(mktemp -d 2>/dev/null) || return 0
    for _m in $(sf_mirrors); do
        (
            _s=$(sf_mirror_speed "$_m/$_u") && printf '%s %s\\n' "$_s" "$_m" >>"$_d/out"
        ) &
    done
    wait
    if [ -f "$_d/out" ]; then
        while read -r _s _m; do
            [ -n "$_s" ] || continue
            echo "mirror: $_m ${_s} B/s" >&2
            if [ "$_s" -gt "$_bestspd" ] 2>/dev/null; then
                _bestspd=$_s
                _best=$_m
            fi
        done <"$_d/out"
    fi
    rm -rf "$_d"
    [ -n "$_best" ] && printf '%s' "$_best"
}

'''

start = t.index('# 逐个镜像站测速，输出最快的那一个')
end = t.index('sf_accel_url() {')
if 'mktemp -d' in t[start:end]:
    print('already parallel')
else:
    t = t[:start] + NEW + t[end:]
    P.write_text(t)
    print('picked: 测速改并行')

pathlib.Path('installer/MIRRORS.md').write_text('''# 镜像下载加速

安装器下载 qcow2 时会自动选更快的地址，规则只有两条：

- **中国大陆的机器**：给所有加速站并行测速，选最快的那个
- **海外机器**：先直连 GitHub，只有直连不通（超时 / 失败）时才走加速站

## 国内判定（多级兜底，任一命中 CN 即算国内）

1. 上游已经拿到的 `_loc`（`is_in_china` 的结果）
2. `https://api.ip.sb/geoip` 的 `country_code`
3. `https://ipinfo.io/country`
4. `http://www.qualcomm.cn/cdn-cgi/trace` 的 `loc`

命中的结果会写回 `_loc`，上游后续判断直接复用。

## 候选站

| 加速站 |
|---|
| `https://mirror-one.losn.cc` |
| `https://mirror.drxian.qzz.io` |
| `https://v4.gh-proxy.org` |
| `https://axisnow.gh-proxy.org` |

顺序只决定探测先后，最终按实际速度选，谁快用谁。

真实下载地址 = 前缀 + 原 URL，例如：

```text
https://axisnow.gh-proxy.org/https://github.com/Asunano/snapfree-os/releases/latest/download/debian-13-server-snapfree-amd64.qcow2
```

## 测速方式

- 所有候选站**并行**发一个 1MB 区间请求（`Range: 0-1048575`，`--max-filesize 4MB` 防误拉整包）
- 返回码不是 200/206、`content-type` 是 `text/html`、或拿到不足 64KB 的，直接排掉（代理常拿伪 200 错误页糊弄）
- 并行测速的总耗时约等于最慢的那一个（上限约 10 秒），不会四站串行叠加
- 选中的站会缓存，同一次安装不会重复测速
- 四个站都不可用时回落 GitHub 原地址（慢，但不会卡住安装）

## 生效范围

- `sf_lookup_img`（`setos_ubuntu` / `setos_debian` 查 `catalog/catalog.tsv` 的路径）
- 交互菜单选中的 URL（`sf_menu` 里的 `sf_sel_img`）
- 只改写 `github.com` / `raw.githubusercontent.com` / `objects.githubusercontent.com` 的链接；你手动传的 `--img` 自定义链接不会被改
- 只影响镜像 qcow2 的下载，`trans.sh` 拉的其他上游资源不变

## 临时关掉

安装器里没有开关。要禁用就把 `sf_mirrors` 的列表清空（或让 `sf_accel_url` 原样返回），改完 `bash -n` 过一遍即可。
''')
print('installer/MIRRORS.md: 已更新为测速选最优')

for p in ['tools/mirror-parallel.py', 'tools/par.flag', '.github/workflows/mirror-parallel.yml']:
    f = pathlib.Path(p)
    if f.exists():
        f.unlink()
        print('rm', p)
