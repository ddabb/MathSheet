/**
 * 数形结合题型生成（计划 §17.3 v1.1）：看图列式 / 点阵乘法 / 数轴填空 / 面积模型拆分
 * / 小数数轴 / 小数面积模型（第三批，五年级）/ 分数乘整数 / 百分数互化 / 比的化简
 * / 分数面积模型（第四批，六年级）。
 *
 * 纯文本图形协议（存储/判分/卷库零迁移）：
 *  - 图形全部由字体字形承载：● ○（实心/空心圆点，1em 全角）、—（数轴线段，0.894em）、
 *    □（作答位）、× − +（运算符）；字形覆盖由 check_font_coverage.py REQUIRED_SYMBOLS 护栏保证；
 *  - 题面恒含单个 □，答案文本 = □ 填回 → 走 QuizJudge 既有填空分支（框位扫描），判分零改动；
 *  - 多行题面末行恒为算式行（不以 \n 结尾）→ 渲染层与竖式（题面以 \n 结尾）区分
 *    （M8 竖式右对齐 + 横线；图形题逐行左对齐，点行按 0.55 倍字号缩排）；
 *  - 宽度约束（4 列版心 512px = 6.737em 最紧，字形宽度为 fontTools 实测）：
 *    看图点行 ≤ 12 点、点阵列数 ≤ 9、数轴 4 刻度（可见数字 ≤ 5 位），
 *    面积模型行1 ≤ "49 × 29 ="（4.45em）、小数面积模型行1 ≤ "9.9 × 9 ="（4.17em）、
 *    小数数轴 3 刻度（0—s—□，一位小数 0.1–0.5），
 *    六年级单行文本最宽 "72 : 81 = 8 : □" ≈ 6.22em、分数面积模型行1 ≤ "5/6 × 24 ="（5.34em），
 *    生成侧保证缩放后行宽不越 4 列版心。
 * 种子化：全部走 Rng（同参数同种子 = 同卷）；键前缀 f 区分图形题与既有题型
 * （fp 看图 / fa 点阵 / fn 数轴 / far·fdr 面积模型 / fdl 小数数轴
 * / ffm 分数乘 / fpc 百分数 / frt 比 / ffr 分数面积模型），去重与错题重练复用既有管线。
 */

import { Rng } from './Rng';
import { SheetItem } from './SheetModel';

export class FigureGen {
  /** 实心圆点 ●（1em 全角，宽度实测）。 */
  private static readonly DOT: string = '\u25cf';
  /** 空心圆点 ○（减法"划掉"位）。 */
  private static readonly OPEN: string = '\u25cb';
  /** 数轴线段 —（U+2014 em dash，0.894em）。 */
  private static readonly DASH: string = '\u2014';
  /** 作答位 □。 */
  private static readonly BOX: string = '\u25a1';
  /** 乘号 ×（U+00D7，1em）。 */
  private static readonly MUL: string = '\u00d7';
  /** 减号 −（U+2212 印刷体，0.555em）。 */
  private static readonly MINUS: string = '\u2212';

  /** 预设表驱动分发（figKind 缺省/未知退化为看图加法兜底）。 */
  static generate(figKind: string | null, rng: Rng): SheetItem {
    if (figKind === 'pic_sub') {
      return FigureGen.picSub(rng);
    }
    if (figKind === 'array') {
      return FigureGen.arrayMul(rng);
    }
    if (figKind === 'numline2') {
      return FigureGen.numLine(rng, 2, 5);
    }
    if (figKind === 'numline3') {
      return FigureGen.numLine(rng, 6, 15);
    }
    if (figKind === 'area') {
      return FigureGen.areaModel(rng);
    }
    if (figKind === 'decnumline') {
      return FigureGen.decNumLine(rng);
    }
    if (figKind === 'decarea') {
      return FigureGen.decAreaModel(rng);
    }
    if (figKind === 'fracmul') {
      return FigureGen.fracMul(rng);
    }
    if (figKind === 'percent') {
      return FigureGen.percentX(rng);
    }
    if (figKind === 'ratio') {
      return FigureGen.ratioSimplify(rng);
    }
    if (figKind === 'fracarea') {
      return FigureGen.fracAreaModel(rng);
    }
    return FigureGen.picAdd(rng);
  }

