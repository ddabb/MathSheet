/**
 * M0 核心②：构造式题目生成器（计划 §6.2 关键技术点①）。
 *
 * 核心思想：约束满足先于随机——按运算反向构造使硬约束先天满足，
 * 拒绝采样仅用于进退位等弱约束（REJECT_LIMIT 上限），理论上无死循环：
 *   加法：在和区间随机和 s → 随机加数 a → b = s - a（操作数与和同时受控）；
 *   减法：随机被减数 x → 减数 y ∈ [0, x]（结果非负先天保证）；
 *   乘法：表内两因子 ∈ [2,9]；两位数×一位数按区间构造；
 *   除法：先随机商 q 与除数 d → 被除数 = q × d（整除先天保证，核心技巧）。
 *
 * M1 范围（未实现）：加减混合/乘加乘减/带括号两步/填空挖位——接口已为扩展留形。
 */

import { Rng } from './Rng';

/** 运算类型（M0：四则单步）。 */
export type OpKind = 'add' | 'sub' | 'mul' | 'div';

/** 题目生成规格：显式数据类（年级预设 = 规格的纯数据组合表，M1）。 */
export class ProblemSpec {
  op: OpKind;
  /** 区间下限（语义随 op：加=和/减=被减数/乘=操作数/除=被除数；dp>0 时为缩放整数）。 */
  min: number;
  /** 区间上限。 */
  max: number;
  /** 加法弱约束：个位相加 < 10（不进位）。 */
  noCarry: boolean;
  /** 减法弱约束：个位被减 >= 减数（不退位）。 */
  noBorrow: boolean;
  /** 乘法：两因子 ∈ [2,9]（表内）；false 且 max>=10 时为多位数×一位数。 */
  tableMul: boolean;
  /** 除法：除数上限（表内 = 9；多位数除法 = 99）。 */
  divisorMax: number;
  /** 乘法第二因子下限（多位数乘法：两位数因子 = 10）。 */
  bMin: number;
  /** 乘法第二因子上限。 */
  bMax: number;
  /** 小数位数（1.0.1 M8）：1 = 一位小数；min/max/a/b/answer 均为 10^dp 缩放整数。 */
  dp: number;

  constructor(op: OpKind, min: number, max: number, noCarry: boolean = false,
              noBorrow: boolean = false, tableMul: boolean = false, divisorMax: number = 9,
              bMin: number = 2, bMax: number = 9, dp: number = 0) {
    this.op = op;
    this.min = min;
    this.max = max;
    this.noCarry = noCarry;
    this.noBorrow = noBorrow;
    this.tableMul = tableMul;
    this.divisorMax = divisorMax;
    this.bMin = bMin;
    this.bMax = bMax;
    this.dp = dp;
  }
}

/** 一道题（物化最小集）。relaxed = 弱约束达拒绝上限后自动放宽（调用方提示）。
 * dp > 0 时 a/b/answer 为 10^dp 缩放整数（展示层 ProblemGen.fmt 还原）。 */
export class Problem {
  a: number;
  b: number;
  op: OpKind;
  answer: number;
  relaxed: boolean;
  /** 小数位数（0 = 整数；1 = 一位小数，数值按 10 倍缩放整数存）。 */
  dp: number;

  constructor(a: number, b: number, op: OpKind, answer: number, relaxed: boolean = false,
              dp: number = 0) {
    this.a = a;
    this.b = b;
    this.op = op;
    this.answer = answer;
    this.relaxed = relaxed;
    this.dp = dp;
  }

  /** 规范化键（加/乘交换律归一，如 "23+15"；小数按缩放还原，如 "3.5+2.8"；Dedup.keyOf 委托本方法）。 */
  key(): string {
    const sym: string = ProblemGen.keySymbolOf(this.op);
    if (this.op === 'mul' && this.dp > 0) {
      // 小数×整数：a 为缩放小数、b 为不缩放整数因子，保序编码
      //（生成器单向产出该形态，保序即规范，不交换重排）
      return ProblemGen.fmt(this.a, this.dp) + sym + String(this.b);
    }
    if (this.op === 'add' || this.op === 'mul') {
      const x: number = Math.min(this.a, this.b);
      const y: number = Math.max(this.a, this.b);
      return ProblemGen.fmt(x, this.dp) + sym + ProblemGen.fmt(y, this.dp);
    }
    return ProblemGen.fmt(this.a, this.dp) + sym + this.fmtB();
  }

  /** 操作数 b 展示/键用文本：dp>0 乘法 b 为整数因子（不缩放），其余按 dp 还原。 */
  fmtB(): string {
    return this.op === 'mul' && this.dp > 0 ? String(this.b) : ProblemGen.fmt(this.b, this.dp);
  }
}

export class ProblemGen {
  /** 弱约束拒绝采样上限（硬约束一律构造保证，不死循环）。 */
  static readonly REJECT_LIMIT: number = 64;

  /** 缩放整数 → 展示文本（dp=1 一位小数；dp=0 原样）。 */
  static fmt(v: number, dp: number): string {
    return dp === 1 ? (v / 10).toFixed(1) : String(v);
  }

