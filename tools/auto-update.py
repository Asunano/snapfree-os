#!/usr/bin/env python3
# 1) image-build: 每日随机窗口重建、每镜像独立 tag 发布、保留 image-latest 兼容、catalog 体积回写
# 2) 新增 upstream-sync: 自动同步上游 trans.sh，reinstall.sh 变更只开 issue
# 3) 文档同步
import pathlib

ROOT = pathlib.Path('.')

# ============ 1. image-build.yml ============
W = ROOT / '.github/workflows/image-build.yml'
t = W.read_text()

# 1.1 定时：每天 01:00 CST，具体开始由 gate 任务随机延迟
old_cron = "  schedule:\n    - cron: '0 18 1 * *'"
new_cron = ("  schedule:\n"
            "    # 每天 01:00 (UTC+8) 触发；实际开始由 gate 任务随机延迟 0-60 分钟\n"
            "    - cron: '0 17 * * *'")
if '0 17 * * *' not in t:
    assert old_cron in t
    t = t.replace(old_cron, new_cron, 1)
    print('build: cron -> 每日 17:00 UTC')

# 1.2 gate 任务 + build needs gate
old_head = "jobs:\n  build:\n    runs-on: ubuntu-24.04"
new_head = '''jobs:
  gate:
    runs-on: ubuntu-24.04
    steps:
      - name: 随机延迟（仅定时触发）
        if: github.event_name == 'schedule'
        run: |
          set -euo pipefail
          d=$((RANDOM % 3600))
          echo "定时触发，随机延迟 ${d}s 后开始重建"
          sleep "$d"

  build:
    needs: gate
    runs-on: ubuntu-24.04'''
if 'random' not in t and 'gate:' not in t:
    assert old_head in t
    t = t.replace(old_head, new_head, 1)
    print('build: 已加 gate 随机延迟')

# 1.3 发布条件：schedule / 手动触发 / [publish] 均可发布
old_if = "    if: github.ref == 'refs/heads/main' && contains(github.event.head_commit.message, '[publish]')"
new_if = ("    if: >-\n"
          "      github.ref == 'refs/heads/main' &&\n"
          "      (github.event_name == 'schedule' ||\n"
          "       github.event_name == 'workflow_dispatch' ||\n"
          "       contains(github.event.head_commit.message, '[publish]'))")
if 'github.event_name == \'schedule\'' not in t:
    assert old_if in t
    t = t.replace(old_if, new_if, 1)
    print('build: 发布条件已放开到 schedule/dispatch')

# 1.4 发布任务整体重写（按镜像打 tag + 汇总 image-latest + 回写 catalog）
idx = t.index('  publish-latest:')
NEW_PUB = '''  publish-latest:
    needs: [build, smoke]
    if: >-
      github.ref == 'refs/heads/main' &&
      (github.event_name == 'schedule' ||
       github.event_name == 'workflow_dispatch' ||
       contains(github.event.head_commit.message, '[publish]'))
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v5

      - name: 取全部 qcow2
        uses: actions/download-artifact@v4
        with:
          path: dist

      - name: 按镜像独立 tag 发布
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GH_REPO: ${{ github.repository }}
        run: |
          set -euo pipefail
          find dist -type f | sort
          for d in dist/*/; do
            id=$(basename "$d" | sed -E 's/^qcow2-//; s/-[0-9]+$//')
            [ -n "$id" ] || continue
            files=$(find "$d" -maxdepth 1 -type f \\( -name '*.qcow2' -o -name '*.sha256' \\) | sort)
            [ -n "$files" ] || { echo "跳过 $id（无产物）"; continue; }
            echo "== 发布 $id"
            if gh release view "$id" >/dev/null 2>&1; then
              gh release upload "$id" $files --clobber
            else
              gh release create "$id" $files \\
                --target "$GITHUB_SHA" \\
                --title "snapfree-os $id" \\
                --notes "$id 的自动构建镜像（每日重建）。产物与 image-latest 中同名文件一致。" \\
                --latest=false
            fi
          done

      - name: 汇总发布到 image-latest（保持旧链接可用）
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GH_REPO: ${{ github.repository }}
        run: |
          set -euo pipefail
          mapfile -t FILES < <(find dist -type f \\( -name '*.qcow2' -o -name '*.sha256' \\) | sort)
          [ "${#FILES[@]}" -gt 0 ] || { echo '没有可发布的产物'; exit 1; }
          if gh release view image-latest >/dev/null 2>&1; then
            gh release upload image-latest "${FILES[@]}" --clobber
          else
            gh release create image-latest "${FILES[@]}" \\
              --target "$GITHUB_SHA" \\
              --title 'snapfree-os latest' \\
              --notes '仓库内镜像的 latest 发布（由 Actions 自动发布）。'
          fi
          gh release edit image-latest --latest

      - name: 回写 catalog 体积
        run: |
          set -euo pipefail
          python3 - <<'PY'
          import pathlib, re
          files = {}
          for p in pathlib.Path('dist').rglob('*.qcow2'):
              files[p.name] = p.stat().st_size
          def human(n):
              if n >= 1024 ** 3:
                  return f"{n / 1024 ** 3:.1f}G"
              return f"{max(1, round(n / 1024 ** 2))}M"
          c = pathlib.Path('catalog/catalog.tsv')
          lines = c.read_text().splitlines()
          out, changed = [], 0
          for line in lines:
              if line.startswith('#') or not line.strip():
                  out.append(line); continue
              f = line.split('|')
              name = f[7].rsplit('/', 1)[-1]
              size = files.get(name)
              if size and f[6] != human(size):
                  f[6] = human(size); changed += 1
              out.append('|'.join(f))
          c.write_text('\\n'.join(out) + '\\n')
          print(f'catalog 体积更新 {changed} 条')
          PY
          if git diff --quiet catalog/catalog.tsv; then
            echo 'catalog 无变化，跳过提交'
            exit 0
          fi
          git config user.name 'snapfree-bot'
          git config user.email 'bot@users.noreply.github.com'
          git add catalog/catalog.tsv
          git commit -m 'chore(catalog): 同步镜像体积 [skip ci]'
          git push
'''
t = t[:idx] + NEW_PUB
W.write_text(t)
print('build: 发布任务已重写（per-image tag + 汇总 + catalog 回写）')

