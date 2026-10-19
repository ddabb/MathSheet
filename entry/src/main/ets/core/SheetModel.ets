/**
 * M2 核心①：统一渲染模型——三种题型（单步/两步混合/填空）归一为版面与渲染层
 * 消费的 SheetItem（题面文本 + 答案文本 + 去重键）。
 *
 * - 题面以 "=" 结尾（口算作答位），运算符两侧空格分隔，减号用印刷体 U+2212；
 * - 去重键沿用各题型 key()（ASCII 紧凑式），与生成期去重保持单一事实源；
 * - 答案文本 = 完整式（填空题为 □ 填回的完整式），答案页渲染层红色呈现。
 */

import { Problem, ProblemGen } from './ProblemGen';
import { MixedProblem } from './MixedGen';
import { BlankProblem } from './FillBlank';

/** 版面/渲染层的最小题目单元（物化文本，不含任何生成语义）。 */
export class SheetItem {
  /** 题面文本（如 "23 + 15 =" / "(15 + 8) × 3 =" / "3 + □ = 7"）。 */
  questionText: string;
  /** 答案文本（题面 + 结果；填空题为填回完整式）。 */
  answerText: string;
  /** 去重键（沿用生成期键，ASCII 紧凑式）。 */
  key: string;

  constructor(questionText: string, answerText: string, key: string) {
    this.questionText = questionText;
    this.answerText = answerText;
    this.key = key;
  }

  /** 单步四则 → SheetItem。 */
  static fromProblem(p: Problem): SheetItem {
    const sym: string = ProblemGen.symbolOf(p.op);
    const q: string = `${p.a} ${sym} ${p.b} =`;
    return new SheetItem(q, `${q} ${p.answer}`, p.key());
  }

  /** 两步混合 → SheetItem（括号按 bracket 渲染）。 */
  static fromMixed(m: MixedProblem): SheetItem {
    const s1: string = ProblemGen.symbolOf(m.op1);
    const s2: string = ProblemGen.symbolOf(m.op2);
    const core: string = `${m.a} ${s1} ${m.b}`;
    const body: string = m.bracket ? `(${core}) ${s2} ${m.c}` : `${core} ${s2} ${m.c}`;
    const q: string = `${body} =`;
    return new SheetItem(q, `${q} ${m.answer}`, m.key());
  }

  /** 填空 → SheetItem（题面含 □；答案文本为 □ 填回后的完整式）。 */
  static fromBlank(b: BlankProblem): SheetItem {
    const sym: string = SheetItem.printSymbol(b.op);
    const left: string = b.blankPos === 'a' ? '\u25a1' : String(b.a);
    const right: string = b.blankPos === 'b' ? '\u25a1' : String(b.b);
    const result: string = b.blankPos === 'answer' ? '\u25a1' : String(b.answerValue);
    const q: string = `${left} ${sym} ${right} = ${result}`;
    return new SheetItem(q, q.replace('\u25a1', String(b.blankValue)), b.key());
  }

  /** 键用符号（ASCII）→ 印刷体符号（减号 U+2212，其余同形）。 */
  static printSymbol(op: string): string {
    if (op === '-') {
      return '\u2212';
    }
    return op;
  }
}
