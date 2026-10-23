# -*- coding: utf-8 -*-
"""walkthrough_storyline.py — 商店截图故事线自动走查（§16 优化计划 P1，流程工具）。

在指定设备上自动重演 7 张商店截图故事线（同 §M6 手工流程，素材态与三端交付集一致），
每次点击前重新 dump 按文本解析坐标（根治每日卡 +52px 位移类陷阱），逐站截图。

故事线（产出 7 站 raw）：
  s1 生成器（每日一练已练态）  s2 题卡预览 1/N   s3 批改进行中（首题）
  s4 批改小结（对错各半）      s5 错题本（N 道）  s6 卷库（2 卷均批改）  s7 设置

素材态：成员"小明"；卷库 2 卷（20 题已批 20/20 错 10 + 50 题已批 50/50 错 25）；
错题本 10 道（50 题批改 25 道错先清空，再由 20 题批改产出 10 道）。

用法：
  py -3 scripts/walkthrough_storyline.py --profile tablet --device 127.0.0.1:15555 --fresh
  --profile tablet|2in1|phone   --device hdc 目标（127.0.0.1:port 会先 tconn）
  --fresh 卸载重装（干净素材态；重复跑务必带，否则卷库卡片会累积）
  --hap  安装包路径（默认 entry/build/default/outputs/default/entry-default-signed.hap）

产出：.shots/agc/<profile>_raw/sN_<name>_raw.jpeg
后续：tablet 原生 3:2 直接拷贝交付；2in1 跑 scripts/process_store_shots_2in1.js；
     完成后跑 scripts/check_shots_spec.py 校验。
"""
import argparse
import io
import json
import os
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

BUNDLE = "com.ddabb.mathsheet"
ABILITY = "EntryAbility"
HAP_DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                           "entry", "build", "default", "outputs", "default",
                           "entry-default-signed.hap")
SHOTS_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".shots", "agc")
DUMP_DEVICE = "/data/local/tmp/walk_dump.json"
SNAP_DEVICE = "/data/local/tmp/walk_snap.jpeg"

STATIONS = ["s1_generator", "s2_preview", "s3_grading", "s4_summary",
            "s5_mistakes", "s6_library", "s7_settings"]


class Device:
    def __init__(self, target: str):
        self.hdc = os.environ.get("HDC") or r"F:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
        self.target = target
        self.dump_local = os.path.join(os.environ.get("TEMP", "."), "deveco",
                                       f"walk_dump_{(target or 'local').replace(':', '_')}.json")

    def run(self, args: list, timeout: int = 90) -> str:
        cmd = [self.hdc] + (["-t", self.target] if self.target else []) + args
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace")
        return (p.stdout or "") + (p.stderr or "")

    def shell(self, s: str, timeout: int = 90) -> str:
        return self.run(["shell", s], timeout=timeout)

    # ---------- 采集 ----------

    def dump(self) -> list:
        """重新 dump 布局树（本地缓存先删，防陈旧 dump 陷阱；写盘竞态重试 3 次）。"""
        if os.path.exists(self.dump_local):
            os.remove(self.dump_local)
        last_err: Exception = RuntimeError("unreachable")
        for _ in range(3):
            self.shell(f"uitest dumpLayout -p {DUMP_DEVICE}")
            time.sleep(0.3)
            self.run(["file", "recv", DUMP_DEVICE, self.dump_local])
            try:
                with io.open(self.dump_local, encoding="utf-8") as f:
                    data = json.load(f)
                return data if isinstance(data, list) else [data]
            except Exception as e:
                last_err = e
                time.sleep(1.0)
        raise RuntimeError(f"dump 解析失败（重试 3 次）：{last_err}")

    def snap(self, out_path: str) -> None:
        self.shell(f"snapshot_display -f {SNAP_DEVICE}")
        self.run(["file", "recv", SNAP_DEVICE, out_path])
        size = os.path.getsize(out_path) if os.path.exists(out_path) else 0
        log(f"  SNAP {os.path.basename(out_path)} {size // 1024}KB")

    # ---------- 基元 ----------

    def click(self, cx: int, cy: int) -> None:
        self.shell(f"uitest uiInput click {cx} {cy}")

    def key(self, code: int) -> None:
        self.shell(f"uitest uiInput keyEvent {code}")

    def input_text(self, text: str) -> None:
        """已聚焦处注入文本：uitest uiInput text（inputText 子命令需 x y 坐标，勿混用）。"""
        self.shell(f"uitest uiInput text {text}")


