# -*- coding: utf-8 -*-
"""1.4.7 代码质量优化 Phase 0：代码体量度量 + 行数护栏。

用法（Windows 需 py -3）：
  py -3 scripts/code_stats.py                   # 行数榜 + 汇总
  py -3 scripts/code_stats.py --top 30          # 前 30
  py -3 scripts/code_stats.py --churn 75        # 近 75 天 git churn 榜
  py -3 scripts/code_stats.py --check           # 行数护栏（pre-commit 调用，违规 exit 1）
  py -3 scripts/code_stats.py --init-whitelist  # 按当前状态生成/重置白名单

护栏规则（沿用 PocketToolbox 1.4.7 行数护栏方法论：threshold 900，白名单只减不增）：
- 新增/修改文件 ≤ threshold（默认 900）行；
- 存量超标文件登记于 scripts/size_whitelist.json，白名单只减不增
  （行数不得超过登记上限；拆小到 ≤threshold 后条目应移除，--check 会提示）。

口径：
- 统计 entry/src/main/ets 下全部 .ets（不含 ohosTest/widget/资源）；
- 行数为物理行（含空行与注释），与 IDE 行号一致；
- churn = git log --since N 天 --name-only 出现次数。
"""
import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')
WHITELIST = os.path.join(ROOT, 'scripts', 'size_whitelist.json')
THRESHOLD = 900


def line_count(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return sum(1 for _ in f)


def collect():
    rows = []
    for base, _dirs, files in os.walk(SRC):
        for name in files:
            if name.endswith('.ets'):
                p = os.path.join(base, name)
                rel = os.path.relpath(p, ROOT).replace('\\', '/')
                rows.append((line_count(p), rel))
    rows.sort(reverse=True)
    return rows


def churn(days):
    try:
        out = subprocess.run(
            ['git', 'log', '--since=%d days ago' % days, '--name-only',
             '--pretty=format:', '--', 'entry/src/main/ets'],
            cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace')
        counter = {}
        for line in out.stdout.splitlines():
            line = line.strip()
            if line.endswith('.ets'):
                counter[line] = counter.get(line, 0) + 1
        return counter
    except Exception as e:
        print('churn skipped: %s' % e)
        return {}


def load_whitelist():
    with open(WHITELIST, 'r', encoding='utf-8') as f:
        doc = json.load(f)
    return int(doc.get('threshold', THRESHOLD)), doc.get('entries', {})


def init_whitelist():
    entries = {}
    for n, rel in collect():
        if n > THRESHOLD:
            entries[rel] = n
    doc = {
        '_comment': ('1.4.7 行数护栏白名单：只减不增。条目值 = 允许的最大行数；'
                     '文件拆到 <=900 行后请移除条目；'
                     '重新生成：py -3 scripts/code_stats.py --init-whitelist'),
        'threshold': THRESHOLD,
        'entries': dict(sorted(entries.items())),
    }
    with open(WHITELIST, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print('whitelist written: %d entries (> %d lines)' % (len(entries), THRESHOLD))
    return 0


def check():
    # NOTE: 输出消息保持 ASCII——hook/管道/各控制台代码页差异下不乱码。
    threshold, entries = load_whitelist()
    sizes = dict((rel, n) for n, rel in collect())
    errors = []
    hints = []
    for rel, n in sorted(sizes.items()):
        if n <= threshold:
            continue
        if rel not in entries:
            errors.append('%s: %d lines > %d, NOT in whitelist (new oversized file)'
                          % (rel, n, threshold))
        elif n > entries[rel]:
            errors.append('%s: %d lines exceeds whitelist cap %d (caps may only shrink)'
                          % (rel, n, entries[rel]))
    for rel in sorted(entries):
        n = sizes.get(rel)
        if n is None:
            hints.append('%s: file gone, remove from whitelist' % rel)
        elif n <= threshold:
            hints.append('%s: now %d lines <= %d, remove from whitelist' % (rel, n, threshold))
    for e in errors:
        print('ERROR  ' + e)
    for h in hints:
        print('HINT   ' + h)
    if errors:
        print('size guard FAILED: %d violation(s) (threshold %d, whitelist %d entries)'
              % (len(errors), threshold, len(entries)))
        return 1
    print('OK: %d files, threshold %d, whitelist %d entries, no violations'
          % (len(sizes), threshold, len(entries)))
    return 0


def report(top):
    rows = collect()
    total = sum(r[0] for r in rows)
    over1000 = [r for r in rows if r[0] > 1000]
    over_thr = [r for r in rows if r[0] > THRESHOLD]

    print('%d files, %d lines total' % (len(rows), total))
    print('>1000 lines: %d files (%d lines, %.0f%% of total)'
          % (len(over1000), sum(r[0] for r in over1000),
             100.0 * sum(r[0] for r in over1000) / max(total, 1)))
    print('>%d lines:  %d files' % (THRESHOLD, len(over_thr)))
    print()
    print('%8s  %s' % ('lines', 'file'))
    for n, rel in rows[:top]:
        print('%8d  %s' % (n, rel))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--top', type=int, default=20)
    ap.add_argument('--churn', type=int, default=0, help='近 N 天 churn 榜，0=不统计')
    ap.add_argument('--check', action='store_true', help='行数护栏校验（违规 exit 1）')
    ap.add_argument('--init-whitelist', action='store_true', help='按当前状态生成/重置白名单')
    args = ap.parse_args()

    if args.init_whitelist:
        sys.exit(init_whitelist())
    if args.check:
        sys.exit(check())

    report(args.top)
    if args.churn:
        c = churn(args.churn)
        print()
        print('churn top (last %d days):' % args.churn)
        for rel, cnt in sorted(c.items(), key=lambda x: -x[1])[:args.top]:
            n = dict((r[1], r[0]) for r in collect()).get(rel, 0)
            print('%3d commits  %6d lines  %s' % (cnt, n, rel))


if __name__ == '__main__':
    sys.exit(main())
