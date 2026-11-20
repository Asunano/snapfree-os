#!/usr/bin/env python3
import pathlib

p = pathlib.Path('docs/BUILD.md')
t = p.read_text()
OLD = '每月 1 日 18:00 定时重建'
NEW = '每月 1 日 18:00（UTC，即北京时间 2 日 02:00）定时重建'
if NEW in t:
    print('already')
else:
    p.write_text(t.replace(OLD, NEW, 1))
    print('fixed')

for f in ['tools/doc-tz.py', 'tools/tz.flag', '.github/workflows/doc-tz.yml']:
    q = pathlib.Path(f)
    if q.exists():
        q.unlink()
        print('rm', f)