# ============ 2. upstream-sync.yml ============
UP = ROOT / '.github/workflows/upstream-sync.yml'
UP.write_text('''# upstream-sync：每日同步上游 bin456789/reinstall 的 trans.sh
# trans.sh 是本仓库未曾修改的上游安装核心，可直接跟随；
# reinstall.sh 经过大量魔改（菜单/catalog/加速），不自动合并，只开 issue 提醒。
name: upstream-sync

on:
  schedule:
    # 每天 04:00 (UTC+8) 触发，实际开始随机延迟 0-30 分钟
    - cron: '0 20 * * *'
  workflow_dispatch:

permissions:
  contents: write
  issues: write

concurrency:
  group: upstream-sync
  cancel-in-progress: false

jobs:
  sync:
    runs-on: ubuntu-24.04
    steps:
      - name: 随机延迟（仅定时触发）
        if: github.event_name == 'schedule'
        run: sleep $((RANDOM % 1800))

      - uses: actions/checkout@v5

      - name: 记录同步前的上游版本
        id: before
        run: echo "last=$(cat installer/.upstream-version 2>/dev/null || echo none)" >> "$GITHUB_OUTPUT"

      - name: 拉取上游文件
        run: |
          set -euo pipefail
          for f in trans.sh reinstall.sh; do
            curl -fsSL --retry 3 "https://raw.githubusercontent.com/bin456789/reinstall/main/$f" -o "/tmp/up-$f"
            bash -n "/tmp/up-$f"
            echo "ok $f $(wc -c < /tmp/up-$f) bytes"
          done

      - name: 兼容性门禁（fork 依赖的锚点必须存在）
        run: |
          set -euo pipefail
          grep -qE '^SCRIPT_VERSION=' /tmp/up-trans.sh
          grep -q '^: main' /tmp/up-trans.sh
          grep -q 'cloud_image' /tmp/up-trans.sh
          grep -q "insert_into_file \\$initrd_dir/trans.sh after '^: main'" installer/reinstall.sh
          echo '锚点检查通过'

      - name: 同步 trans.sh
        id: sync
        run: |
          set -euo pipefail
          NEW=$(grep -m1 '^SCRIPT_VERSION=' /tmp/up-trans.sh | cut -d= -f2)
          OLD_SHA=$(sha256sum installer/trans.sh | cut -d' ' -f1)
          NEW_SHA=$(sha256sum /tmp/up-trans.sh | cut -d' ' -f1)
          echo "上游版本 $NEW | 本地 ${OLD_SHA:0:12} | 上游 ${NEW_SHA:0:12}"
          echo "version=$NEW" >> "$GITHUB_OUTPUT"
          if [ "$OLD_SHA" = "$NEW_SHA" ]; then
            echo 'changed=false' >> "$GITHUB_OUTPUT"
            echo 'trans.sh 无变化'
            exit 0
          fi
          cp /tmp/up-trans.sh installer/trans.sh
          sed -i "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=$NEW/" installer/reinstall.sh
          bash -n installer/trans.sh
          bash -n installer/reinstall.sh
          a=$(grep -m1 '^SCRIPT_VERSION=' installer/reinstall.sh)
          b=$(grep -m1 '^SCRIPT_VERSION=' installer/trans.sh)
          [ "$a" = "$b" ] || { echo '版本号未对齐，回退'; cp installer/trans.sh /tmp/keep; git checkout -- installer/trans.sh installer/reinstall.sh; exit 1; }
          echo 'changed=true' >> "$GITHUB_OUTPUT"
          echo "已更新到 $NEW"

      - name: 提交同步结果
        if: steps.sync.outputs.changed == 'true'
        run: |
          set -euo pipefail
          git config user.name 'snapfree-bot'
          git config user.email 'bot@users.noreply.github.com'
          printf '%s\\n' "${{ steps.sync.outputs.version }}" > installer/.upstream-version
          git add installer/trans.sh installer/reinstall.sh installer/.upstream-version
          git commit -m "[sync] 上游 trans.sh 同步至 ${{ steps.sync.outputs.version }}"
          git push

      - name: 上游 reinstall.sh 有变更则开 issue（不自动合并）
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GH_REPO: ${{ github.repository }}
        run: |
          set -euo pipefail
          NEW=$(grep -m1 '^SCRIPT_VERSION=' /tmp/up-trans.sh | cut -d= -f2)
          LAST="${{ steps.before.outputs.last }}"
          if [ "$NEW" = "$LAST" ]; then
            echo "上游版本未变（$NEW），不建 issue"
            exit 0
          fi
          TITLE="上游 reinstall.sh 变更待评估：$NEW"
          if gh issue list --state open --search "\"$TITLE\" in:title" --json title --jq '.[].title' | grep -qx "$TITLE"; then
            echo 'issue 已存在，跳过'
            exit 0
          fi
          {
            echo "上游 bin456789/reinstall 已发布 **$NEW**（本地记录：$LAST）。"
            echo
            echo "本仓库已自动同步 \`trans.sh\`，但 \`reinstall.sh\` 经过魔改（catalog 菜单、下载加速、setos_* 校验），**不会自动合并**。"
            echo
            echo "需要人工处理的事项："
            echo "1. 对比上游 reinstall.sh 与本地导入部分，判断是否有影响安装流程的修复；"
            echo "2. 若上游修了引导/分区/网络相关逻辑，按功能搬进本地对应函式；"
            echo "3. 搬完后跑 \`installer-contract\`，并手动触发一次重装验证；"
            echo "4. 若暂不跟进，保持 \`installer/.upstream-version\` 不变即可（下次不会再重复提醒同一版本）。"
            echo
            echo "上游：https://github.com/bin456789/reinstall/commits/main"
          } > /tmp/issue.md
          gh issue create --title "$TITLE" --body-file /tmp/issue.md

      - name: 更新本地版本记录（仅当本次未提交时）
        if: steps.sync.outputs.changed != 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          NEW="${{ steps.sync.outputs.version }}"
          CUR=$(cat installer/.upstream-version 2>/dev/null || echo none)
          [ "$NEW" = "$CUR" ] && { echo '无需更新'; exit 0; }
          git config user.name 'snapfree-bot'
          git config user.email 'bot@users.noreply.github.com'
          printf '%s\\n' "$NEW" > installer/.upstream-version
          git add installer/.upstream-version
          git commit -m "chore: 记录上游版本 $NEW [skip ci]"
          git push
''')
print('新增 upstream-sync.yml')

