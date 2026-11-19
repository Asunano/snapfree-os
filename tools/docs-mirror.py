#!/usr/bin/env python3
# 补文档 + 清理一次性脚手架
import pathlib

R = pathlib.Path('README.md')
r = R.read_text()

SEC = '''## 镜像下载加速

安装器下载 qcow2 会自动挑更快的地址：**国内机器直接用加速站**（`mirror-one.losn.cc` → `mirror.drxian.qzz.io` → `v4.gh-proxy.org` → `axisnow.gh-proxy.org`，按顺序探测，第一个可用的胜出）；**海外机器先直连 GitHub，只有直连不通才退到加速站**。地区识别依次尝试 `api.ip.sb` → `ipinfo.io` → `qualcomm trace`，任一命中 CN 即算国内。探测会过滤 `text/html` 之类的伪 200 错误页，四站全挂时回落 GitHub 原地址。细节见 [`installer/MIRRORS.md`](installer/MIRRORS.md)。

'''

if '## 镜像下载加速' not in r:
    assert '## 装完之后' in r
    r = r.replace('## 装完之后', SEC + '## 装完之后', 1)
    R.write_text(r)
    print('README: 已插入镜像加速章节')
else:
    print('README: 已有章节，跳过')

if 'installer/MIRRORS.md    镜像加速说明' not in r:
    r = R.read_text()
    old = 'installer/                 fork 的 reinstall（菜单 + 安装核心，trans.sh 未改）'
    if old in r:
        r = r.replace(old, old + '\ninstaller/MIRRORS.md       镜像下载加速规则与开关', 1)
        R.write_text(r)
        print('README: 目录表已补 MIRRORS.md')
else:
    print('README: 目录已补，跳过')

M = pathlib.Path('installer/MIRRORS.md')
M.write_text('''# 镜像下载加速

安装器下载 qcow2 时会自动选更快的地址，规则只有两条：

- **中国大陆的机器**：直接用加速站（按下面顺序探测，第一个可用的胜出）
- **海外机器**：先直连 GitHub，只有直连不通（超时 / 失败）时才退到加速站

## 国内判定（多级兜底，任一命中 CN 即算国内）

1. 上游已经拿到的 `_loc`（`is_in_china` 的结果）
2. `https://api.ip.sb/geoip` 的 `country_code`
3. `https://ipinfo.io/country`
4. `http://www.qualcomm.cn/cdn-cgi/trace` 的 `loc`

命中的结果会写回 `_loc`，上游后续判断直接复用。

## 加速站顺序

| 顺序 | 前缀 |
|---|---|
| 1 | `https://mirror-one.losn.cc` |
| 2 | `https://mirror.drxian.qzz.io` |
| 3 | `https://v4.gh-proxy.org` |
| 4 | `https://axisnow.gh-proxy.org` |

真实下载地址 = 前缀 + 原 URL，例如：

```text
https://mirror-one.losn.cc/https://github.com/Asunano/snapfree-os/releases/latest/download/debian-13-server-snapfree-amd64.qcow2
```

## 探测方式

- 先发 `HEAD`；站点不支持 `HEAD` 时用 `Range: 0-1023` 拉 1KB 兜底，并用 `--max-filesize 65536` 防止误拉整包
- 返回 `text/html` / `application/json` / `text/plain`，或 `content-length` 小于 64KB 的，判为错误页而不算命中
- 选中的前缀会缓存，同一次安装不重复探测
- 四个站都不可用时回落 GitHub 原地址（慢，但不会卡住安装）

## 生效范围

- `sf_lookup_img`（`setos_ubuntu` / `setos_debian` 查 `catalog/catalog.tsv` 的路径）
- 交互菜单选中的 URL（`sf_menu` 里的 `sf_sel_img`）
- 只改写 `github.com` / `raw.githubusercontent.com` / `objects.githubusercontent.com` 的链接；你手动传的 `--img` 自定义链接不会被改
- 只影响镜像 qcow2 的下载，`trans.sh` 拉的其他上游资源不变

## 临时关掉

安装器里没有开关。要禁用就把 `sf_mirrors` 的列表清空（或让 `sf_accel_url` 原样返回），改完 `bash -n` 过一遍即可。
''')
print('installer/MIRRORS.md: 已写入')

# 清理一次性脚手架
for p in [
    'tools/add-mirror-accel.py', 'tools/mirror.flag',
    'tools/fix-cn-detect.py', 'tools/cn.flag',
    'tools/harden-probe.py', 'tools/probe.flag',
    'tools/docs-mirror.py', 'tools/docs.flag',
    '.github/workflows/mirror-accel.yml',
    '.github/workflows/cn-detect.yml',
    '.github/workflows/harden-probe.yml',
    '.github/workflows/docs-mirror.yml',
]:
    f = pathlib.Path(p)
    if f.exists():
        f.unlink()
        print('rm', p)
