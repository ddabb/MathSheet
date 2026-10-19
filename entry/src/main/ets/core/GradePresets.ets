/**
 * M1 年级预设：题型 × 难度的纯数据组合表（计划 §4.1 / §6.2）。
 *
 * - 每题型 2-3 档难度（数值范围/进退位约束/是否含括号）；
 * - kind = single（单步四则）/ mixed（两步混合）/ fill（填空，fillFrom 引用基础预设）；
 * - 表为纯数据：可测可扩展；生成编排见 SheetGen，测试见 MathCore.test GradePresets 段。
 */

import { ProblemSpec } from './ProblemGen';
import { MixedSpec } from './MixedGen';

export class PresetEntry {
  id: string;
  grade: number;
  labelZh: string;
  labelEn: string;
  kind: 'single' | 'mixed' | 'fill';
  spec: ProblemSpec | null;
  mixed: MixedSpec | null;
  /** fill 条目专用：引用提供基础题的 single 预设 id。 */
  fillFrom: string | null;

  constructor(id: string, grade: number, labelZh: string, labelEn: string,
              kind: 'single' | 'mixed' | 'fill', spec: ProblemSpec | null = null,
              mixed: MixedSpec | null = null, fillFrom: string | null = null) {
    this.id = id;
    this.grade = grade;
    this.labelZh = labelZh;
    this.labelEn = labelEn;
    this.kind = kind;
    this.spec = spec;
    this.mixed = mixed;
    this.fillFrom = fillFrom;
  }
}

export class GradePresets {
  static readonly ENTRIES: PresetEntry[] = [
    // ---- 一年级：10/20 以内加减 + 连加连减 + 填空
    new PresetEntry('g1_add10', 1, '10以内加法', 'Addition within 10', 'single',
      new ProblemSpec('add', 1, 10, true)),
    new PresetEntry('g1_sub10', 1, '10以内减法', 'Subtraction within 10', 'single',
      new ProblemSpec('sub', 1, 10)),
    new PresetEntry('g1_add20_base', 1, '20以内加法·基础（不进位）', 'Addition within 20 - no carry', 'single',
      new ProblemSpec('add', 1, 20, true)),
    new PresetEntry('g1_add20_plus', 1, '20以内加法·进阶（含进位）', 'Addition within 20 - with carry', 'single',
      new ProblemSpec('add', 1, 20)),
    new PresetEntry('g1_sub20_base', 1, '20以内减法·基础（不退位）', 'Subtraction within 20 - no borrow', 'single',
      new ProblemSpec('sub', 1, 20, false, true)),
    new PresetEntry('g1_sub20_plus', 1, '20以内减法·进阶（含退位）', 'Subtraction within 20 - with borrow', 'single',
      new ProblemSpec('sub', 1, 20)),
    new PresetEntry('g1_chain_add', 1, '连加', 'Chained addition', 'mixed', null,
      new MixedSpec('add', 'add', false, 2, 30, 1, 10, 10)),
    new PresetEntry('g1_chain_sub', 1, '连减', 'Chained subtraction', 'mixed', null,
      new MixedSpec('add', 'sub', false, 1, 20, 1, 10, 10)),
    new PresetEntry('g1_fill', 1, '填空（20以内加减）', 'Fill-in (within 20)', 'fill', null, null, 'g1_add20_plus'),

    // ---- 二年级：100 以内加减 + 表内乘除 + 乘加乘减 + 填空
    new PresetEntry('g2_add100_base', 2, '100以内加法·基础（不进位）', 'Addition within 100 - no carry', 'single',
      new ProblemSpec('add', 10, 99, true)),
    new PresetEntry('g2_add100_plus', 2, '100以内加法·进阶（含进位）', 'Addition within 100 - with carry', 'single',
      new ProblemSpec('add', 10, 99)),
    new PresetEntry('g2_sub100_base', 2, '100以内减法·基础（不退位）', 'Subtraction within 100 - no borrow', 'single',
      new ProblemSpec('sub', 20, 99, false, true)),
    new PresetEntry('g2_sub100_plus', 2, '100以内减法·进阶（含退位）', 'Subtraction within 100 - with borrow', 'single',
      new ProblemSpec('sub', 1, 100)),
    new PresetEntry('g2_mul_table', 2, '表内乘法', 'Multiplication table', 'single',
      new ProblemSpec('mul', 2, 9, false, false, true)),
    new PresetEntry('g2_div_table', 2, '表内除法', 'Division table', 'single',
      new ProblemSpec('div', 2, 81, false, false, false, 9)),
    new PresetEntry('g2_mul_add', 2, '乘加', 'Multiply then add', 'mixed', null,
      new MixedSpec('mul', 'add', false, 2, 90, 2, 9, 9, 9, 9)),
    new PresetEntry('g2_mul_sub', 2, '乘减', 'Multiply then subtract', 'mixed', null,
      new MixedSpec('mul', 'sub', false, 2, 90, 2, 9, 9, 9, 9)),
    new PresetEntry('g2_fill', 2, '填空（100以内加减）', 'Fill-in (within 100)', 'fill', null, null, 'g2_add100_plus'),

    // ---- 三年级：三位数加减 + 两位数乘一位数 + 带括号两步 + 填空
    new PresetEntry('g3_add_3d', 3, '三位数加法', 'Three-digit addition', 'single',
      new ProblemSpec('add', 100, 999)),
    new PresetEntry('g3_sub_3d', 3, '三位数减法', 'Three-digit subtraction', 'single',
      new ProblemSpec('sub', 100, 999)),
    new PresetEntry('g3_mul_2x1', 3, '两位数乘一位数', 'Two-digit by one-digit', 'single',
      new ProblemSpec('mul', 10, 99)),
    new PresetEntry('g3_bracket_add', 3, '带括号·(a+b)×c', 'Bracketed (a+b)×c', 'mixed', null,
      new MixedSpec('add', 'mul', true, 20, 400, 10, 99, 20, 9)),
    new PresetEntry('g3_bracket_sub', 3, '带括号·(a−b)×c', 'Bracketed (a-b)×c', 'mixed', null,
      new MixedSpec('sub', 'mul', true, 10, 400, 20, 99, 20, 9)),
    new PresetEntry('g3_fill', 3, '填空（两位数乘一位数）', 'Fill-in (2-digit × 1-digit)', 'fill', null, null, 'g3_mul_2x1'),
  ];

  static forGrade(grade: number): PresetEntry[] {
    const out: PresetEntry[] = [];
    for (const e of GradePresets.ENTRIES) {
      if (e.grade === grade) {
        out.push(e);
      }
    }
    return out;
  }

  static byId(id: string): PresetEntry | null {
    for (const e of GradePresets.ENTRIES) {
      if (e.id === id) {
        return e;
      }
    }
    return null;
  }

  /** 解析条目基础规格：single/fill 用（fill 经 fillFrom 间接解析）。 */
  static resolveSpec(entry: PresetEntry): ProblemSpec | null {
    if (entry.spec !== null) {
      return entry.spec;
    }
    if (entry.kind === 'fill' && entry.fillFrom !== null) {
      const base: PresetEntry | null = GradePresets.byId(entry.fillFrom);
      if (base !== null) {
        return base.spec;
      }
    }
    return null;
  }
}
