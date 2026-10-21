"""E2E 布局树检索（uitest dumpLayout 产物 → 控件中心坐标）。

用法：
  py -3 scripts/find_ui.py <dump.json> <关键词> [--all]
    默认输出首个匹配节点；--all 输出全部匹配。
  坐标输出格式 "cx cy"（供 hdc shell uitest uiInput click cx cy）。

  hdc shell uitest dumpLayout -p /data/local/tmp/e2e.json
  hdc file recv /data/local/tmp/e2e.json <本地路径>
"""

import json
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BOUNDS_RE = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def center(bounds: str):
    m = BOUNDS_RE.match(bounds.replace(" ", ""))
    if not m:
        return None
    x1, y1, x2, y2 = (int(v) for v in m.groups())
    if x2 <= x1 or y2 <= y1:
        return None
    return (x1 + x2) // 2, (y1 + y2) // 2


def texts_of(attrs: dict) -> str:
    parts = [attrs.get("text", ""), attrs.get("originalText", ""),
             attrs.get("description", ""), attrs.get("id", ""), attrs.get("key", "")]
    return " ".join(str(p) for p in parts if p)


def walk(node, keyword, out):
    attrs = node.get("attributes", {})
    if keyword in texts_of(attrs):
        c = center(str(attrs.get("bounds", "")))
        out.append((attrs.get("type", ""), texts_of(attrs).strip()[:60],
                    attrs.get("bounds", ""), c))
    for child in node.get("children", []):
        walk(child, keyword, out)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    path, keyword = sys.argv[1], sys.argv[2]
    show_all = "--all" in sys.argv
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    out = []
    walk(data, keyword, out)
    if not out:
        print(f"NOT_FOUND: {keyword}")
        sys.exit(1)
    picked = out if show_all else out[:1]
    for typ, txt, bounds, c in picked:
        if c is None:
            print(f"{typ} | {txt} | {bounds} | NO_COORD")
        else:
            print(f"{typ} | {txt} | {bounds} | CLICK {c[0]} {c[1]}")


if __name__ == "__main__":
    main()
