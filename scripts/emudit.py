# -*- coding: utf-8 -*-
"""emudit.py —— 模拟器/真机 UI 调试工具箱（1.4.9 M5-C2，沉淀 1.4.8-1.4.9 调试期临时脚本）

工具化范围：find_entry.py / find_node.py（节点检索）、dump_cc.py（可读树）、ui_band.py
（y 带交集）、ui_walk.py（JSON 输出 + 可点击祖先链）、punct_px*.py（像素采样/暗带扫描）、
ab_compare.py（树结构 diff）。调试期一次性脚本请勿再复制粘贴，直接用本工具。

== 采集协议（喂给本工具的文件怎么来） ==
  布局树(JSON)：
    devecocli ui layout --format json --mode full > dump.json
      （只含可见区节点——目标须先滚动到屏内；窗口默认聚焦窗口，--all-windows 看全部）
    或 hdc shell uitest dumpLayout && hdc file recv /data/local/tmp/layout.json dump.json
  截图：
    devecocli ui screenshot --path shot.png
    或 hdc shell snapshot_display -f /data/local/tmp/shot.jpeg   <- 后缀必须 .jpeg
      && hdc file recv /data/local/tmp/shot.jpeg shot.jpeg
  已知坑位（详见 docs/1.4.9开发计划 §2.3）：
    - dumpLayout 输出是 JSON 非 XML；3D 旋转容器下部节点会被丢弃（渲染正常仅采集缺失）
    - toast/ComponentContent 渲染于子窗口，不进 a11y 树 —— 验证协议=像素 bbox（px --diff）
    - hilog 重定向含 UTF-16 间隔字符：grep -a + strip \\x00
    - uinput -T -M 无效组合静默失败（滑动用 -T -m）；-m 起终点有幻影点击
    - 文本清空不可靠：keyEvent BackSpace 不生效、inputText 为追加式（靠 maxLength 兜底）
    - 窗口号应用重启即变，须 hidumper 重查

== 用法（py -3 scripts/emudit.py <cmd> ...） ==
  find <dump.json> [-t 文本子串] [-k key子串] [-i id子串] [--band y0,y1]
       [--json] [--center] [--first]
      节点检索：-t/-k/-i 可组合（任一命中即列出，均不给=列出全部含 text/key 节点）；
      --band 按纵向带过滤；--center 只输出首个命中中心点 "cx,cy"（管道友好）；
      --json 每行一个 JSON（含中心点/可点击祖先链，兼容 ui_walk 消费方式）
      例：py -3 scripts/emudit.py find dump.json -t 生字卡 --center
  band <dump.json> --y0 N --y1 N
      y 带交集子树预览（chip 行/工具栏定位）
  tree <dump.json> [--depth N]
      全树可读预览（缩进层级、type/text/key/bounds/clickable）
  px <img> [--box x1,y1,x2,y2] [--thr 300] [--scan row|col] [--diff <img2>] [--tol 10]
      像素采样：--box 区域统计（尺寸/均值/暗像素数，暗=RGB 和<thr）；
      --scan row|col 逐行/逐列暗像素计数（暗带定位：toast bbox、格线检测）；
      --diff 同区域两图差异：差异像素数 + 差异 bbox（无差异输出 None，A/B 回归判据）
      例：py -3 scripts/emudit.py px a.png --diff b.png --box 0,2100,1280,2300
      （px 需 PIL：py -3 -m pip install pillow）

== 实战链路 ==
  1. dump 采集 → find -t 目标文本 --center → 拿 "cx,cy"
  2. 点击：devecocli ui click CX CY（或 hdc shell uitest uiInput click CX CY）
  3. 前后各截一张图 → px --diff 比对（预期区域变化/其余 0 像素）
  4. 结构回归：两份 dump → find/band 比对（或本目录 ui_walk.py 兼容消费 --json 输出）
"""
import argparse
import json
import re
import sys


def _utf8_stdout():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass


def load_dump(path):
    """载入布局树 JSON：顶层可为数组或对象；容忍 BOM 与 CLI 夹带的非 JSON 横幅。"""
    with open(path, 'r', encoding='utf-8-sig') as f:
        txt = f.read()
    txt = txt.strip()
    try:
        return json.loads(txt)
    except ValueError:
        pass
    start = txt.find('[')
    end = txt.rfind(']')
    if start >= 0 and end > start:
        return json.loads(txt[start:end + 1])
    start = txt.find('{')
    end = txt.rfind('}')
    if start >= 0 and end > start:
        return json.loads(txt[start:end + 1])
    raise SystemExit('[emudit] no JSON payload found in %s' % path)


def node_attrs(node):
    """归一化节点：uitest dumpLayout 为 {attributes:{...},children}，devecocli ui layout 为平铺。"""
    a = node.get('attributes')
    if isinstance(a, dict):
        return a
    return node


