# -*- coding: utf-8 -*-
"""E2E 助手：按文本点按 / 快照 / dump 摘要。

用法：
  py -3 scripts/dev_tap.py tap "生成口算题卡"     # 点击第一个含关键词的文本中心
  py -3 scripts/dev_tap.py tap "二年级" --all      # 若有歧义则列出全部匹配
  py -3 scripts/dev_tap.py snap 01_preview         # 快照到 .shots/01_preview.jpeg
  py -3 scripts/dev_tap.py texts                   # dump 并打印全部文本+bounds
"""
import io
import json
import os
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

TMP = r"C:\Users\60138546\AppData\Local\Temp\deveco"
DUMP_DEVICE = "/data/local/tmp/dev_dump.json"
DUMP_LOCAL = os.path.join(TMP, "dev_dump.json")
SHOTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".shots")


def run(cmd: list, timeout: int = 60) -> str:
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                       encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    return out


def hdc(*args: str, timeout: int = 60) -> str:
    return run(["hdc", "shell", " ".join(args)], timeout=timeout)


def dump() -> list:
    hdc("uitest dumpLayout -p " + DUMP_DEVICE)
    run(["hdc", "file", "recv", DUMP_DEVICE, DUMP_LOCAL], timeout=60)
    with io.open(DUMP_LOCAL, encoding="utf-8") as f:
        return [json.load(f)]


def walk(node, out):
    a = node.get("attributes", {})
    t = (a.get("text") or "").strip()
    if t:
        out.append({"bounds": a.get("bounds", ""), "text": t})
    for c in node.get("children", []) or []:
        walk(c, out)
    return out


def parse_bounds(b: str):
    try:
        left, rest = b.split("][")
        l, t = left.lstrip("[").split(",")
        r, bo = rest.rstrip("]").split(",")
        return int(l), int(t), int(r), int(bo)
    except Exception:
        return None


def cmd_tap(kw: str, show_all: bool) -> None:
    rows = []
    for root in dump():
        walk(root, rows)
    hits = [r for r in rows if kw in r["text"]]
    if not hits:
        print("NO_HIT")
        return
    if show_all:
        for h in hits:
            print(h["bounds"], h["text"][:40])
        return
    b = parse_bounds(hits[0]["bounds"])
    if b is None:
        print("BAD_BOUNDS", hits[0])
        return
    cx = (b[0] + b[2]) // 2
    cy = (b[1] + b[3]) // 2
    hdc(f"uinput -T -c {cx} {cy}")
    print(f"TAP {cx},{cy} <- [{hits[0]['text'][:30]}]")


def cmd_snap(name: str) -> None:
    os.makedirs(SHOTS_DIR, exist_ok=True)
    hdc("snapshot_display -f /data/local/tmp/dev_snap.jpeg")
    out = os.path.join(SHOTS_DIR, name + ".jpeg")
    run(["hdc", "file", "recv", "/data/local/tmp/dev_snap.jpeg", out], timeout=60)
    size = os.path.getsize(out) if os.path.exists(out) else 0
    print(f"SNAP {out} {size}B")


def cmd_texts() -> None:
    rows = []
    for root in dump():
        walk(root, rows)
    for r in rows:
        print(r["bounds"], r["text"][:60])


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    action = sys.argv[1]
    if action == "tap":
        cmd_tap(sys.argv[2], "--all" in sys.argv)
    elif action == "snap":
        cmd_snap(sys.argv[2])
    elif action == "texts":
        cmd_texts()
    else:
        print("unknown action")
