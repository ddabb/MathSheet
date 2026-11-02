/**
 * M1 年级预设：题型 × 难度的纯数据组合表（计划 §4.1 / §6.2）。
 *
 * - 每题型 2-3 档难度（数值范围/进退位约束/是否含括号）；
 * - kind = single（单步四则）/ mixed（两步混合）/ fill（填空，fillFrom 引用基础预设）
 *        / vertical（竖式，1.0.1 M8：多位数加减/乘法竖式）
 *        / figure（数形结合，v1.1 §17.3：看图列式/点阵乘法/数轴填空/面积模型拆分/小数数轴/小数面积模型，figKind 分发）；
 * - 四五年级（M8）：小数以缩放整数入表（dp=1，如 min=1 max=99 即 0.1–9.9）；
 * - 表为纯数据：可测可扩展；生成编排见 SheetGen，测试见 MathCore.test GradePresets 段。
 */

import { ProblemSpec } from './ProblemGen';
import { MixedSpec } from './MixedGen';

export class PresetEntry {
  id: string;
  grade: number;
  labelZh: string;
  labelEn: string;
  kind: 'single' | 'mixed' | 'fill' | 'vertical' | 'figure';
  spec: ProblemSpec | null;
  mixed: MixedSpec | null;
  /** fill 条目专用：引用提供基础题的 single 预设 id。 */
  fillFrom: string | null;
  /** figure 条目专用：数形结合题型分发键（pic_add/pic_sub/array/numline2/numline3/area/decnumline/decarea）。 */
  figKind: string | null;

  constructor(id: string, grade: number, labelZh: string, labelEn: string,
              kind: 'single' | 'mixed' | 'fill' | 'vertical' | 'figure', spec: ProblemSpec | null = null,
              mixed: MixedSpec | null = null, fillFrom: string | null = null,
              figKind: string | null = null) {
    this.id = id;
    this.grade = grade;
    this.labelZh = labelZh;
    this.labelEn = labelEn;
    this.kind = kind;
    this.spec = spec;
    this.mixed = mixed;
    this.fillFrom = fillFrom;
    this.figKind = figKind;
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
    new PresetEntry('g1_pic_add', 1, '看图列式·加法', 'Picture addition', 'figure', null, null, null, 'pic_add'),
    new PresetEntry('g1_pic_sub', 1, '看图列式·减法', 'Picture subtraction', 'figure', null, null, null, 'pic_sub'),

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
    new PresetEntry('g2_array', 2, '点阵乘法', 'Dot-array multiplication', 'figure', null, null, null, 'array'),
    new PresetEntry('g2_numline', 2, '数轴填空', 'Number-line blanks', 'figure', null, null, null, 'numline2'),

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
    new PresetEntry('g3_numline', 3, '数轴填空', 'Number-line blanks', 'figure', null, null, null, 'numline3'),

    // ---- 四年级（1.0.1 M8）：多位数乘除 + 简便运算 + 竖式 + 填空
    new PresetEntry('g4_mul_3x1', 4, '三位数乘一位数', 'Three-digit by one-digit', 'single',
      new ProblemSpec('mul', 100, 999)),
    new PresetEntry('g4_mul_2x2', 4, '两位数乘两位数', 'Two-digit by two-digit', 'single',
      new ProblemSpec('mul', 10, 99, false, false, false, 9, 10, 99)),
    new PresetEntry('g4_div_3x1', 4, '三位数除以一位数', 'Three-digit ÷ one-digit', 'single',
      new ProblemSpec('div', 100, 999)),
    new PresetEntry('g4_div_2d', 4, '除数是两位数', 'Two-digit divisor', 'single',
      new ProblemSpec('div', 100, 999, false, false, false, 99)),
    new PresetEntry('g4_assoc', 4, '简便运算（乘法结合律）', 'Friendly multiplication', 'mixed', null,
      new MixedSpec('mul', 'mul', false, 200, 9000, 25, 125, 9, 9, 125, true)),
    new PresetEntry('g4_vert_add', 4, '竖式·三位数加法', 'Vertical addition', 'vertical',
      new ProblemSpec('add', 100, 999)),
    new PresetEntry('g4_vert_sub', 4, '竖式·三位数减法', 'Vertical subtraction', 'vertical',
      new ProblemSpec('sub', 100, 999)),
    new PresetEntry('g4_vert_mul', 4, '竖式·两位数乘两位数', 'Vertical 2-digit × 2-digit', 'vertical',
      new ProblemSpec('mul', 10, 99, false, false, false, 9, 10, 99)),
    new PresetEntry('g4_fill', 4, '填空（三位数乘一位数）', 'Fill-in (3-digit × 1-digit)', 'fill', null, null, 'g4_mul_3x1'),
    new PresetEntry('g4_area', 4, '面积模型拆分', 'Area-model decomposition', 'figure', null, null, null, 'area'),

    // ---- 五年级（1.0.1 M8）：一位小数加减乘 + 三位数乘两位数 + 填空（小数 = dp1 缩放整数）
    new PresetEntry('g5_dec_add', 5, '一位小数加法', 'Decimal addition (1 dp)', 'single',
      new ProblemSpec('add', 1, 99, false, false, false, 9, 2, 9, 1)),
    new PresetEntry('g5_dec_sub', 5, '一位小数减法', 'Decimal subtraction (1 dp)', 'single',
      new ProblemSpec('sub', 1, 99, false, false, false, 9, 2, 9, 1)),
    new PresetEntry('g5_dec_mul', 5, '小数乘整数', 'Decimal × integer', 'single',
      new ProblemSpec('mul', 1, 99, false, false, false, 9, 2, 9, 1)),
    new PresetEntry('g5_mul_3x2', 5, '三位数乘两位数', 'Three-digit by two-digit', 'single',
      new ProblemSpec('mul', 100, 999, false, false, false, 9, 10, 99)),
    new PresetEntry('g5_fill', 5, '填空（一位小数加法）', 'Fill-in (decimal addition)', 'fill', null, null, 'g5_dec_add'),
    new PresetEntry('g5_numline', 5, '小数数轴填空', 'Decimal number-line blanks', 'figure', null, null, null, 'decnumline'),
    new PresetEntry('g5_area', 5, '小数面积模型拆分', 'Decimal area-model decomposition', 'figure', null, null, null, 'decarea'),

    // ---- 六年级（v1.1 第四批）：分数乘整数 / 百分数互化 / 比的化简 / 分数面积模型
    new PresetEntry('g6_frac_mul', 6, '分数乘整数', 'Fraction × integer', 'figure', null, null, null, 'fracmul'),
    new PresetEntry('g6_percent', 6, '百分数互化', 'Percent conversions', 'figure', null, null, null, 'percent'),
    new PresetEntry('g6_ratio', 6, '比的化简', 'Ratio simplification', 'figure', null, null, null, 'ratio'),
    new PresetEntry('g6_frac_area', 6, '分数面积模型', 'Fraction area model', 'figure', null, null, null, 'fracarea'),
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
