/**
 * M1 核心④：两步混合运算生成器（计划 §4.1：连加连减/乘加乘减/带括号两步）。
 *
 * 构造方向（§6.2 运算树自顶向下）：先定外层结果区间与第二步运算，回推内层操作数。
 * 硬约束先天保证：
 *   - 内层减法 a - b >= 0（b ∈ [0, a]）；
 *   - 外层减法 inner - c >= 0（c ∈ [0, inner]）；
 *   - 内层乘法因子 ∈ [2, factorMax]；外层乘法因子 c ∈ [2, cFactorMax]。
 * 最终结果区间 [min,max] 为弱约束：REJECT_LIMIT 拒绝采样兜底 + 放宽标记。
 *
 * text 为规范化紧凑形式（去重键同源，ASCII 符号），如 "12+8-5" / "6×7+9" / "(15-8)×3"；
 * 排版层（M2）自行从结构化字段渲染印刷体文本，不走 text。
 */

import { Rng } from './Rng';
import { ProblemGen } from './ProblemGen';

/** 混合运算可用运算（M1 不含除法入树：除法混合属 P2 需求驱动）。 */
export type MixedOp = 'add' | 'sub' | 'mul';

/** 两步混合规格：(a op1 b) op2 c；bracket 控制文本是否渲染括号。 */
export class MixedSpec {
  op1: MixedOp;
  op2: MixedOp;
  bracket: boolean;
  /** 最终结果区间 [min,max]（弱约束）。 */
  min: number;
  max: number;
  /** 内层区间（op1=add 时和为区间；op1=sub 时为被减数区间；op1=mul 时忽略）。 */
  innerMin: number;
  innerMax: number;
  /** 外层加减项 c 的上限（c ∈ [0, cMax]）。 */
  cMax: number;
  /** 外层乘法因子 c 的上限（c ∈ [2, cFactorMax]）。 */
  cFactorMax: number;
  /** 内层乘法因子上限（因子 ∈ [2, factorMax]）。 */
  factorMax: number;

  constructor(op1: MixedOp, op2: MixedOp, bracket: boolean, min: number, max: number,
              innerMin: number, innerMax: number, cMax: number = 20,
              cFactorMax: number = 9, factorMax: number = 9) {
    this.op1 = op1;
    this.op2 = op2;
    this.bracket = bracket;
    this.min = min;
    this.max = max;
    this.innerMin = innerMin;
    this.innerMax = innerMax;
    this.cMax = cMax;
    this.cFactorMax = cFactorMax;
    this.factorMax = factorMax;
  }
}

/** 两步混合题（answer/text 在构造时由字段推导，保证键与值同源）。 */
export class MixedProblem {
  a: number;
  b: number;
  c: number;
  op1: MixedOp;
  op2: MixedOp;
  bracket: boolean;
  answer: number;
  relaxed: boolean;
  text: string;

  constructor(a: number, b: number, c: number, op1: MixedOp, op2: MixedOp,
              bracket: boolean, relaxed: boolean = false) {
    this.a = a;
    this.b = b;
    this.c = c;
    this.op1 = op1;
    this.op2 = op2;
    this.bracket = bracket;
    this.relaxed = relaxed;
    const inner: number = op1 === 'add' ? a + b : op1 === 'sub' ? a - b : a * b;
    this.answer = op2 === 'add' ? inner + c : op2 === 'sub' ? inner - c : inner * c;
    const s1: string = ProblemGen.keySymbolOf(op1);
    const s2: string = ProblemGen.keySymbolOf(op2);
    const core: string = a + s1 + b;
    this.text = bracket ? '(' + core + ')' + s2 + c : core + s2 + c;
  }

  /** 去重键（即规范化文本）。 */
  key(): string {
    return this.text;
  }
}

export class MixedGen {
  /** 弱约束（最终结果区间）拒绝采样上限。 */
  static readonly REJECT_LIMIT: number = 64;

  static generate(spec: MixedSpec, rng: Rng): MixedProblem {
    const lo: number = Math.min(spec.min, spec.max);
    const hi: number = Math.max(spec.min, spec.max);
    const iLo: number = Math.min(spec.innerMin, spec.innerMax);
    const iHi: number = Math.max(spec.innerMin, spec.innerMax);
    let a: number = 0;
    let b: number = 0;
    let c: number = 0;
    for (let i = 0; i < MixedGen.REJECT_LIMIT; i++) {
      // 内层（硬约束构造保证）
      if (spec.op1 === 'add') {
        const s: number = rng.nextInt(iLo, iHi + 1);
        const aLo: number = Math.max(0, s - iHi);
        const aHi: number = Math.min(iHi, s);
        a = rng.nextInt(aLo, aHi + 1);
        b = s - a;
      } else if (spec.op1 === 'sub') {
        a = rng.nextInt(iLo, iHi + 1);
        b = rng.nextInt(0, a + 1);
      } else {
        a = rng.nextInt(2, spec.factorMax + 1);
        b = rng.nextInt(2, spec.factorMax + 1);
      }
      const inner: number = spec.op1 === 'add' ? a + b : spec.op1 === 'sub' ? a - b : a * b;
      // 外层（加减项/乘法因子）
      if (spec.op2 === 'add') {
        c = rng.nextInt(0, spec.cMax + 1);
      } else if (spec.op2 === 'sub') {
        c = rng.nextInt(0, inner + 1);
      } else {
        c = rng.nextInt(2, spec.cFactorMax + 1);
      }
      const r: number = spec.op2 === 'add' ? inner + c : spec.op2 === 'sub' ? inner - c : inner * c;
      if (r >= lo && r <= hi) {
        return new MixedProblem(a, b, c, spec.op1, spec.op2, spec.bracket, false);
      }
    }
    return new MixedProblem(a, b, c, spec.op1, spec.op2, spec.bracket, true);
  }
}