def parse_bounds(b):
    """bounds 归一化为 [x1,y1,x2,y2]：兼容 '[278,474][371,583]' 字符串与 [x1,y1,x2,y2] 数组。"""
    if isinstance(b, (list, tuple)) and len(b) == 4:
        try:
            return [int(b[0]), int(b[1]), int(b[2]), int(b[3])]
        except (TypeError, ValueError):
            return None
    if isinstance(b, str):
        m = re.findall(r'-?\d+', b)
        if len(m) >= 4:
            return [int(x) for x in m[:4]]
    return None


def center_of(bounds):
    return (bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2


def walk_roots(roots):
    """展开根列表为 (attrs, node, parents) 序列，保留父链供可点击祖先检索。"""
    stack = [(r, []) for r in roots] if isinstance(roots, list) else [(roots, [])]
    while stack:
        node, parents = stack.pop()
        if not isinstance(node, dict):
            continue
        yield node_attrs(node), node, parents
        children = node.get('children') or []
        for c in children:
            stack.append((c, parents + [node]))


def in_band(bounds, y0, y1):
    return bounds is not None and not (bounds[3] < y0 or bounds[1] > y1)


def clickable_ancestor(parents):
    for p in reversed(parents):
        a = node_attrs(p)
        if a.get('clickable') and str(a.get('clickable')).lower() in ('true', '1'):
            return a
    return None


def brief(v, n):
    s = '' if v is None else str(v)
    return s if len(s) <= n else s[:n] + '~'


def cmd_find(args):
    roots = load_dump(args.dump)
    y0, y1 = (args.band if args.band else (None, None))
    hits = []
    for a, _node, parents in walk_roots(roots):
        text = a.get('text') or ''
        key = a.get('key') or ''
        desc = a.get('description') or ''
        nid = str(a.get('id') or '')
        if args.text and args.text not in str(text) + str(desc):
            continue
        if args.key and args.key not in str(key):
            continue
        if args.id and args.id not in nid:
            continue
        if not (args.text or args.key or args.id):
            if not (text or key or desc):
                continue
        bounds = parse_bounds(a.get('bounds'))
        if y0 is not None and not in_band(bounds, y0, y1):
            continue
        hits.append((a, bounds, parents))
    if args.center:
        if not hits:
            raise SystemExit('[emudit] no match')
        c = center_of(hits[0][1]) if hits[0][1] else None
        print('%d,%d' % c if c else 'NO_BOUNDS')
        return
    if args.first and hits:
        hits = hits[:1]
    for a, bounds, parents in hits:
        cx, cy = center_of(bounds) if bounds else (None, None)
        if args.json:
            ca = clickable_ancestor(parents)
            print(json.dumps({
                'text': a.get('text') or '', 'key': a.get('key') or '',
                'id': a.get('id'), 'type': a.get('type'),
                'bounds': bounds, 'center': [cx, cy],
                'clickable': a.get('clickable'),
                'clickable_ancestor': ({
                    'id': ca.get('id'), 'type': ca.get('type'),
                    'bounds': parse_bounds(ca.get('bounds'))} if ca else None)},
                ensure_ascii=False))
        else:
            print('type=%-14s text=%-30r key=%-26r id=%-10r bounds=%s center=%s clickable=%s' % (
                brief(a.get('type'), 14), brief(a.get('text'), 28), brief(a.get('key'), 24),
                brief(a.get('id'), 10), bounds,
                ('%d,%d' % (cx, cy)) if cx is not None else '?', a.get('clickable')))
    print('total: %d' % len(hits), file=sys.stderr)


def cmd_band(args):
    roots = load_dump(args.dump)
    for a, _node, _parents in walk_roots(roots):
        bounds = parse_bounds(a.get('bounds'))
        if in_band(bounds, args.y0, args.y1):
            print('type=%-14s id=%-10r text=%-24r key=%-20r bounds=%s clickable=%s' % (
                brief(a.get('type'), 14), brief(a.get('id'), 10), brief(a.get('text'), 22),
                brief(a.get('key'), 18), bounds, a.get('clickable')))


def cmd_tree(args):
    roots = load_dump(args.dump)
    out = []

    def rec(node, depth):
        if not isinstance(node, dict):
            return
        a = node_attrs(node)
        if args.depth and depth > args.depth:
            return
        bounds = parse_bounds(a.get('bounds'))
        cx, cy = center_of(bounds) if bounds else (None, None)
        out.append('%stype=%-14s id=%-10r text=%-26r key=%-20r bounds=%s center=%s click=%s' % (
            '  ' * depth, brief(a.get('type'), 14), brief(a.get('id'), 10),
            brief(a.get('text'), 24), brief(a.get('key'), 18), bounds,
            ('%d,%d' % (cx, cy)) if cx is not None else '?', a.get('clickable')))
        for c in node.get('children') or []:
            rec(c, depth + 1)

    for r in (roots if isinstance(roots, list) else [roots]):
        rec(r, 0)
    print('\n'.join(out) if out else '(empty tree)')


def _require_pil():
    try:
        from PIL import Image  # noqa: F401
        return True
    except ImportError:
        print('[emudit] px 命令需要 Pillow：py -3 -m pip install pillow', file=sys.stderr)
        return False


def _img_open(path):
    from PIL import Image
    return Image.open(path).convert('RGB')


def _pixels(region):
    """像素序列（兼容 Pillow 14：getdata 弃用改 get_flattened_data）。"""
    try:
        return list(region.get_flattened_data())
    except AttributeError:
        return list(region.getdata())


def _box_of(args, img_size):
    if args.box:
        b = [int(x) for x in args.box.split(',')]
        if len(b) != 4:
            raise SystemExit('[emudit] --box 需要 x1,y1,x2,y2')
        return tuple(b)
    return (0, 0, img_size[0], img_size[1])


def cmd_px(args):
    if not _require_pil():
        return
    img = _img_open(args.image)
    box = _box_of(args, img.size)
    region = img.crop(box)
    if args.diff:
        other = _img_open(args.diff).crop(box)
        if region.size != other.size:
            raise SystemExit('[emudit] 两图区域尺寸不一致: %s vs %s' % (region.size, other.size))
        pa, pb = _pixels(region), _pixels(other)
        diff_px = []
        for i, (p, q) in enumerate(zip(pa, pb)):
            if abs(p[0] - q[0]) + abs(p[1] - q[1]) + abs(p[2] - q[2]) > args.tol:
                diff_px.append(i)
        if not diff_px:
            print(json.dumps({'box': list(box), 'diff_count': 0, 'diff_bbox': None}))
            return
        w = region.size[0]
        xs = [i % w + box[0] for i in diff_px]
        ys = [i // w + box[1] for i in diff_px]
        bbox = [min(xs), min(ys), max(xs), max(ys)]
        print(json.dumps({'box': list(box), 'diff_count': len(diff_px), 'diff_bbox': bbox}))
        return
    if args.scan:
        w, h = region.size
        darks = []
        if args.scan == 'row':
            for y in range(h):
                darks.append(sum(1 for x in range(w)
                                 if sum(region.getpixel((x, y))) < args.thr))
            print(json.dumps({'box': list(box), 'scan': 'row',
                              'first_y': box[1], 'dark_counts': darks}))
        else:
            for x in range(w):
                darks.append(sum(1 for y in range(h)
                                 if sum(region.getpixel((x, y))) < args.thr))
            print(json.dumps({'box': list(box), 'scan': 'col',
                              'first_x': box[0], 'dark_counts': darks}))
        return
    pixels = _pixels(region)
    dark = sum(1 for p in pixels if sum(p) < args.thr)
    light = sum(1 for p in pixels if sum(p) >= args.thr)
    mean = [round(sum(p[i] for p in pixels) / len(pixels)) for i in range(3)] if pixels else []
    print(json.dumps({'box': list(box), 'size': list(region.size), 'mean_rgb': mean,
                      'dark_px': dark, 'light_px': light, 'thr': args.thr}))


def main():
    _utf8_stdout()
    ap = argparse.ArgumentParser(prog='emudit.py', description='模拟器/真机 UI 调试工具箱（详见模块 docstring）',
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('find', help='节点检索：text/key/id 子串 + y 带 + 中心点')
    p.add_argument('dump')
    p.add_argument('-t', '--text')
    p.add_argument('-k', '--key')
    p.add_argument('-i', '--id')
    p.add_argument('--band', type=str, help='y0,y1 纵向带过滤')
    p.add_argument('--json', action='store_true', help='每行一个 JSON（含中心点/可点击祖先）')
    p.add_argument('--center', action='store_true', help='只输出首个命中中心点 cx,cy')
    p.add_argument('--first', action='store_true', help='只输出首个命中')
    p.set_defaults(func=cmd_find)

    p = sub.add_parser('band', help='y 带交集节点预览')
    p.add_argument('dump')
    p.add_argument('--y0', type=int, required=True)
    p.add_argument('--y1', type=int, required=True)
    p.set_defaults(func=cmd_band)

    p = sub.add_parser('tree', help='全树可读预览')
    p.add_argument('dump')
    p.add_argument('--depth', type=int, default=0, help='最大层级（0=不限）')
    p.set_defaults(func=cmd_tree)

    p = sub.add_parser('px', help='像素采样：区域统计/暗带扫描/两图差异 bbox')
    p.add_argument('image')
    p.add_argument('--box', type=str, help='x1,y1,x2,y2（缺省全图）')
    p.add_argument('--thr', type=int, default=300, help='暗像素阈值（RGB 和 < thr），默认 300')
    p.add_argument('--scan', choices=['row', 'col'], help='逐行/逐列暗像素计数')
    p.add_argument('--diff', type=str, help='对比图路径：输出差异像素数 + 差异 bbox')
    p.add_argument('--tol', type=int, default=10, help='diff 通道和容差，默认 10')
    p.set_defaults(func=cmd_px)

    args = ap.parse_args()
    if getattr(args, 'band', None):
        parts = args.band.split(',')
        args.band = (int(parts[0]), int(parts[1]))
    args.func(args)


if __name__ == '__main__':
    main()