  /**
   * 加法：和 s ∈ [min,max] → 加数 a ∈ [max(0, s-max), min(max, s)] → b = s - a。
   * 硬约束先天满足：a,b ∈ [0,max] 且 a+b = s ∈ [min,max]。
   * 弱约束：不进位（个位相加 < 10），拒绝采样兜底。
   */
  static genAdd(spec: ProblemSpec, rng: Rng): Problem {
    const lo: number = Math.min(spec.min, spec.max);
    const hi: number = Math.max(spec.min, spec.max);
    let s: number = lo;
    let a: number = 0;
    let b: number = 0;
    for (let i = 0; i < ProblemGen.REJECT_LIMIT; i++) {
      s = rng.nextInt(lo, hi + 1);
      const aLo: number = Math.max(0, s - hi);
      const aHi: number = Math.min(hi, s);
      a = rng.nextInt(aLo, aHi + 1);
      b = s - a;
      if (!spec.noCarry || (a % 10) + (b % 10) < 10) {
        return new Problem(a, b, 'add', s, false, spec.dp);
      }
    }
    return new Problem(a, b, 'add', s, true, spec.dp);
  }

  /**
   * 减法：被减数 x ∈ [min,max] → 减数 y ∈ [0, x]。
   * 硬约束先天满足：x - y >= 0（结果非负）、x ∈ [min,max]、y <= x <= max。
   * 弱约束：不退位（个位被减 >= 减数），拒绝采样兜底。
   */
  static genSub(spec: ProblemSpec, rng: Rng): Problem {
    const lo: number = Math.min(spec.min, spec.max);
    const hi: number = Math.max(spec.min, spec.max);
    let x: number = lo;
    let y: number = 0;
    for (let i = 0; i < ProblemGen.REJECT_LIMIT; i++) {
      x = rng.nextInt(lo, hi + 1);
      y = rng.nextInt(0, x + 1);
      if (!spec.noBorrow || (x % 10) >= (y % 10)) {
        return new Problem(x, y, 'sub', x - y, false, spec.dp);
      }
    }
    return new Problem(x, y, 'sub', x - y, true, spec.dp);
  }

  /**
   * 乘法：
   *   表内（tableMul）：两因子 ∈ [2,9]（2-9 乘法口诀全集）；
   *   小数×整数（dp>0）：a ∈ [min,max] 缩放整数，b ∈ [bMin,bMax] 整数因子；
   *   多位数（max >= 10）：因子 b ∈ [bMin,bMax]（默认 2-9；两位数因子 10-99），a ∈ [max(10,min), max]；
   *   其余（max < 10 非表内）：两因子 ∈ [max(2,min), min(9,max)]。
   */
  static genMul(spec: ProblemSpec, rng: Rng): Problem {
    const lo: number = Math.min(spec.min, spec.max);
    const hi: number = Math.max(spec.min, spec.max);
    let a: number = 2;
    let b: number = 2;
    if (spec.tableMul) {
      a = rng.nextInt(2, 10);
      b = rng.nextInt(2, 10);
    } else if (spec.dp > 0) {
      a = rng.nextInt(Math.max(1, lo), hi + 1);
      b = rng.nextInt(Math.max(2, spec.bMin), spec.bMax + 1);
    } else if (hi >= 10) {
      b = rng.nextInt(Math.max(2, spec.bMin), spec.bMax + 1);
      const aLo: number = Math.max(10, lo);
      a = rng.nextInt(aLo, hi + 1);
    } else {
      const fLo: number = Math.max(2, lo);
      const fHi: number = Math.min(9, hi);
      a = rng.nextInt(fLo, fHi + 1);
      b = rng.nextInt(fLo, fHi + 1);
    }
    return new Problem(a, b, 'mul', a * b, false, spec.dp);
  }

  /**
   * 除法：除数 d ∈ [2, divisorMax]（表内 9 / 多位数 99）→ 商 q ∈ [1, floor(max/d)] → 被除数 = q × d。
   * 硬约束先天满足：整除、被除数 <= max、q >= 1、被除数 >= d。
   * 弱约束：被除数 >= min（区间下限），拒绝采样兜底（达上限标记放宽）。
   */
  static genDiv(spec: ProblemSpec, rng: Rng): Problem {
    const lo: number = Math.min(spec.min, spec.max);
    const hi: number = Math.max(spec.min, spec.max);
    const dMax: number = Math.max(2, Math.min(99, spec.divisorMax));
    let dividend: number = 0;
    let d: number = 2;
    let q: number = 1;
    for (let i = 0; i < ProblemGen.REJECT_LIMIT; i++) {
      d = rng.nextInt(2, dMax + 1);
      const qMax: number = Math.max(1, Math.floor(hi / d));
      q = rng.nextInt(1, qMax + 1);
      dividend = q * d;
      if (lo <= 1 || dividend >= lo) {
        return new Problem(dividend, d, 'div', q, false, spec.dp);
      }
    }
    return new Problem(dividend, d, 'div', q, true, spec.dp);
  }

  /** 统一入口：按 spec.op 分发。 */
  static generate(spec: ProblemSpec, rng: Rng): Problem {
    switch (spec.op) {
      case 'sub':
        return ProblemGen.genSub(spec, rng);
      case 'mul':
        return ProblemGen.genMul(spec, rng);
      case 'div':
        return ProblemGen.genDiv(spec, rng);
      case 'add':
      default:
        return ProblemGen.genAdd(spec, rng);
    }
  }

  /** 键用符号（去重键/序列化用：ASCII 连字符 + ×÷，与 Dedup 约定一致）。 */
  static keySymbolOf(op: OpKind): string {
    switch (op) {
      case 'sub':
        return '-';
      case 'mul':
        return '\u00d7';
      case 'div':
        return '\u00f7';
      case 'add':
      default:
        return '+';
    }
  }

  /** 展示用符号（排版层调用：印刷体减号 U+2212，打印质量）。 */
  static symbolOf(op: OpKind): string {
    switch (op) {
      case 'sub':
        return '\u2212';
      case 'mul':
        return '\u00d7';
      case 'div':
        return '\u00f7';
      case 'add':
      default:
        return '+';
    }
  }
}