# ============ 3. 版本记录 ============
cur_ver = 'none'
for line in (ROOT / 'installer/trans.sh').read_text().splitlines():
    if line.startswith('SCRIPT_VERSION='):
        cur_ver = line.split('=', 1)[1].strip()
(ROOT / 'installer/.upstream-version').write_text(cur_ver + '\n')
print('installer/.upstream-version =', cur_ver)

# ============ 4. 文档 ============
R = ROOT / 'README.md'
r = R.read_text()
SEC = '''## 自动更新与发布

| 对象 | 频率 | 行为 |
|---|---|---|
| 镜像 | 每天 01:00 后随机开始（随机延迟 0–60 分钟） | 从官方源重建四套镜像 → 冒烟启动 → 发布 |
| 安装核心 `trans.sh` | 每天 04:00 后随机开始 | 拉取上游同名文件，锚点兼容性校验通过后覆盖并提交 |
| 魔改安装器 `reinstall.sh` | 仅提醒 | 上游有变更时开 issue，不自动合并 |

发布标签：每套镜像一个独立 tag（当前为 `ubuntu-26.04`、`ubuntu-24.04`、`debian-13`、`debian-12`），另有一个汇总 tag `image-latest`，内含全部镜像。

```text
https://github.com/Asunano/snapfree-os/releases/download/ubuntu-26.04/ubuntu-26.04-server-snapfree-amd64.qcow2
https://github.com/Asunano/snapfree-os/releases/download/debian-13/debian-13-server-snapfree-amd64.qcow2
https://github.com/Asunano/snapfree-os/releases/latest/download/debian-13-server-snapfree-amd64.qcow2   # 汇总，兼容旧链接
```

`catalog/catalog.tsv` 中的 `size` 会在发布后自动回写，`url` 保持指向 `image-latest`，所以旧链接不会失效。

手动发布：在 Actions 里手动跑 `image-build` 会直接发布；或推入 commit 并在 message 里带 `[publish]`。

'''
if '## 自动更新与发布' not in r:
    assert '## 镜像清单' in r
    r = r.replace('## 镜像清单', SEC + '## 镜像清单', 1)
    r = r.replace('- [镜像清单](#镜像清单)', '- [自动更新与发布](#自动更新与发布)\n- [镜像清单](#镜像清单)', 1)
    R.write_text(r)
    print('README: 已加自动更新章节')

