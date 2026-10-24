# -*- coding: utf-8 -*-
"""walkthrough_storyline.py — 商店截图故事线自动走查（§16 优化计划 P1，流程工具）。

在指定设备上自动重演 7 张商店截图故事线（同 §M6 手工流程，素材态与三端交付集一致），
每次点击前重新 dump 按文本解析坐标（根治每日卡 +52px 位移类陷阱），逐站截图。

故事线（产出 7 站 raw）：
  s1 生成器（每日一练已练态）  s2 题卡预览 1/N   s3 在线作答（第 2 题输入中）
  s4 在线作答结果页            s5 错题本（N 道）  s6 卷库（2 卷均批改）  s7 设置

素材态：成员"小明"；卷库 2 卷（20 题卷在线作答批 对 15/错 5 + 50 题卷手动批 对 25/错 25·5 分）；
错题本 5 道（50 题批改 25 道错先清空，再由在线作答 5 道错产出）。

用法：
  py -3 scripts/walkthrough_storyline.py --profile tablet --device 127.0.0.1:15555 --fresh
  --profile tablet|2in1|phone   --device hdc 目标（127.0.0.1:port 会先 tconn）
  --fresh 卸载重装（干净素材态；重复跑务必带，否则卷库卡片会累积）
  --hap  安装包路径（默认 entry/build/default/outputs/default/entry-default-signed.hap）

产出：.shots/agc/<profile>_raw/sN_<name>_raw.jpeg
后续：tablet 原生 3:2 直接拷贝交付；2in1 跑 scripts/process_store_shots_2in1.js；
      phone 拷 .shots/phone_s*.jpeg 后跑 scripts/process_store_shots.js；
      完成后跑 scripts/check_shots_spec.py 校验。
"""
import argparse
import io
import json
import os
import re
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

