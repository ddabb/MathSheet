# -*- coding: utf-8 -*-
"""字体覆盖护栏：rawfile 打印字体 cmap 必须覆盖资源全字符 + 数学/题面符号。

用法（Windows 需 py -3）：
  py -3 scripts/check_font_coverage.py            # 报告：字体信息 + 覆盖统计
  py -3 scripts/check_font_coverage.py --check    # 校验模式（pre-commit 调用，违规 exit 1）

背景（2026-10-23 缺陷复盘）：
- M2 时代入的 SourceHanSansSC-Regular.ttf 是裁剪子集，−(U+2212)/×(U+00D7)/÷(U+00F7)/□(U+25A1)
  字形本体缺失（非仅缺 cmap 映射），而 drawing.Font 单 typeface 无字形回退 →
  题卡位图运算符不渲染（OCR 实证 "93 38 ="）。E2E 全为 dump 文本断言，从未目视发现。
- 根因是子集化时字符集靠"当刻资源清单"推算，后续新增字符无护栏兜底。
- 本脚本在 pre-commit 强制：字体 cmap ⊇ 资源 string.json 全字符 ∪ 题面符号集 ∪ 可打印 ASCII，
  且文件体积不超过上限（防误用全量字体撑爆 HAP）。

当前字体：NotoSansSC-Regular.ttf（Noto Sans SC = 思源黑体 Google 分发版，OFL 1.1，
许可见 docs/licenses/NotoSansSC-OFL.txt；由 pyftsubset 裁剪，保留 name 表版权声明）。
"""
import argparse
import json
import os
import sys

try:
    from fontTools.ttLib import TTFont
except ImportError:
    print('ERROR  fonttools 未安装（py -3 -m pip install fonttools）')
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_PATH = os.path.join(ROOT, 'entry', 'src', 'main', 'resources',
                         'rawfile', 'font', 'NotoSansSC-Regular.ttf')
LOCALES = ['base', 'en']
STR_TPL = os.path.join(ROOT, 'entry', 'src', 'main', 'resources',
                       '%s', 'element', 'string.json')

# 题面/数学符号：ProblemGen.symbolOf 输出 −×÷+（U+2212/D7/F7/2B），题面 "=" 结尾，
# 填空占位 □（U+25A1），括号混合题 ()(U+28/29)，以及 SheetModel/资源文案用到的破折号。
REQUIRED_SYMBOLS = {
    0x2B: '+', 0x2212: '\u2212', 0x00D7: '\u00d7', 0x00F7: '\u00f7',
    0x3D: '=', 0x28: '(', 0x29: ')', 0x25A1: '\u25a1',
    0x2013: '\u2013', 0x2014: '\u2014',
}
# 可打印 ASCII（数字/大小写/标点/空格全量）
ASCII_RANGE = range(0x20, 0x7F)
# 体积上限：防误用全量静态字体（约 10.5MB）或未裁剪字重家族撑爆 HAP
MAX_FONT_BYTES = 8 * 1024 * 1024


def resource_chars():
    """资源 string.json（base/en）全字符集合。"""
    chars = set()
    for loc in LOCALES:
        path = STR_TPL % loc
        with open(path, 'r', encoding='utf-8-sig') as f:
            doc = json.load(f)
        for item in doc.get('string', []):
            chars.update(ord(c) for c in item.get('value', ''))
    return chars


def required_set():
    req = dict(REQUIRED_SYMBOLS)
    req.update({cp: chr(cp) for cp in ASCII_RANGE})
    req.update({cp: chr(cp) for cp in resource_chars()})
    return req


def fmt(cp, name):
    return 'U+%04X %r%s' % (cp, name, '' if name == chr(cp) else ' (%r)' % chr(cp))


def check(font_path):
    """返回 (ERROR 列表, WARN 列表, 统计信息 dict)。"""
    errors, warns = [], []
    info = {}
    if not os.path.isfile(font_path):
        return (['font missing: %s' % font_path], warns, info)
    size = os.path.getsize(font_path)
    info['size'] = size
    if size > MAX_FONT_BYTES:
        errors.append('font size %d bytes exceeds cap %d bytes (subset it: '
                      'pyftsubset ... --unicodes-file)' % (size, MAX_FONT_BYTES))
    font = TTFont(font_path)
    cmap = font.getBestCmap()
    info['cmap'] = len(cmap)
    req = required_set()
    info['required'] = len(req)
    missing = sorted(cp for cp in req if cp not in cmap)
    info['missing'] = len(missing)
    for cp in missing:
        errors.append('cmap missing %s (from %d-char required set)'
                      % (fmt(cp, req[cp]), len(req)))
    return errors, warns, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='校验模式（违规 exit 1，pre-commit 调用）')
    args = ap.parse_args()

    errors, warns, info = check(FONT_PATH)
    for msg in errors:
        print('ERROR  ' + msg)
    for msg in warns:
        print('WARN   ' + msg)

    if args.check:
        if errors:
            print('font guard FAILED: %d violation(s)' % len(errors))
            return 1
        print('OK: font %d bytes, cmap %d entries covers required %d chars '
              '(resource strings + symbols + ASCII)'
              % (info.get('size', 0), info.get('cmap', 0), info.get('required', 0)))
        return 0

    print('font: %s' % os.path.relpath(FONT_PATH, ROOT))
    print('size: %d bytes (cap %d)' % (info.get('size', 0), MAX_FONT_BYTES))
    print('cmap entries: %s' % info.get('cmap'))
    print('required chars: %s (resource strings %s symbols %d + ASCII %d)'
          % (info.get('required'), '', len(REQUIRED_SYMBOLS), len(list(ASCII_RANGE))))
    print('missing: %d' % info.get('missing', -1))
    print('violations: %d error(s)' % len(errors))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