def log(msg: str) -> None:
    print(msg, flush=True)


def walk(node: dict, out: list) -> list:
    a = node.get("attributes", {}) or {}
    text = (a.get("text") or "").strip()
    value = (a.get("value") or "").strip()
    if text or value:
        out.append({"text": text, "value": value, "bounds": a.get("bounds", ""),
                    "type": a.get("type", ""), "key": a.get("key", "")})
    for c in node.get("children", []) or []:
        walk(c, out)
    return out


def walk_keys(node: dict, out: list) -> list:
    a = node.get("attributes", {}) or {}
    if a.get("key"):
        out.append(a["key"])
    for c in node.get("children", []) or []:
        walk_keys(c, out)
    return out


def parse_bounds(b: str):
    try:
        left, rest = b.split("][")
        l, t = left.lstrip("[").split(",")
        r, bo = rest.rstrip("]").split(",")
        return int(l), int(t), int(r), int(bo)
    except Exception:
        return None


def center(b: str):
    p = parse_bounds(b)
    if p is None or p[2] <= p[0] or p[3] <= p[1]:
        return None
    return (p[0] + p[2]) // 2, (p[1] + p[3]) // 2


class Walker:
    """每次操作前重新 dump 按文本解析坐标 —— 不缓存坐标，天然免疫布局位移。"""

    def __init__(self, dev: Device, out_dir: str):
        self.dev = dev
        self.out_dir = out_dir

    def rows(self) -> list:
        """当前屏文本行；dump 瞬时失败容错为空（消费方均为轮询重试语义）。"""
        out: list = []
        try:
            for root in self.dev.dump():
                walk(root, out)
        except Exception as e:
            log(f"  (dump 重试耗尽，本轮按空处理：{e})")
        return out

    def screen_size(self) -> tuple:
        for root in self.dev.dump():
            p = parse_bounds((root.get("attributes") or {}).get("bounds", ""))
            if p and p[2] > 0 and p[3] > 0:
                return p[2], p[3]
        self.fail("无法获取屏幕尺寸（dump 根节点 bounds 缺失）")

    def is_desktop(self) -> bool:
        keys: list = []
        for root in self.dev.dump():
            walk_keys(root, keys)
        return any("SCBDesktop" in k for k in keys)

    def launch_app(self) -> None:
        """启动应用并确认 UI 出现：aa start 重试（安装后 BMS 就绪竞态），锁屏则上滑后重试。
        桌面判定靠 key=SCBDesktop（桌面 a11y 树图标无文本，不能按文本节点数判锁屏）。"""
        for _ in range(6):
            out = self.dev.shell(f"aa start -a {ABILITY} -b {BUNDLE}").strip()
            log(f"  aa start: {out}")
            t0 = time.time()
            while time.time() - t0 < 8:
                if self.find("生成题卡"):
                    return
                time.sleep(1.2)
            if not self.is_desktop():
                sw, sh = self.screen_size()
                self.dev.shell(f"uitest uiInput swipe {sw // 2} {int(sh * 0.9)} "
                               f"{sw // 2} {int(sh * 0.1)} 500")
                time.sleep(2.5)
        self.fail("应用启动失败：aa start 重试 6 轮仍无应用 UI")

    def find(self, kw: str, exact: bool = False, attr: str = "text") -> list:
        hits = []
        for r in self.rows():
            v = r[attr]
            if (exact and v == kw) or (not exact and kw in v):
                c = center(r["bounds"])
                if c:
                    hits.append({**r, "cx": c[0], "cy": c[1]})
        return hits

    def wait_for(self, kw: str, timeout: float = 40, exact: bool = False,
                 attr: str = "text") -> list:
        t0 = time.time()
        while time.time() - t0 < timeout:
            hits = self.find(kw, exact, attr)
            if hits:
                return hits
            time.sleep(1.2)
        self.fail(f"等待超时 {timeout}s：找不到 [{kw}]（exact={exact}）")

    def wait_gone(self, kw: str, timeout: float = 20, exact: bool = False) -> None:
        t0 = time.time()
        while time.time() - t0 < timeout:
            if not self.find(kw, exact):
                return
            time.sleep(1.0)
        self.fail(f"等待消失超时：[{kw}] 仍在")

    def tap(self, kw: str, exact: bool = False, idx: int = 0, verify: bool = True) -> dict:
        hits = self.wait_for(kw, exact=exact) if verify else self.find(kw, exact)
        if len(hits) <= idx:
            self.fail(f"[{kw}] 命中 {len(hits)} 个，取第 {idx} 个越界")
        h = hits[idx]
        self.dev.click(h["cx"], h["cy"])
        log(f"  TAP ({h['cx']},{h['cy']}) <- [{h['text'][:24] or h['value'][:24]}]")
        return h

    def tap_y_sorted(self, kw: str, idx: int, exact: bool = False) -> dict:
        hits = sorted(self.wait_for(kw, exact=exact), key=lambda h: h["cy"])
        if len(hits) <= idx:
            self.fail(f"[{kw}] 命中 {len(hits)} 个，取第 {idx} 个越界")
        h = hits[idx]
        self.dev.click(h["cx"], h["cy"])
        log(f"  TAP ({h['cx']},{h['cy']}) <- [{h['text'][:24]}] (y 序第 {idx})")
        return h

    def clear_and_type(self, new_text: str) -> None:
        """定位当前屏唯一 TextInput：清空后输入。占位文案不进 a11y 树，故按 type 定位。
        退格次数 = 当前 value 长度（读不到则 12 兜底）；KEYCODE_DEL = 2055。"""
        hits: list = []
        t0 = time.time()
        while time.time() - t0 < 20:
            hits = [r for r in self.rows() if r["type"] == "TextInput"]
            if hits:
                break
            time.sleep(1.0)
        if not hits:
            self.fail("找不到 TextInput 输入域")
        node = hits[0]
        # 预填内容在 text 或 value 属性（不同时机暴露不同），两者择长；全空则 12 兜底
        n = len(node["value"] or node["text"]) or 12
        c = center(node["bounds"])
        if c is None:
            self.fail(f"TextInput bounds 异常：{node['bounds']}")
        self.dev.click(c[0], c[1])
        for _ in range(n + 4):
            self.dev.key(2055)
        self.dev.input_text(new_text)
        log(f"  TYPE [{new_text}]（清退 {n} 字）")

    def snap(self, station: str, settle: float = 1.5) -> None:
        time.sleep(settle)
        self.dev.snap(os.path.join(self.out_dir, f"{station}_raw.jpeg"))

    def fail(self, msg: str) -> None:
        log(f"FAIL: {msg}")
        log("--- 当前屏幕全部文本（排查用） ---")
        for r in self.rows():
            if r["text"] or r["value"]:
                log(f"  [{r['type']}] {r['bounds']} text={r['text'][:30]} value={r['value'][:20]}")
        sys.exit(1)