STATIONS = ["s1_generator", "s2_preview", "s3_quiz", "s4_quiz_result",
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

    def tap_scroll(self, kw: str, exact: bool = False, idx: int = 0, rounds: int = 6) -> dict:
        """点选目标：当前屏未见则逐屏上滑滚动表单直至出现（手机竖屏表单超一屏）。
        平板/2in1 一屏放得下则零滑动，行为与 tap 一致。"""
        hits = self.find(kw, exact)
        sw, sh = self.screen_size()
        for _ in range(rounds):
            if hits:
                break
            self.dev.shell(f"uitest uiInput swipe {sw // 2} {int(sh * 0.62)} "
                           f"{sw // 2} {int(sh * 0.38)} 400")
            time.sleep(1.2)
            hits = self.find(kw, exact)
        if len(hits) <= idx:
            self.fail(f"[{kw}] 滚动查找未命中（exact={exact}）")
        h = hits[idx]
        self.dev.click(h["cx"], h["cy"])
        log(f"  TAP ({h['cx']},{h['cy']}) <- [{h['text'][:24]}]（滚动定位）")
        return h

    def scroll_top(self, anchor: str = "每日一练", rounds: int = 6) -> None:
        """回滚表单至顶（锚点可见即止）：滚动选过题数后，收尾 s1 截图须回表单顶部。
        平板/2in1 锚点本就可见，零滑动。"""
        for _ in range(rounds):
            if self.find(anchor):
                return
            sw, sh = self.screen_size()
            self.dev.shell(f"uitest uiInput swipe {sw // 2} {int(sh * 0.38)} "
                           f"{sw // 2} {int(sh * 0.62)} 400")
            time.sleep(1.2)

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
    """批改当前卷：交替标记 对/错 各 N 次，直到批改完成页；小结页校验『共 N 题』防错卷。
    完成后点选『5 分』用时速记（随卷持久化，s6 卷库元信息可见）。"""
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
    w.tap_y_sorted("5 分", idx=0, exact=True)  # 精确匹配防"15 分"子串污染
    log(f"  批改完成：对 {right_n} / 错 {wrong_n}（共 {total}）· 用时 5 分")


# ---------- 在线作答走查 ----------

QUESTION_RE = re.compile(r"^\d+\s*[+\-\u2212\u00d7\u00f7]\s*\d+\s*=$")
COUNTER_RE = re.compile(r"^(\d+) / (\d+)$")


def answer_of(q: str):
    """题面 -> 期望答案（默认二年级族：两位数加减/表内乘除，双操作数）。"""
    q = q.strip().rstrip("=").strip()
    q = q.replace("\u2212", "-").replace("\u00d7", "*").replace("\u00f7", "/")
    m = re.match(r"^(\d+)\s*([+\-*/])\s*(\d+)$", q)
    if not m:
        return None
    a, op, b = int(m.group(1)), m.group(2), int(m.group(3))
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    return a // b


def _quiz_counter(rows: list):
    for r in rows:
        m = COUNTER_RE.match(r["text"])
        if m:
            return int(m.group(1))
    return None


def _quiz_question(rows: list):
    for r in rows:
        if QUESTION_RE.match(r["text"]):
            return r["text"]
    return None


def _quiz_keypad(rows: list) -> dict:
    """键盘键位坐标：数字取同文本 y 最大者（输入框/题面在上方，键盘在底部）。"""
    keys: dict = {}
    for d in "0123456789":
        best = None
        for r in rows:
            if r["text"] == d:
                c = center(r["bounds"])
                if c and (best is None or c[1] > best[1]):
                    best = c
        if best:
            keys[d] = best
    for sym in ("\u232b", "\u2713"):
        for r in rows:
            if r["text"] == sym:
                c = center(r["bounds"])
                if c:
                    keys[sym] = c
                    break
    return keys


def quiz_answer_all(w: Walker, wrong_at: set, snap_at: int = 2,
                    snap_name: str = "s3_quiz") -> None:
    """练习模式作答整卷：wrong_at 故意答错题号集合（1 基）；
    第 snap_at 题输入首位后定格截 s3。计数器驱动防闪绿期重复作答；
    答错反馈页点『下一题』前进（advance 已回作答态）。"""
    expect = 1
    snapped = False
    stall = 0
    while True:
        rows = w.rows()
        texts = [r["text"] for r in rows]
        if any("作答完成" in t for t in texts):
            break
        if any("回答错误" in t for t in texts):
            w.tap("下一题")
            expect += 1
            time.sleep(1.0)
            continue
        c = _quiz_counter(rows)
        if c is None:
            stall += 1
            if stall > 12:
                w.fail("quiz 计数器丢失 12 轮")
            time.sleep(0.8)
            continue
        stall = 0
        if c > expect:
            expect = c
            continue
        if c < expect:
            w.fail(f"quiz 计数器回退 c={c} expect={expect}")
        q = _quiz_question(rows)
        if q is None:
            time.sleep(0.6)
            continue
        ans = answer_of(q)
        if ans is None:
            w.fail(f"quiz 题面解析失败：{q}")
        keys = _quiz_keypad(rows)
        if "\u2713" not in keys:
            time.sleep(0.6)
            continue
        digits = str(ans) if expect not in wrong_at else ("1" if str(ans) != "1" else "2")
        for i, ch in enumerate(digits):
            if ch not in keys:
                w.fail(f"quiz 键盘缺键 {ch}")
            w.dev.click(keys[ch][0], keys[ch][1])
            time.sleep(0.12)
            if expect == snap_at and i == 0 and not snapped:
                w.snap(snap_name, settle=0.6)  # s3：输入一半 + 键盘 + 进度条
                snapped = True
                time.sleep(0.3)
        w.dev.click(keys["\u2713"][0], keys["\u2713"][1])
        # 提交后等前进/答错反馈/结果，避免闪绿期重复作答
        deadline = time.time() + 4.0
        while time.time() < deadline:
            rows = w.rows()
            t2 = [r["text"] for r in rows]
            if any("作答完成" in t for t in t2) or any("回答错误" in t for t in t2):
                break
            cc = _quiz_counter(rows)
            if cc is not None and cc != expect:
                break
            time.sleep(0.25)
        time.sleep(0.2)


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
        # module.json5 metadata ohos.ability.window.isMaximize 首启即最大化（仅自由窗口态生效）；
        # 兜底：配置未生效仍为悬浮窗（根宽 < 2500px）时双击标题栏手动最大化
        rw, _ = w.screen_size()
        if rw < 2500:
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
    w.tap_scroll("20", exact=True)  # 手机竖屏题数在折叠区，滚动定位；宽屏零滑动
    w.tap("生成题卡")
    w.wait_for("导出 PDF")
    w.snap("s2_preview")
    w.tap("返回")
    w.wait_for("生成题卡")

    log("== 批改 50 题卷（对 25 / 错 25 · 手动批改素材态） ==")
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

    log("== 在线作答 20 题卷（练习 · 对 15 / 错 5）+ s3/s4 ==")
    w.tap("卷库", exact=True)
    w.wait_for("批改")
    w.tap("在线作答")  # 唯一未批卷（20 题）卡片的品牌色入口
    w.wait_for("开始作答")
    w.wait_for("共 20 题")
    w.tap("开始作答")  # 默认练习模式：每题提交即判分
    quiz_answer_all(w, {4, 8, 12, 16, 20})
    w.wait_for("作答完成")
    w.wait_for("共 20 题 · 对 15 · 错 5")
    w.snap("s4_quiz_result")
    w.tap("返回")
    w.wait_for("批改")  # 自卷库卡片入口推入，返回即回 Index 卷库 tab

    log("== 收尾站点截图 s1/s5/s6/s7 ==")
    w.tap("生成", exact=True)
    w.wait_for("生成题卡")
    w.scroll_top()  # 手机滚动选过题数后回顶部，s1 与宽屏同构（Hero 卡+年级题型区）
    w.snap("s1_generator")
    w.tap("错题本", exact=True)
    w.wait_for("清空错题本")
    w.wait_for("共 5 道错题")
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