  /** 看图列式·加法（一年级，和 ≤ 10）：上行两组实心点，下行算式单个 □（两加数/和轮换）。 */
  static picAdd(rng: Rng): SheetItem {
    const a: number = rng.nextInt(2, 10); // 2..9
    const b: number = rng.nextInt(1, Math.min(9, 10 - a) + 1); // 1..min(9, 10−a)
    const pos: number = rng.nextInt(0, 3); // 0..2
    const dots: string = `${FigureGen.repeat(FigureGen.DOT, a)} ${FigureGen.repeat(FigureGen.DOT, b)}`;
    let expr: string = '';
    let value: number = 0;
    if (pos === 0) {
      expr = `${FigureGen.BOX} + ${b} =`;
      value = a;
    } else if (pos === 1) {
      expr = `${a} + ${FigureGen.BOX} =`;
      value = b;
    } else {
      expr = `${a} + ${b} = ${FigureGen.BOX}`;
      value = a + b;
    }
    const q: string = `${dots}\n${expr}`;
    return new SheetItem(q, q.replace(FigureGen.BOX, String(value)), `fpa${a}_${b}_${pos}`);
  }

  /** 看图列式·减法（一年级，总数 ≤ 12）：实心点为剩余、空心点为划掉，下行算式单个 □。 */
  static picSub(rng: Rng): SheetItem {
    const rest: number = rng.nextInt(2, 9); // 2..8（● 个数）
    const removed: number = rng.nextInt(1, Math.min(6, 12 - rest) + 1); // 1..min(6, 12−rest)（○ 个数）
    const total: number = rest + removed;
    const pos: number = rng.nextInt(0, 3);
    const dots: string =
      `${FigureGen.repeat(FigureGen.DOT, rest)}${FigureGen.repeat(FigureGen.OPEN, removed)}`;
    let expr: string = '';
    let value: number = 0;
    if (pos === 0) {
      expr = `${FigureGen.BOX} ${FigureGen.MINUS} ${removed} =`;
      value = total;
    } else if (pos === 1) {
      expr = `${total} ${FigureGen.MINUS} ${FigureGen.BOX} =`;
      value = removed;
    } else {
      expr = `${total} ${FigureGen.MINUS} ${removed} = ${FigureGen.BOX}`;
      value = rest;
    }
    const q: string = `${dots}\n${expr}`;
    return new SheetItem(q, q.replace(FigureGen.BOX, String(value)), `fps${total}_${removed}_${pos}`);
  }

  /** 点阵乘法（二年级表内）：r 行 × c 列点阵 + 末行算式（行数/列数/积轮换挖空）。 */
  static arrayMul(rng: Rng): SheetItem {
    const rows: number = rng.nextInt(2, 7); // 2..6
    const cols: number = rng.nextInt(2, 10); // 2..9
    const pos: number = rng.nextInt(0, 3);
    let q: string = '';
    for (let i: number = 0; i < rows; i++) {
      q += FigureGen.repeat(FigureGen.DOT, cols) + '\n';
    }
    const product: number = rows * cols;
    let expr: string = '';
    let value: number = 0;
    if (pos === 0) {
      expr = `${FigureGen.BOX} ${FigureGen.MUL} ${cols} = ${product}`;
      value = rows;
    } else if (pos === 1) {
      expr = `${rows} ${FigureGen.MUL} ${FigureGen.BOX} = ${product}`;
      value = cols;
    } else {
      expr = `${rows} ${FigureGen.MUL} ${cols} = ${FigureGen.BOX}`;
      value = product;
    }
    q += expr;
    return new SheetItem(q, q.replace(FigureGen.BOX, String(value)), `fam${rows}x${cols}_${pos}`);
  }

