# -*- coding: utf-8 -*-
"""1.4.7 代码质量优化 Phase 3 P3-3：多语字符串资源治理。

用法（Windows 需 py -3）：
  py -3 scripts/check_strings.py            # 报告：键数统计 + 键集合 diff + 占位符一致性 + 前缀审计
  py -3 scripts/check_strings.py --check    # 校验模式（pre-commit 调用，违规 exit 1）

校验规则（沿用 PocketToolbox 1.4.7 P3-3 多语资源治理方法论）：
- base/en 两目录 string.json 键集合必须一致：缺键 = 运行时回退 base；多键 = 死资源；
- 同文件内键名不得重复（后者静默覆盖前者）；
- 同键双语占位符签名必须一致（%s/%d 按出现序隐式编号，%N$s/%N$d 显式编号；
  缺失/多余/类型不符都会导致 $r() 传参错位或显示异常）；
- 前缀审计与键数统计仅报告不拦截（命名收拢另批进行）。
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALES = ['base', 'en']
BASE = 'base'
PATH_TPL = os.path.join(ROOT, 'entry', 'src', 'main', 'resources',
                        '%s', 'element', 'string.json')
# 系统保留前缀（模块/Ability/桌面卡片清单引用，不可改名），审计时跳过
SYSTEM_PREFIXES = {'EntryAbility', 'module'}
PLACEHOLDER_RE = re.compile(r'%(\d+\$)?([sd])')
SCATTER_THRESHOLD = 3  # 前缀键数 <= 该值视为散键候选


def load(locale):
    """返回 (name->value 映射, 重复键列表, 解析错误列表)。"""
    path = PATH_TPL % locale
    with open(path, 'r', encoding='utf-8-sig') as f:
        doc = json.load(f)
    entries = doc.get('string', [])
    mapping = {}
    dups = []
    for item in entries:
        name = item.get('name')
        value = item.get('value', '')
        if not name:
            continue
        if name in mapping:
            dups.append(name)
        else:
            mapping[name] = value
    return mapping, dups


def signature(value):
    """占位符签名：[(编号, 类型), ...] 按编号升序。

    非位置 %s/%d 按出现顺序隐式编号 1,2,3...；位置 %N$s/%N$d 用显式编号。
    位置占位符支持译文语序重排，故按编号排序后比较而非按出现序。
    """
    seq = 0
    tokens = []
    for m in PLACEHOLDER_RE.finditer(value):
        pos_s, typ = m.group(1), m.group(2)
        if pos_s:
            pos = int(pos_s.rstrip('$'))
        else:
            seq += 1
            pos = seq
        tokens.append((pos, typ))
    tokens.sort()
    return tokens


def check(data):
    """收集违规：[(级别, 消息), ...]，级别 ERROR/WARN。ERROR 拦截，WARN 仅提示。

    同键内占位符编号重复（如 "%1$d ... %1$d"）是合法的「同参数复用」模式
    （调用方重复传参即可，见 gif_toast_frames_truncated），降级 WARN 不拦截。
    """
    issues = []
    base_map = data[BASE][0]
    for loc in LOCALES:
        mapping, dups = data[loc]
        for name in dups:
            issues.append(('ERROR', '%s: duplicate key "%s" (later entry silently wins)'
                           % (loc, name)))
    for loc in LOCALES:
        if loc == BASE:
            continue
        mapping = data[loc][0]
        for name in base_map:
            if name not in mapping:
                issues.append(('ERROR', '%s: missing key "%s" (runtime falls back to base)'
                               % (loc, name)))
        for name in mapping:
            if name not in base_map:
                issues.append(('ERROR', '%s: extra key "%s" not in base (dead resource)'
                               % (loc, name)))
    for name in sorted(base_map):
        sigs = {}
        for loc in LOCALES:
            mapping = data[loc][0]
            if name in mapping:
                sigs[loc] = signature(mapping[name])
        ref = sigs.get(BASE)
        if ref is None:
            continue
        for loc, sig in sigs.items():
            if loc == BASE:
                continue
            if sig != ref:
                issues.append(('ERROR', '%s: placeholder mismatch for "%s": base=%s %s=%s'
                               % (loc, name, ref, loc, sig)))
        seen = set()
        for pos, _typ in ref:
            if pos in seen:
                issues.append(('WARN', 'base: repeated placeholder position %d in "%s" '
                               '(same-arg reuse; ensure call site passes it consistently)'
                               % (pos, name)))
                break
            seen.add(pos)
    return issues


def prefix_audit(names):
    """前缀直方图 + 散键候选。返回 (直方图行列表, 散键行列表)。"""
    hist = {}
    for name in names:
        prefix = name.split('_')[0]
        hist[prefix] = hist.get(prefix, 0) + 1
    hist_rows = ['%5d  %s' % (cnt, prefix)
                 for prefix, cnt in sorted(hist.items(), key=lambda x: (-x[1], x[0]))]
    scatter = []
    for prefix, cnt in sorted(hist.items()):
        if cnt <= SCATTER_THRESHOLD and prefix not in SYSTEM_PREFIXES:
            members = [n for n in names if n.split('_')[0] == prefix]
            scatter.append('%-12s %d key(s): %s' % (prefix, cnt, ', '.join(members)))
    return hist_rows, scatter


def report(data, top_prefixes):
    base_map = data[BASE][0]
    print('key counts: ' + ', '.join(
        '%s=%d' % (loc, len(data[loc][0])) for loc in LOCALES))
    print('keys with placeholders (base): %d'
          % sum(1 for v in base_map.values() if PLACEHOLDER_RE.search(v)))
    issues = check(data)
    errors = [msg for lvl, msg in issues if lvl == 'ERROR']
    warns = [msg for lvl, msg in issues if lvl == 'WARN']
    for msg in errors:
        print('ERROR  ' + msg)
    for msg in warns:
        print('WARN   ' + msg)
    print('violations: %d error(s), %d warning(s)' % (len(errors), len(warns)))
    print()
    hist_rows, scatter = prefix_audit(sorted(base_map))
    print('prefix histogram (top %d of %d prefixes):'
          % (top_prefixes, len(hist_rows)))
    for row in hist_rows[:top_prefixes]:
        print('  ' + row)
    print()
    print('scattered prefixes (<= %d keys, rename candidates):' % SCATTER_THRESHOLD)
    for row in scatter:
        print('  ' + row)
    print('scattered prefix count: %d' % len(scatter))
    return 1 if errors else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='校验模式（违规 exit 1，pre-commit 调用）')
    ap.add_argument('--top-prefixes', type=int, default=20)
    args = ap.parse_args()

    data = {}
    for loc in LOCALES:
        data[loc] = load(loc)

    if args.check:
        issues = check(data)
        errors = [msg for lvl, msg in issues if lvl == 'ERROR']
        warns = [msg for lvl, msg in issues if lvl == 'WARN']
        for msg in errors:
            print('ERROR  ' + msg)
        for msg in warns:
            print('WARN   ' + msg)
        if errors:
            print('string guard FAILED: %d violation(s) in %s'
                  % (len(errors), ', '.join(LOCALES)))
            return 1
        print('OK: %s key sets consistent, placeholders consistent, no duplicates'
              % '/'.join(str(len(data[loc][0])) for loc in LOCALES))
        return 0

    return report(data, args.top_prefixes)


if __name__ == '__main__':
    sys.exit(main())
