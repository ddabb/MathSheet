/**
 * M1 核心⑤：填空题生成（计划 §4.1：挖操作数或结果，如 3 + □ = 7 / 3 + 5 = □）。
 *
 * 从完整单步题挖空：blankPos ∈ {a, b, answer}；text 为规范化紧凑形式（去重键同源）。
 * allowAnswer=false 时只挖操作数（低龄段：不挖结果，避免"看结果倒推"歧义）。
 */

import { Rng } from './Rng';
import { Problem, ProblemGen } from './ProblemGen';

export type BlankPos = 'a' | 'b' | 'answer';

/** 填空题（由完整题 + 挖位推导，键与值同源；dp>0 时数值为缩放整数）。 */
export class BlankProblem {
  a: number;
  b: number;
  op: string;
  blankPos: BlankPos;
  blankValue: number;
  /** 完整式结果（M2 SheetModel 答案文本推导用，物化保持单一事实源）。 */
  answerValue: number;
  /** 小数位数（1.0.1 M8）：1 = 一位小数（数值按 10 倍缩放整数存）。 */
  dp: number;
  text: string;

  constructor(p: Problem, blankPos: BlankPos) {
    this.a = p.a;
    this.b = p.b;
    this.op = ProblemGen.keySymbolOf(p.op);
    this.blankPos = blankPos;
    this.blankValue = blankPos === 'a' ? p.a : blankPos === 'b' ? p.b : p.answer;
    this.answerValue = p.answer;
    this.dp = p.dp;
    const left: string = blankPos === 'a' ? '\u25a1' : ProblemGen.fmt(p.a, this.dp);
    const right: string = blankPos === 'b' ? '\u25a1' : p.fmtB();
    const result: string = blankPos === 'answer' ? '\u25a1' : ProblemGen.fmt(p.answer, this.dp);
    this.text = left + this.op + right + '=' + result;
  }

  /** 去重键（即规范化文本，如 "3+\u25a1=7"）。 */
  key(): string {
    return this.text;
  }
}

export class FillBlank {
  static readonly POSITIONS: BlankPos[] = ['a', 'b', 'answer'];

  /** 从完整题生成填空题；allowAnswer=false 时只挖操作数。 */
  static fromProblem(p: Problem, rng: Rng, allowAnswer: boolean = true): BlankProblem {
    const positions: BlankPos[] = allowAnswer ? FillBlank.POSITIONS : ['a', 'b'];
    const pos: BlankPos = positions[rng.nextInt(0, positions.length)];
    return new BlankProblem(p, pos);
  }
}