  /** 数轴填空：0 起等差 4 刻度（0, s, 2s, 3s），中间刻度挖 □（step ∈ [lo, hi]）。 */
  static numLine(rng: Rng, lo: number, hi: number): SheetItem {
    const step: number = rng.nextInt(lo, hi + 1);
    const pos: number = rng.nextInt(1, 4); // 挖空刻度 1..3
    const parts: string[] = [];
    for (let i: number = 0; i < 4; i++) {
      parts.push(i === pos ? FigureGen.BOX : String(i * step));
    }
    const q: string =
      `${parts[0]}${FigureGen.DASH}${parts[1]}${FigureGen.DASH}${parts[2]}${FigureGen.DASH}${parts[3]}`;
    const value: number = pos * step;
    return new SheetItem(q, q.replace(FigureGen.BOX, String(value)), `fnl${step}_${pos}`);
  }

  /**
   * 面积模型拆分（四年级，两位数×两位数，连接 g4_mul_2x2 / g4_assoc 分配律概念）：
   * m = 整十 t + 个位 u（u ≥ 1 保证分割有意义），c 两位数。
   * 4 行协议：行1 "m × c ="（屏幕/在线作答可读）、行2-3 矢量图形占位
   * （渲染层 far 分支 drawLine 绘制 t|u 分割矩形 + 左侧 c + 顶部 t/u 标签，
   * 题面模式子块留白，答案模式子块积 t×c/u×c 红色）、行4 作答 □。
   * 判分走既有填空分支（期望 = m×c）；屏幕降级为横式填空（行1 + 行4 □）。
   */
  static areaModel(rng: Rng): SheetItem {
    const tens: number = rng.nextInt(1, 5) * 10; // 10..40
    const ones: number = rng.nextInt(1, 10); // 1..9
    const m: number = tens + ones;
    const c: number = rng.nextInt(12, 30); // 12..29
    const head: string = `${m} ${FigureGen.MUL} ${c} =`;
    const q: string = `${head}\n\n\n${FigureGen.BOX}`;
    return new SheetItem(q, `${head}\n\n\n${m * c}`, `far${m}x${c}`);
  }

  /**
   * 小数数轴填空（五年级，小数意义/小数加减数感）：0 起等差 3 刻度（0, s, 2s），
   * s ∈ 0.1–0.5（一位小数），□ 在刻度 1/2。单行纯文本，走既有单行渲染路径。
   * 3 刻度宽度约束：0.x 三字符刻度（1.39em）×2 + 破折号 ×2 + □ ≤ 4.73em ✓ 4 列版心。
   * 判分走既有填空分支（扫描含内嵌小数点，遇 — 停止）；isCorrect 数值比较容忍 "1"="1.0"。
   */
  static decNumLine(rng: Rng): SheetItem {
    const tenths: number = rng.nextInt(1, 6); // 步长 0.1..0.5（十分位）
    const pos: number = rng.nextInt(1, 3); // □ 在刻度 1..2
    const parts: string[] = [];
    for (let i: number = 0; i < 3; i++) {
      parts.push(i === pos ? FigureGen.BOX : FigureGen.fmtTenths(i * tenths));
    }
    const q: string =
      `${parts[0]}${FigureGen.DASH}${parts[1]}${FigureGen.DASH}${parts[2]}`;
    return new SheetItem(q, q.replace(FigureGen.BOX, FigureGen.fmtTenths(pos * tenths)),
      `fdl${tenths}_${pos}`);
  }