B = ROOT / 'docs/BUILD.md'
b = B.read_text()
OLD_TRIG = '触发条件：`push` 到 `main` 且改动命中 `distros/**` 或本 workflow 文件；`workflow_dispatch`；每月 1 日 18:00（UTC，即北京时间 2 日 02:00）定时重建。'
NEW_TRIG = '''触发条件：`push` 到 `main` 且改动命中 `distros/**` 或本 workflow 文件；`workflow_dispatch`；每日 `0 17 * * *`（UTC，即北京时间 01:00）定时重建。

定时触发时 `gate` 任务会先随机 `sleep 0–3600` 秒，使每日开始时间不固定（上限一小时，避免所有用户与上游同时拉取官方源）。`gate` 只在上报定时事件时延迟，`push` / `workflow_dispatch` 直接开始。

发布条件：`main` 分支且（`schedule` 或 `workflow_dispatch` 或 commit message 含 `[publish]`）。发布时按 artifact 目录名拆出镜像 id，为每个 id 创建一个同名 tag 的 Release（`--latest=false`），随后把所有产物汇总写入 `image-latest` 并将其设为 latest，保证 `releases/latest/download/<file>` 旧链接不变。

发布完成后会按实际产物字节数回写 `catalog/catalog.tsv` 的 `size` 字段并以 `chore(catalog): 同步镜像体积 [skip ci]` 提交；`GITHUB_TOKEN` 提交不会再触发其他 workflow。'''
if '每月 1 日 18:00' in b:
    b = b.replace(OLD_TRIG, NEW_TRIG, 1)
    print('BUILD.md: 触发/发布说明已更新')

SYNC = '''### upstream-sync

`.github/workflows/upstream-sync.yml` 每日同步上游安装核心，`workflow_dispatch` 可手动跑：

1. 拉取上游 `trans.sh`、`reinstall.sh`，两者先过 `bash -n`
2. 兼容性门禁：上游 `trans.sh` 必须有 `^SCRIPT_VERSION=`、`^: main`、`cloud_image`；本地 `reinstall.sh` 必须有向 `trans.sh` 注入的锚点语句
3. `trans.sh` sha256 变化时覆盖本地文件，并把 `reinstall.sh` 的 `SCRIPT_VERSION` 改成与上游一致（重装时 `reinstall.sh` 会校验下载到的 `trans.sh` 版本号，两者必须相等），再提交 `[sync] ...`
4. 上游版本号变化时开 issue `上游 reinstall.sh 变更待评估：<version>`，说明不能自动合并的原因与人工步骤；已存在同名 issue 则跳过
5. `installer/.upstream-version` 记录已处理的上游版本，避免重复开 issue

> [!IMPORTANT]
> 只自动同步 `trans.sh`。`reinstall.sh` 含 catalog 菜单、下载加速、`setos_*` 校验等魔改，自动合并会冲突或覆盖这些逻辑，只能按 issue 人工搬。

'''
if '### upstream-sync' not in b:
    anchor = '## 清单字段'
    b = b.replace(anchor, SYNC + anchor, 1)
    B.write_text(b)
    print('BUILD.md: 已加 upstream-sync 章节')
else:
    B.write_text(b)

for f in ['tools/auto-update.py', 'tools/auto.flag', '.github/workflows/auto-update.yml']:
    q = pathlib.Path(f)
    if q.exists():
        q.unlink()
        print('rm', f)
