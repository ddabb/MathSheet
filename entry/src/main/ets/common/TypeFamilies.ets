/**
 * UI 层题型家族表（计划 §5.1 输入零门槛）：把细粒度预设（基础/进阶变体）
 * 归并为家长视角的"题型家族"（如"100 以内加减"），难度（基础/进阶）由
 * 独立分段选择器决定；家族 × 难度 → GradePresets 预设 id 列表。
 * 无难度区分的家族（如表内乘除、带括号两步）两档同源。
 */

export class TypeFamily {
  id: string;
  labelZh: string;
  labelEn: string;
  /** 基础难度映射的预设 id 列表。 */
  baseIds: string[];
  /** 进阶难度映射的预设 id 列表（无区分时与 baseIds 相同）。 */
  plusIds: string[];

  constructor(id: string, labelZh: string, labelEn: string, baseIds: string[], plusIds: string[]) {
    this.id = id;
    this.labelZh = labelZh;
    this.labelEn = labelEn;
    this.baseIds = baseIds;
    this.plusIds = plusIds;
  }
}

export class TypeFamilies {
  static readonly FAMILIES: TypeFamily[] = [
    // ---- 一年级
    new TypeFamily('f1_10', '10以内加减', 'Add/sub within 10',
      ['g1_add10', 'g1_sub10'], ['g1_add10', 'g1_sub10']),
    new TypeFamily('f1_20', '20以内加减', 'Add/sub within 20',
      ['g1_add20_base', 'g1_sub20_base'], ['g1_add20_plus', 'g1_sub20_plus']),
    new TypeFamily('f1_chain', '连加连减', 'Chained add/sub',
      ['g1_chain_add', 'g1_chain_sub'], ['g1_chain_add', 'g1_chain_sub']),
    new TypeFamily('f1_fill', '填空题', 'Fill-in blanks', ['g1_fill'], ['g1_fill']),
    new TypeFamily('f1_pic', '看图列式', 'Picture equations',
      ['g1_pic_add'], ['g1_pic_add', 'g1_pic_sub']),
    // ---- 二年级
    new TypeFamily('f2_100', '100以内加减', 'Add/sub within 100',
      ['g2_add100_base', 'g2_sub100_base'], ['g2_add100_plus', 'g2_sub100_plus']),
    new TypeFamily('f2_mul', '表内乘法', 'Times table', ['g2_mul_table'], ['g2_mul_table']),
    new TypeFamily('f2_div', '表内除法', 'Division table', ['g2_div_table'], ['g2_div_table']),
    new TypeFamily('f2_mix', '乘加乘减', 'Multiply then add/sub',
      ['g2_mul_add', 'g2_mul_sub'], ['g2_mul_add', 'g2_mul_sub']),
    new TypeFamily('f2_fill', '填空题', 'Fill-in blanks', ['g2_fill'], ['g2_fill']),
    new TypeFamily('f2_array', '点阵乘法', 'Dot-array multiplication', ['g2_array'], ['g2_array']),
    new TypeFamily('f2_numline', '数轴填空', 'Number-line blanks', ['g2_numline'], ['g2_numline']),
    // ---- 三年级
    new TypeFamily('f3_3d', '三位数加减', 'Three-digit add/sub',
      ['g3_add_3d', 'g3_sub_3d'], ['g3_add_3d', 'g3_sub_3d']),
    new TypeFamily('f3_mul', '两位数乘一位数', 'Two-digit × one-digit',
      ['g3_mul_2x1'], ['g3_mul_2x1']),
    new TypeFamily('f3_bracket', '带括号两步', 'Two-step with brackets',
      ['g3_bracket_add', 'g3_bracket_sub'], ['g3_bracket_add', 'g3_bracket_sub']),
    new TypeFamily('f3_fill', '填空题', 'Fill-in blanks', ['g3_fill'], ['g3_fill']),
    new TypeFamily('f3_numline', '数轴填空', 'Number-line blanks', ['g3_numline'], ['g3_numline']),
    // ---- 四年级（1.0.1 M8）
    new TypeFamily('f4_mul', '多位数乘法', 'Multi-digit multiplication',
      ['g4_mul_3x1'], ['g4_mul_2x2']),
    new TypeFamily('f4_div', '多位数除法', 'Multi-digit division',
      ['g4_div_3x1'], ['g4_div_2d']),
    new TypeFamily('f4_assoc', '简便运算', 'Friendly arithmetic',
      ['g4_assoc'], ['g4_assoc']),
    new TypeFamily('f4_vert', '竖式计算', 'Vertical calculation',
      ['g4_vert_add', 'g4_vert_sub'], ['g4_vert_add', 'g4_vert_sub', 'g4_vert_mul']),
    new TypeFamily('f4_fill', '填空题', 'Fill-in blanks', ['g4_fill'], ['g4_fill']),
    new TypeFamily('f4_area', '面积模型拆分', 'Area-model decomposition', ['g4_area'], ['g4_area']),
    // ---- 五年级（1.0.1 M8）
    new TypeFamily('f5_dec', '小数加减', 'Decimal add/sub',
      ['g5_dec_add', 'g5_dec_sub'], ['g5_dec_add', 'g5_dec_sub']),
    new TypeFamily('f5_decmul', '小数乘整数', 'Decimal × integer',
      ['g5_dec_mul'], ['g5_dec_mul']),
    new TypeFamily('f5_mul', '三位数乘两位数', 'Three-digit × two-digit',
      ['g5_mul_3x2'], ['g5_mul_3x2']),
    new TypeFamily('f5_fill', '填空题', 'Fill-in blanks', ['g5_fill'], ['g5_fill']),
    new TypeFamily('f5_numline', '小数数轴填空', 'Decimal number-line blanks',
      ['g5_numline'], ['g5_numline']),
    new TypeFamily('f5_area', '小数面积模型拆分', 'Decimal area-model decomposition',
      ['g5_area'], ['g5_area']),
    // ---- 六年级（v1.1 第四批）
    new TypeFamily('f6_frac_mul', '分数乘整数', 'Fraction × integer',
      ['g6_frac_mul'], ['g6_frac_mul']),
    new TypeFamily('f6_percent', '百分数互化', 'Percent conversions',
      ['g6_percent'], ['g6_percent']),
    new TypeFamily('f6_ratio', '比的化简', 'Ratio simplification',
      ['g6_ratio'], ['g6_ratio']),
    new TypeFamily('f6_frac_area', '分数面积模型', 'Fraction area model',
      ['g6_frac_area'], ['g6_frac_area'])
  ];