def grade_current(w: Walker, right_n: int, wrong_n: int) -> None:
    """批改当前卷：交替标记 对/错 各 N 次，直到批改完成页；小结页校验『共 N 题』防错卷。"""
    w.wait_for("已批")
    right = w.wait_for("对", exact=True)[0]
    wrong = w.wait_for("错", exact=True)[0]
    total = right_n + wrong_n
    for i in range(total):
        btn = right if i % 2 == 0 else wrong
        w.dev.click(btn["cx"], btn["cy"])
        time.sleep(0.25)
    w.wait_for("批改完成", timeout=60)
    w.wait_for(f"共 {total} 题")
    log(f"  批改完成：对 {right_n} / 错 {wrong_n}（共 {total}）")


def run_story(dev: Device, profile: str, fresh: bool, hap: str) -> None:
    out_dir = os.path.join(SHOTS_ROOT, f"{profile}_raw")
    os.makedirs(out_dir, exist_ok=True)
    w = Walker(dev, out_dir)

    if fresh:
        log("== 卸载重装（干净素材态） ==")
        dev.run(["uninstall", BUNDLE], timeout=120)
        out = dev.run(["install", hap], timeout=180)
        log("  install: " + (out.strip().splitlines()[-1] if out.strip() else ""))
        if "fail" in out.lower():
            log(f"FAIL: 安装失败：{out}")
            sys.exit(1)
        time.sleep(2)

    log("== 熄屏超时覆写 1h（恢复态模拟器自动锁屏极快，防走查中断） ==")
    dev.shell("power-shell timeout -o 3600000")

    log("== 启动应用 ==")
    w.launch_app()

    if profile == "2in1":
        # ContainerModal 窗口双击标题栏最大化（仅首启窗口态需要；已最大化勿重复执行）
        b = center(w.wait_for("生成题卡")[0]["bounds"])
        dev.shell(f"uitest uiInput doubleClick {b[0] if b else 1560} 316")
        time.sleep(2)
        w.wait_for("生成题卡")

    log("== 改名：默认 -> 小明 ==")
    w.tap("设置", exact=True)
    w.tap("改名")
    w.wait_for("确定", exact=True)
    w.clear_and_type("小明")
    w.tap("确定", exact=True)
    w.wait_for("小明")
    w.wait_gone("确定")

    log("== 生成 50 题卷（默认配置） ==")
    w.tap("生成", exact=True)
    w.tap("生成题卡")
    w.wait_for("导出 PDF")
    w.tap("返回")
    w.wait_for("生成题卡")

    log("== 题数 20 生成 + s2 预览 ==")
    w.tap("20", exact=True)
    w.tap("生成题卡")
    w.wait_for("导出 PDF")
    w.snap("s2_preview")
    w.tap("返回")
    w.wait_for("生成题卡")

    log("== 批改 50 题卷（对 25 / 错 25） ==")
    w.tap("卷库", exact=True)
    w.wait_for("批改")
    w.tap_y_sorted("批改", idx=1, exact=True)  # 精确匹配按钮：防"未批改"meta 含"批改"污染 y 序
    w.wait_for("已批 0 / 50")
    grade_current(w, 25, 25)
    w.tap("返回")
    w.wait_for("批改")

    log("== 清空错题本（50 题卷的 25 道） ==")
    w.tap("错题本", exact=True)
    w.wait_for("清空错题本")
    w.tap("清空错题本")
    w.wait_for("不可恢复")
    w.tap("清空", exact=True)
    w.wait_gone("不可恢复")
    w.wait_for("错题会收进", timeout=30)

    log("== 批改 20 题卷（对 10 / 错 10）+ s3/s4 ==")
    w.tap("卷库", exact=True)
    w.wait_for("批改")
    w.tap_y_sorted("批改", idx=0, exact=True)  # 最新 = 20 题卷
    w.wait_for("已批 0 / 20")
    w.snap("s3_grading")
    grade_current(w, 10, 10)
    w.snap("s4_summary")
    w.tap("返回")
    w.wait_for("批改")

    log("== 收尾站点截图 s1/s5/s6/s7 ==")
    w.tap("生成", exact=True)
    w.wait_for("生成题卡")
    w.snap("s1_generator")
    w.tap("错题本", exact=True)
    w.wait_for("清空错题本")
    w.snap("s5_mistakes")
    w.tap("卷库", exact=True)
    w.wait_for("批改")
    w.snap("s6_library")
    w.tap("设置", exact=True)
    w.wait_for("改名")
    w.snap("s7_settings")

    log(f"== 完成：7 站 raw 已存 {out_dir} ==")
    log("后续：tablet 直接拷贝交付；2in1 跑 process_store_shots_2in1.js；"
        "最后跑 py scripts/check_shots_spec.py 校验")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--profile", required=True, choices=["tablet", "2in1", "phone"])
    ap.add_argument("--device", default="", help="hdc 目标（空=唯一设备）")
    ap.add_argument("--fresh", action="store_true", help="卸载重装（重复跑必带）")
    ap.add_argument("--hap", default=HAP_DEFAULT)
    args = ap.parse_args()

    if args.device.startswith("127.0.0.1:"):
        dev = Device(args.device)
        log(f"tconn {args.device}：{dev.run(['tconn', args.device]).strip()}")
    else:
        dev = Device(args.device)
    if args.fresh and not os.path.exists(args.hap):
        log(f"FAIL: HAP 不存在 {args.hap}")
        return 1
    run_story(dev, args.profile, args.fresh, args.hap)
    return 0


if __name__ == "__main__":
    sys.exit(main())