  /**
   * 小数面积模型拆分（五年级，小数乘整数，连接 g5_dec_mul 部分积概念）：
   * m = 整数部分 w ∈ [1,9] + 十分位 d ∈ [1,9]（一位小数 1.1–9.9，d ≥ 1 保证分割有意义），
   * c ∈ [2,9] 整数。4 行协议同面积模型：行1 "m × c ="、行2-3 fdr 矢量分割矩形占位
   * （渲染层 fdr 分支：顶部 w|0.d 标签 + 左侧 c + 答案模式子块积 w×c / 0.d×c）、行4 作答 □。
   * 结果按应用小数约定补 .0（3.0 而非 3）；键 fdr{m×10}x{c}，键空间 81×8 = 648。
   */
  static decAreaModel(rng: Rng): SheetItem {
    const w: number = rng.nextInt(1, 10); // 1..9（整数部分）
    const d: number = rng.nextInt(1, 10); // 1..9（十分位）
    const c: number = rng.nextInt(2, 10); // 2..9
    const m10: number = w * 10 + d; // m × 10（一位小数缩放整数，键/格式化共用）
    const head: string = `${FigureGen.fmtTenths(m10)} ${FigureGen.MUL} ${c} =`;
    const q: string = `${head}\n\n\n${FigureGen.BOX}`;
    return new SheetItem(q, `${head}\n\n\n${FigureGen.fmtTenthsPad(m10 * c)}`,
      `fdr${m10}x${c}`);
  }

  /** 十分位缩放整数值格式化（n/10）：整除不带点（数轴刻度 1），否则一位小数（0.4）。 */
  private static fmtTenths(n: number): string {
    return n % 10 === 0 ? String(n / 10) : (n / 10).toFixed(1);
  }

  /**
   * 分数乘整数（六年级，单行文本，人教六上"求一个数的几分之几"）：
   * a/b 最简（a<b，gcd=1），c = k·b（k ∈ [1,3]，b|c 保证结果整数 k·a）。
   * □ 三位轮换：结果 / c / 分子。宽度最宽 "5/8 × 24 = □" ≈ 6.07em ✓ 4 列版心。
   * 判分走既有填空分支（框位扫描，分子位 □ 后遇 '/' 停止）。
   */
  static fracMul(rng: Rng): SheetItem {
    let a = 0;
    let b = 0;
    do {
      b = rng.nextInt(2, 10); // 2..9
      a = rng.nextInt(1, b); // 1..b−1
    } while (FigureGen.gcd(a, b) !== 1);
    const k: number = rng.nextInt(1, 4); // 1..3
    const c: number = k * b;
    const frac: string = `${a}/${b}`;
    const product: number = k * a;
    const pos: number = rng.nextInt(0, 3);
    let expr: string = '';
    let value: number = 0;
    if (pos === 0) {
      expr = `${frac} ${FigureGen.MUL} ${c} = ${FigureGen.BOX}`;
      value = product;
    } else if (pos === 1) {
      expr = `${frac} ${FigureGen.MUL} ${FigureGen.BOX} = ${product}`;
      value = c;
    } else {
      expr = `${FigureGen.BOX}/${b} ${FigureGen.MUL} ${c} = ${product}`;
      value = a;
    }
    return new SheetItem(expr, expr.replace(FigureGen.BOX, String(value)),
      `ffm${a}_${b}x${k}_${pos}`);
  }

  /**
   * 百分数互化（六年级，单行文本）：x = 5t ∈ [10,95]，三形态——
   * 分数→百分数（p/q = □%）、小数→百分数（0.dd = □%）、百分数→小数（x% = □）。
   * 分数取 x/100 约分（gcd）；小数 (x/100).toFixed(2) 两位小数恒定文本。
   * 宽度最宽 "19/20 = □%" ≈ 5.89em ✓ 4 列版心。
   */
  static percentX(rng: Rng): SheetItem {
    const x: number = rng.nextInt(2, 20) * 5; // 10..95（5 的倍数）
    const form: number = rng.nextInt(0, 3);
    const g: number = FigureGen.gcd(x, 100);
    const dec: string = (x / 100).toFixed(2);
    let q: string = '';
    let value: string = '';
    if (form === 0) {
      q = `${x / g}/${100 / g} = ${FigureGen.BOX}%`;
      value = String(x);
    } else if (form === 1) {
      q = `${dec} = ${FigureGen.BOX}%`;
      value = String(x);
    } else {
      q = `${x}% = ${FigureGen.BOX}`;
      value = dec;
    }
    return new SheetItem(q, q.replace(FigureGen.BOX, value), `fpc${x}_${form}`);
  }

