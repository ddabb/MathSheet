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

  /** 单步四则 → SheetItem（dp>0 时数值为缩放整数，fmt 还原一位小数；乘法 b 为整数因子）。 */
  static fromProblem(p: Problem): SheetItem {
    const sym: string = ProblemGen.symbolOf(p.op);
    const fa: string = ProblemGen.fmt(p.a, p.dp);
    const fb: string = p.fmtB();
    const q: string = `${fa} ${sym} ${fb} =`;
    return new SheetItem(q, `${q} ${ProblemGen.fmt(p.answer, p.dp)}`, p.key());
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

  /** 填空 → SheetItem（题面含 □；答案文本为 □ 填回后的完整式；dp 填空值含一位小数）。 */
  static fromBlank(b: BlankProblem): SheetItem {
    const sym: string = SheetItem.printSymbol(b.op);
    // dp>0 乘法填空：b 为不缩放整数因子（与 Problem.fmtB 约定一致）
    const mulDp: boolean = b.op === '\u00d7' && b.dp > 0;
    const left: string = b.blankPos === 'a' ? '\u25a1' : ProblemGen.fmt(b.a, b.dp);
    const right: string = b.blankPos === 'b' ? '\u25a1' : (mulDp ? String(b.b) : ProblemGen.fmt(b.b, b.dp));
    const result: string = b.blankPos === 'answer' ? '\u25a1' : ProblemGen.fmt(b.answerValue, b.dp);
    const q: string = `${left} ${sym} ${right} = ${result}`;
    const filled: string = mulDp && b.blankPos === 'b' ? String(b.blankValue)
      : ProblemGen.fmt(b.blankValue, b.dp);
    return new SheetItem(q, q.replace('\u25a1', filled), b.key());
  }

  /**
   * 竖式 → SheetItem（1.0.1 M8）：4 行文本——上行 / 运算符+下行 / 空行（横线位）/ 结果行。
   * 题面止于空行（学生作答位留白），答案文本追加结果行；
   * 键前缀 'v' 区分同式横式题（去重/错题本独立）；sub 键操作数升序（与 add/mul
   * 归一键空间统一；生成序 a≥b，升序即 b-a）；在线批改走题面前缀匹配（QuizJudge 竖式分支）。
   */
  static fromVertical(p: Problem): SheetItem {
    const opChar: string = p.op === 'sub' ? '\u2212' : p.op === 'mul' ? '\u00d7' : '+';
    const top: string = ProblemGen.fmt(p.a, p.dp);
    const bottom: string = p.fmtB();
    const q: string = `${top}\n${opChar}${bottom}\n\n`;
    const key: string = p.op === 'sub'
      ? `v${ProblemGen.fmt(Math.min(p.a, p.b), p.dp)}-${ProblemGen.fmt(Math.max(p.a, p.b), p.dp)}`
      : `v${p.key()}`;
    return new SheetItem(q, `${q}${ProblemGen.fmt(p.answer, p.dp)}`, key);
  }

  /** 键用符号（ASCII）→ 印刷体符号（减号 U+2212，其余同形）。 */
  static printSymbol(op: string): string {
    if (op === '-') {
      return '\u2212';
    }
    return op;
  }
}
