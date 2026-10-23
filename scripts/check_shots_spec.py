# -*- coding: utf-8 -*-
"""check_shots_spec.py — AGC 商店截图规格校验（§16 优化计划 P2 交付护栏）。

按前缀分类校验 .shots/agc/ 下交付截图是否符合 AGC 上架规格（计划 §M6）：
  phone_*   手机竖屏：9:16（w/h=0.5625），尺寸 ≥1080×1920（短边 ≥1080）
  tablet_*  平板横屏：3:2（w/h=1.5），尺寸 ≥1920×1280
  2in1_*    PC/2in1：16:9（w/h≈1.778），尺寸 ≥1920×1080
通用：每类目 3-10 张；JPEG/PNG；单张 ≤5MB。

用法：py scripts/check_shots_spec.py [--dir .shots/agc]
素材不入 git，故不接 pre-commit；作为交付前清单工具（重拍素材后必跑）。
"""
import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    print("需要 Pillow：py -3 -m pip install pillow")
    sys.exit(2)

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

MAX_BYTES = 5 * 1024 * 1024
COUNT_MIN, COUNT_MAX = 3, 10
RATIO_TOL = 0.01

CATEGORIES = [
    ("phone", 9 / 16, (1080, 1920)),
    ("tablet", 3 / 2, (1920, 1280)),
    ("2in1", 16 / 9, (1920, 1080)),
]


def check_one(path: str, ratio: float, min_w: int, min_h: int) -> list:
    errs = []
    size = os.path.getsize(path)
    if size > MAX_BYTES:
        errs.append(f"大小 {size}B 超 5MB 上限")
    try:
        with Image.open(path) as img:
            w, h = img.size
            fmt = (img.format or "").upper()
    except Exception as e:
        return [f"无法解析: {e}"]
    if fmt not in ("JPEG", "PNG"):
        errs.append(f"格式 {fmt} 非 JPEG/PNG")
    if w < min_w or h < min_h:
        errs.append(f"尺寸 {w}x{h} 低于 {min_w}x{min_h}")
    if abs(w / h - ratio) > RATIO_TOL:
        errs.append(f"比例 {w / h:.4f} 偏离 {ratio:.4f}")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".shots", "agc"))
    args = ap.parse_args()
    root = os.path.abspath(args.dir)

    total_err = 0
    for prefix, ratio, (mw, mh) in CATEGORIES:
        files = sorted(f for f in os.listdir(root)
                       if f.startswith(prefix + "_") and f.lower().endswith((".jpg", ".jpeg", ".png"))
                       ) if os.path.isdir(root) else []
        if not files:
            print(f"[{prefix}] 无素材（本类目未交付则忽略）")
            continue
        if not (COUNT_MIN <= len(files) <= COUNT_MAX):
            print(f"[{prefix}] 张数 {len(files)} 不在 {COUNT_MIN}-{COUNT_MAX}")
            total_err += 1
        for f in files:
            errs = check_one(os.path.join(root, f), ratio, mw, mh)
            kb = os.path.getsize(os.path.join(root, f)) // 1024
            if errs:
                total_err += 1
                print(f"[{prefix}] FAIL {f} ({kb}KB): " + "; ".join(errs))
            else:
                print(f"[{prefix}] OK   {f} ({kb}KB)")
    print(f"\n{'FAIL: ' + str(total_err) + ' 处违规' if total_err else '全部符合 AGC 规格'}")
    return 1 if total_err else 0


if __name__ == "__main__":
    sys.exit(main())