  static forGrade(grade: number): TypeFamily[] {
    const out: TypeFamily[] = [];
    for (const f of TypeFamilies.FAMILIES) {
      if (f.id.indexOf(`f${grade}_`) === 0) {
        out.push(f);
      }
    }
    return out;
  }

  static byId(id: string): TypeFamily | null {
    for (const f of TypeFamilies.FAMILIES) {
      if (f.id === id) {
        return f;
      }
    }
    return null;
  }

  /** 各年级默认勾选家族（对应家长最常用练习组合）。 */
  static defaultsForGrade(grade: number): string[] {
    if (grade === 1) {
      return ['f1_20'];
    }
    if (grade === 3) {
      return ['f3_3d', 'f3_mul'];
    }
    if (grade === 4) {
      return ['f4_mul', 'f4_div'];
    }
    if (grade === 5) {
      return ['f5_dec', 'f5_mul'];
    }
    if (grade === 6) {
      return ['f6_frac_mul', 'f6_percent'];
    }
    return ['f2_100', 'f2_mul', 'f2_div'];
  }

  /** 家族 id 列表 × 难度 → 预设 id 列表（去重保序，勾选顺序即卷内轮转顺序）。 */
  static resolvePresetIds(familyIds: string[], advanced: boolean): string[] {
    const out: string[] = [];
    for (const fid of familyIds) {
      const f: TypeFamily | null = TypeFamilies.byId(fid);
      if (f === null) {
        continue;
      }
      const ids: string[] = advanced ? f.plusIds : f.baseIds;
      for (const id of ids) {
        if (out.indexOf(id) < 0) {
          out.push(id);
        }
      }
    }
    return out;
  }
}