  /**
   * 比的化简（六年级，单行文本）：最简整数比 p:q（p<q，gcd=1）放大 k 倍得 pk:qk，
   * □ 在化简侧（q 或 p）。pk、qk ≤ 99，宽度最宽 "72 : 81 = 8 : □" ≈ 6.22em ✓ 4 列版心。
   */
  static ratioSimplify(rng: Rng): SheetItem {
    let p = 0;
    let q = 0;
    let k = 0;
    do {
      p = rng.nextInt(1, 9);
      q = rng.nextInt(p + 1, 10);
      k = rng.nextInt(2, 10); // 2..9
    } while (FigureGen.gcd(p, q) !== 1 || p * k > 99 || q * k > 99);
    const pos: number = rng.nextInt(0, 2);
    let expr: string = '';
    let value: number = 0;
    if (pos === 0) {
      expr = `${p * k} : ${q * k} = ${p} : ${FigureGen.BOX}`;
      value = q;
    } else {
      expr = `${p * k} : ${q * k} = ${FigureGen.BOX} : ${q}`;
      value = p;
    }
    return new SheetItem(expr, expr.replace(FigureGen.BOX, String(value)),
      `frt${p}_${q}x${k}_${pos}`);
  }

  /**
   * 分数乘整数面积模型（六年级，4 行协议同面积模型）：
   * a/b 最简（a<b，b ∈ [2,6]），c = k·b（k ∈ [1,4]，c ≤ 24），结果 k·a 整数。
   * 行1 "a/b × c ="、行2-3 ffr 矢量条带占位（渲染层 ffr 分支：c 长条带按 b 等分、
   * 前 a 组阴影线 + 顶部 a/b 标签 + 左侧 c，答案模式阴影区积红色 k·a）、行4 作答 □。
   * 宽度 "5/6 × 24 =" ≈ 5.34em ✓；键 ffr{a}_{b}x{k}，键空间 11 组合 × 4 = 44。
   */
  static fracAreaModel(rng: Rng): SheetItem {
    let a = 0;
    let b = 0;
    do {
      b = rng.nextInt(2, 7); // 2..6
      a = rng.nextInt(1, b); // 1..b−1
    } while (FigureGen.gcd(a, b) !== 1);
    const k: number = rng.nextInt(1, 5); // 1..4
    const c: number = k * b;
    const head: string = `${a}/${b} ${FigureGen.MUL} ${c} =`;
    const q: string = `${head}\n\n\n${FigureGen.BOX}`;
    return new SheetItem(q, `${head}\n\n\n${k * a}`, `ffr${a}_${b}x${k}`);
  }

  /** 欧几里得最大公约数（分数最简 / 比最简判定）。 */
  private static gcd(x: number, y: number): number {
    let a: number = x;
    let b: number = y;
    while (b !== 0) {
      const t: number = a % b;
      a = b;
      b = t;
    }
    return a;
  }

  /** 十分位缩放整数值补零格式化（n/10，应用小数约定：结果 3.0 而非 3）。 */
  private static fmtTenthsPad(n: number): string {
    return n % 10 === 0 ? `${n / 10}.0` : (n / 10).toFixed(1);
  }

  /** 字符重复（ArkTS 无内建 repeat 便捷实现，循环拼接）。 */
  private static repeat(ch: string, n: number): string {
    let s: string = '';
    for (let i: number = 0; i < n; i++) {
      s += ch;
    }
    return s;
  }
}
