/**
 * v1.1 §17.3 数形结合测试套件（figTest）——看图列式 / 点阵乘法 / 数轴填空 / 面积模型拆分
 * / 小数数轴 / 小数面积模型（五年级）：
 *   - FigureGen 结构与范围：行数/点数/挖空位/键（fp·fa·fn 前缀）与种子确定性；
 *   - 判分回环：题面单个 □ 走 QuizJudge 既有填空分支，期望答案 = 挖空值；
 *   - 宽度预算：em 字宽模型（fontTools 实测常数）断言所有行不越 4 列版心（6.737em）；
 *   - 预设/家族/混编集成：5 个 figure 预设入表、家族解析、buildMultiSheetTraced 溯源；
 *   - 版面多行块：lineCountsOf 与整块放置；渲染冒烟：图形分支 + 竖式分支同页不抛错。
 *
 * 运行协议（模拟器 class 过滤定向跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class figTest -s timeout 30000
 */
import { describe, it, expect } from '@ohos/hypium';
import { image } from '@kit.ImageKit';
import { Rng } from '../../../main/ets/core/Rng';
import { FigureGen } from '../../../main/ets/core/FigureGen';
import { SheetItem } from '../../../main/ets/core/SheetModel';
import { QuizJudge } from '../../../main/ets/core/QuizJudge';
import { GradePresets, PresetEntry } from '../../../main/ets/core/GradePresets';
import { SheetGen } from '../../../main/ets/core/SheetGen';
import { SheetLayout, LayoutSpec } from '../../../main/ets/core/SheetLayout';
import { TypeFamilies, TypeFamily } from '../../../main/ets/common/TypeFamilies';
import { PageRenderRequest, SheetRenderer } from '../../../main/ets/render/SheetRenderer';

/** 单字符 em 宽（fontTools 实测 NotoSansSC 子集 advance）。 */
function charEm(ch: string): number {
  if (ch >= '0' && ch <= '9') {
    return 0.555;
  }
  if (ch === ' ') {
    return 0.224;
  }
  if (ch === '+' || ch === '\u2212' || ch === '=') {
    return 0.555;
  }
  if (ch === '.') {
    return 0.278;
  }
  if (ch === '/') {
    return 0.392;
  }
  if (ch === ':') {
    return 0.278;
  }
  if (ch === '%') {
    return 0.921;
  }
  if (ch === '\u2014') {
    return 0.894;
  }
  return 1.0; // ● ○ □ × 等全角
}

function lineEm(line: string): number {
  let w: number = 0;
  for (let i: number = 0; i < line.length; i++) {
    w += charEm(line.charAt(i));
  }
  return w;
}

function isDotLine(line: string): boolean {
  if (line.length === 0) {
    return false;
  }
  for (let i: number = 0; i < line.length; i++) {
    const ch: string = line.charAt(i);
    if (ch !== '\u25cf' && ch !== '\u25cb' && ch !== ' ') {
      return false;
    }
  }
  return true;
}

/** 挖空位推断（三题型通用）：□ 在行首 → 0；在 '=' 后 → 2；运算符与 = 之间 → 1。 */
function boxPosOf(exprLine: string): number {
  const boxIdx: number = exprLine.indexOf('\u25a1');
  const eqIdx: number = exprLine.indexOf('=');
  expect(boxIdx >= 0).assertTrue();
  expect(eqIdx > 0).assertTrue();
  return boxIdx === 0 ? 0 : (boxIdx > eqIdx ? 2 : 1);
}

function countChar(s: string, ch: string): number {
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    if (s.charAt(i) === ch) {
      n++;
    }
  }
  return n;
}

/** 4 列版心最紧预算：512px ÷ 76px = 6.737em。 */
const FOUR_COL_EM: number = 6.737;

export default function figTest() {
  describe('figTest', () => {
    // ---- 看图列式·加法：结构与范围（和 ≤ 10，两组 ●，2 行，单个 □，键与确定性） ----
    it('Fig_picAdd_range', 0, () => {
      const rng: Rng = new Rng(7);
      const keysA: string[] = [];
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.picAdd(rng);
        keysA.push(item.key);
        const lines: string[] = item.questionText.split('\n');
        expect(lines.length).assertEqual(2);
        const groups: string[] = lines[0].split(' ');
        expect(groups.length).assertEqual(2);
        const a: number = groups[0].length;
        const b: number = groups[1].length;
        expect(a >= 2 && a <= 9).assertTrue();
        expect(b >= 1 && b <= 9).assertTrue();
        expect(a + b <= 10).assertTrue();
        expect(countChar(lines[0], '\u25cf')).assertEqual(a + b);
        expect(countChar(lines[1], '\u25a1')).assertEqual(1);
        const pos: number = boxPosOf(lines[1]);
        if (pos === 0) {
          expect(lines[1]).assertEqual(`\u25a1 + ${b} =`);
        } else if (pos === 1) {
          expect(lines[1]).assertEqual(`${a} + \u25a1 =`);
        } else {
          expect(lines[1]).assertEqual(`${a} + ${b} = \u25a1`);
        }
        expect(item.key).assertEqual(`fpa${a}_${b}_${pos}`);
        expect(item.questionText.charAt(item.questionText.length - 1) !== '\n').assertTrue();
      }
      const rng2: Rng = new Rng(7);
      for (let i: number = 0; i < 300; i++) {
        expect(FigureGen.picAdd(rng2).key).assertEqual(keysA[i]);
      }
    });

    // ---- 看图列式·加法：判分回环（□ 填空分支，期望 = 挖空值，正确/错误判定） ----
    it('Fig_picAdd_judge', 0, () => {
      const rng: Rng = new Rng(21);
      for (let i: number = 0; i < 200; i++) {
        const item: SheetItem = FigureGen.picAdd(rng);
        const lines: string[] = item.questionText.split('\n');
        const groups: string[] = lines[0].split(' ');
        const a: number = groups[0].length;
        const b: number = groups[1].length;
        const pos: number = boxPosOf(lines[1]);
        const value: number = pos === 0 ? a : (pos === 1 ? b : a + b);
        expect(item.answerText).assertEqual(item.questionText.replace('\u25a1', String(value)));
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(value));
        expect(QuizJudge.isCorrect(String(value), expected)).assertTrue();
        expect(QuizJudge.isCorrect(String(value + 1), expected)).assertFalse();
      }
    });

    // ---- 看图列式·减法：结构 + 判分（● 剩余 + ○ 划掉，总数 ≤ 12） ----
    it('Fig_picSub_range_judge', 0, () => {
      const rng: Rng = new Rng(33);
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.picSub(rng);
        const lines: string[] = item.questionText.split('\n');
        expect(lines.length).assertEqual(2);
        const rest: number = countChar(lines[0], '\u25cf');
        const removed: number = countChar(lines[0], '\u25cb');
        expect(rest + removed).assertEqual(lines[0].length);
        expect(rest >= 2 && rest <= 8).assertTrue();
        expect(removed >= 1 && removed <= 6).assertTrue();
        expect(rest + removed <= 12).assertTrue();
        expect(countChar(lines[1], '\u25a1')).assertEqual(1);
        const total: number = rest + removed;
        const pos: number = boxPosOf(lines[1]);
        if (pos === 0) {
          expect(lines[1]).assertEqual(`\u25a1 \u2212 ${removed} =`);
        } else if (pos === 1) {
          expect(lines[1]).assertEqual(`${total} \u2212 \u25a1 =`);
        } else {
          expect(lines[1]).assertEqual(`${total} \u2212 ${removed} = \u25a1`);
        }
        expect(item.key).assertEqual(`fps${total}_${removed}_${pos}`);
        const value: number = pos === 0 ? total : (pos === 1 ? removed : rest);
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(value));
        expect(QuizJudge.isCorrect(String(value), expected)).assertTrue();
        expect(QuizJudge.isCorrect('0', expected)).assertFalse();
      }
    });

    // ---- 点阵乘法：结构（2..6 行 × 2..9 列，r+1 行文本，键 fam） ----
    it('Fig_array_structure', 0, () => {
      const rng: Rng = new Rng(55);
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.arrayMul(rng);
        const lines: string[] = item.questionText.split('\n');
        expect(lines.length >= 3 && lines.length <= 7).assertTrue();
        const rows: number = lines.length - 1;
        const cols: number = lines[0].length;
        expect(cols >= 2 && cols <= 9).assertTrue();
        for (let r: number = 0; r < rows; r++) {
          expect(lines[r].length).assertEqual(cols);
          expect(countChar(lines[r], '\u25cf')).assertEqual(cols);
        }
        const expr: string = lines[rows];
        expect(countChar(expr, '\u25a1')).assertEqual(1);
        const pos: number = boxPosOf(expr);
        if (pos === 0) {
          expect(expr).assertEqual(`\u25a1 \u00d7 ${cols} = ${rows * cols}`);
        } else if (pos === 1) {
          expect(expr).assertEqual(`${rows} \u00d7 \u25a1 = ${rows * cols}`);
        } else {
          expect(expr).assertEqual(`${rows} \u00d7 ${cols} = \u25a1`);
        }
        expect(item.key).assertEqual(`fam${rows}x${cols}_${pos}`);
        const value: number = pos === 0 ? rows : (pos === 1 ? cols : rows * cols);
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(value));
        expect(QuizJudge.isCorrect(String(value), expected)).assertTrue();
      }
    });

    // ---- 数轴填空：结构 + 判分（0 起等差 4 刻度，step 2..5 / 6..15，键 fnl） ----
    it('Fig_numline_structure', 0, () => {
      const rng: Rng = new Rng(77);
      for (let i: number = 0; i < 200; i++) {
        const item: SheetItem = FigureGen.numLine(rng, 2, 5);
        const parts: string[] = item.questionText.split('\u2014');
        expect(parts.length).assertEqual(4);
        expect(parts[0]).assertEqual('0');
        let step: number = 0;
        let pos: number = -1;
        for (let j: number = 1; j < 4; j++) {
          if (parts[j] === '\u25a1') {
            pos = j;
          } else {
            step = Number(parts[j]) / j;
          }
        }
        expect(pos >= 1 && pos <= 3).assertTrue();
        expect(step >= 2 && step <= 5).assertTrue();
        for (let j: number = 1; j < 4; j++) {
          if (j !== pos) {
            expect(Number(parts[j])).assertEqual(j * step);
          }
        }
        expect(item.key).assertEqual(`fnl${step}_${pos}`);
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(pos * step));
        expect(QuizJudge.isCorrect(String(pos * step), expected)).assertTrue();
      }
      for (let i: number = 0; i < 200; i++) {
        const item: SheetItem = FigureGen.numLine(rng, 6, 15);
        const parts: string[] = item.questionText.split('\u2014');
        expect(parts.length).assertEqual(4);
        expect(parts[0]).assertEqual('0');
        let step: number = 0;
        let pos: number = -1;
        for (let j: number = 1; j < 4; j++) {
          if (parts[j] === '\u25a1') {
            pos = j;
          } else {
            step = Number(parts[j]) / j;
          }
        }
        expect(step >= 6 && step <= 15).assertTrue();
        expect(pos >= 1 && pos <= 3).assertTrue();
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(pos * step));
      }
    });

    // ---- 宽度预算：所有行（点行按渲染层 0.55 缩放）不越 4 列版心 6.737em ----
    it('Fig_width_budget', 0, () => {
      const rng: Rng = new Rng(99);
      const items: SheetItem[] = [];
      for (let i: number = 0; i < 200; i++) {
        items.push(FigureGen.picAdd(rng));
        items.push(FigureGen.picSub(rng));
        items.push(FigureGen.arrayMul(rng));
        items.push(FigureGen.numLine(rng, 2, 5));
        items.push(FigureGen.numLine(rng, 6, 15));
        items.push(FigureGen.areaModel(rng));
        items.push(FigureGen.decNumLine(rng));
        items.push(FigureGen.decAreaModel(rng));
        items.push(FigureGen.fracMul(rng));
        items.push(FigureGen.percentX(rng));
        items.push(FigureGen.ratioSimplify(rng));
        items.push(FigureGen.fracAreaModel(rng));
      }
      expect(items.length).assertEqual(2400);
      for (const item of items) {
        const lines: string[] = item.questionText.split('\n');
        for (const line of lines) {
          const w: number = lineEm(line) * (isDotLine(line) ? 0.55 : 1.0);
          expect(w <= FOUR_COL_EM + 0.001).assertTrue();
        }
      }
    });

    // ---- 预设/家族：5 个 figure 预设入表，家族解析正确，默认勾选不含新家族 ----
    it('Fig_presets_families', 0, () => {
      const ids: string[] = ['g1_pic_add', 'g1_pic_sub', 'g2_array', 'g2_numline', 'g3_numline'];
      const figKinds: string[] = ['pic_add', 'pic_sub', 'array', 'numline2', 'numline3'];
      for (let i: number = 0; i < ids.length; i++) {
        const e: PresetEntry | null = GradePresets.byId(ids[i]);
        expect(e !== null).assertTrue();
        if (e !== null) {
          expect(e.kind).assertEqual('figure');
          expect(e.figKind).assertEqual(figKinds[i]);
          expect(e.labelZh.length > 0).assertTrue();
          expect(e.labelEn.length > 0).assertTrue();
        }
      }
      expect(TypeFamilies.resolvePresetIds(['f1_pic'], false).join(',')).assertEqual('g1_pic_add');
      expect(TypeFamilies.resolvePresetIds(['f1_pic'], true).join(','))
        .assertEqual('g1_pic_add,g1_pic_sub');
      expect(TypeFamilies.resolvePresetIds(['f2_array'], false).join(',')).assertEqual('g2_array');
      expect(TypeFamilies.resolvePresetIds(['f2_numline'], false).join(',')).assertEqual('g2_numline');
      expect(TypeFamilies.resolvePresetIds(['f3_numline'], false).join(',')).assertEqual('g3_numline');
      for (let gi: number = 1; gi <= 3; gi++) {
        const resolved: string[] =
          TypeFamilies.resolvePresetIds(TypeFamilies.defaultsForGrade(gi), false);
        for (const id of ids) {
          expect(resolved.indexOf(id) < 0).assertTrue();
        }
      }
      // 第三批（五年级）：小数数轴 + 小数面积模型，默认勾选不含
      const g5Ids: string[] = ['g5_numline', 'g5_area'];
      const g5Kinds: string[] = ['decnumline', 'decarea'];
      for (let i: number = 0; i < g5Ids.length; i++) {
        const e5: PresetEntry | null = GradePresets.byId(g5Ids[i]);
        expect(e5 !== null).assertTrue();
        if (e5 !== null) {
          expect(e5.kind).assertEqual('figure');
          expect(e5.figKind).assertEqual(g5Kinds[i]);
          expect(e5.grade).assertEqual(5);
        }
      }
      expect(TypeFamilies.resolvePresetIds(['f5_numline'], false).join(',')).assertEqual('g5_numline');
      expect(TypeFamilies.resolvePresetIds(['f5_numline'], true).join(',')).assertEqual('g5_numline');
      expect(TypeFamilies.resolvePresetIds(['f5_area'], false).join(',')).assertEqual('g5_area');
      expect(TypeFamilies.resolvePresetIds(['f5_area'], true).join(',')).assertEqual('g5_area');
      expect(TypeFamilies.defaultsForGrade(5).indexOf('f5_numline') < 0).assertTrue();
      expect(TypeFamilies.defaultsForGrade(5).indexOf('f5_area') < 0).assertTrue();
      // 第四批（六年级）：分数乘整数 / 百分数互化 / 比的化简 / 分数面积模型
      const g6Ids: string[] = ['g6_frac_mul', 'g6_percent', 'g6_ratio', 'g6_frac_area'];
      const g6Kinds: string[] = ['fracmul', 'percent', 'ratio', 'fracarea'];
      for (let i: number = 0; i < g6Ids.length; i++) {
        const e6: PresetEntry | null = GradePresets.byId(g6Ids[i]);
        expect(e6 !== null).assertTrue();
        if (e6 !== null) {
          expect(e6.kind).assertEqual('figure');
          expect(e6.figKind).assertEqual(g6Kinds[i]);
          expect(e6.grade).assertEqual(6);
        }
        const f6Id: string[] = [`f6_${g6Ids[i].substring(3)}`];
        expect(TypeFamilies.resolvePresetIds(f6Id, false).join(',')).assertEqual(g6Ids[i]);
        expect(TypeFamilies.resolvePresetIds(f6Id, true).join(',')).assertEqual(g6Ids[i]);
      }
      // 六年级默认勾选 = 分数乘整数 + 百分数（f6_ratio/f6_frac_area 不含）
      expect(TypeFamilies.defaultsForGrade(6).join(',')).assertEqual('f6_frac_mul,f6_percent');
      expect(TypeFamilies.defaultsForGrade(6).indexOf('f6_ratio') < 0).assertTrue();
      expect(TypeFamilies.defaultsForGrade(6).indexOf('f6_frac_area') < 0).assertTrue();
      const f6Ids: string[] = TypeFamilies.forGrade(6).map((f: TypeFamily) => f.id);
      expect(f6Ids.join(',')).assertEqual('f6_frac_mul,f6_percent,f6_ratio,f6_frac_area');
      for (const id of TypeFamilies.resolvePresetIds(f6Ids, false)) {
        expect(GradePresets.byId(id) !== null).assertTrue();
      }
    });

    // ---- 混编集成：buildMultiSheetTraced 轮转溯源 + 键前缀 + itemForPresetId 重生成 ----
    it('Fig_sheetgen_integration', 0, () => {
      const idOrder: string[] = ['g1_pic_add', 'g2_array', 'g2_numline', 'g3_numline', 'g1_pic_sub'];
      const prefixOf: string[] = ['fpa', 'fam', 'fnl', 'fnl', 'fps'];
      const entries: PresetEntry[] = [];
      for (const id of idOrder) {
        const e: PresetEntry | null = GradePresets.byId(id);
        expect(e !== null).assertTrue();
        if (e !== null) {
          entries.push(e);
        }
      }
      expect(entries.length).assertEqual(5);
      // 去重放行协议（Dedup.collectBy）：数轴键空间小（12/30），重复题重试期间轮转指针
      // 前移 → 逐题 presetId 不严格等于 idOrder[i%n]，断言改为逐项一致性。
      const traced = SheetGen.buildMultiSheetTraced(entries, 99, 50);
      expect(traced.items.length).assertEqual(50);
      const keys: Set<string> = new Set<string>();
      const seenPresets: Set<string> = new Set<string>();
      for (const t of traced.items) {
        keys.add(t.item.key);
        const idx: number = idOrder.indexOf(t.presetId);
        expect(idx >= 0).assertTrue();
        expect(t.item.key.indexOf(prefixOf[idx])).assertEqual(0);
        const expected: string =
          QuizJudge.expectedAnswerOf(t.item.questionText, t.item.answerText);
        expect(QuizJudge.isCorrect(expected, expected)).assertTrue();
        seenPresets.add(t.presetId);
      }
      expect(seenPresets.size).assertEqual(5);
      expect(keys.size >= 40).assertTrue(); // 放行重复有限（数轴小键空间），其余题型键空间充足
      const regen: SheetItem | null = SheetGen.itemForPresetId('g2_array', new Rng(5));
      expect(regen !== null).assertTrue();
      if (regen !== null) {
        expect(regen.key.indexOf('fam')).assertEqual(0);
      }
    });

    // ---- 版面多行块：lineCountsOf 与混排整块放置（1 行数轴 + r+1 行点阵） ----
    it('Fig_layout_multiline', 0, () => {
      const rng: Rng = new Rng(123);
      const items: SheetItem[] = [];
      for (let i: number = 0; i < 12; i++) {
        items.push(FigureGen.numLine(rng, 2, 5));
        items.push(FigureGen.arrayMul(rng));
      }
      expect(items.length).assertEqual(24);
      const counts: number[] = SheetLayout.lineCountsOf(items);
      let sum: number = 0;
      for (let i: number = 0; i < items.length; i++) {
        expect(counts[i]).assertEqual(items[i].questionText.split('\n').length);
        sum += counts[i];
      }
      expect(sum > 24).assertTrue();
      const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, '图形卷');
      const layout = SheetLayout.layout(items.length, spec, counts);
      let placed: number = 0;
      for (const page of layout.pages) {
        placed += page.items.length;
      }
      expect(placed).assertEqual(items.length);
    });

    // ---- 渲染冒烟：图形分支 + 竖式分支同页（题面/答案两模式）不抛错、尺寸正确 ----
    it('Fig_render_smoke', 0, async (): Promise<void> => {
      const rng: Rng = new Rng(456);
      const items: SheetItem[] = [];
      for (let i: number = 0; i < 3; i++) {
        items.push(FigureGen.picAdd(rng));
        items.push(FigureGen.picSub(rng));
        items.push(FigureGen.arrayMul(rng));
        items.push(FigureGen.numLine(rng, 6, 15));
        items.push(FigureGen.areaModel(rng));
        items.push(FigureGen.decNumLine(rng));
        items.push(FigureGen.decAreaModel(rng));
        items.push(FigureGen.fracMul(rng));
        items.push(FigureGen.percentX(rng));
        items.push(FigureGen.ratioSimplify(rng));
        items.push(FigureGen.fracAreaModel(rng));
      }
      // 竖式对照项（题面以 \n 结尾走 M8 右对齐分支）+ 单行横式对照
      items.push(new SheetItem('345\n+678\n\n', '345\n+678\n\n1023', 'vsmoke'));
      items.push(new SheetItem('23 + 15 =', '23 + 15 = 38', 'plain'));
      const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, '图形卷');
      const layout = SheetLayout.layout(items.length, spec, SheetLayout.lineCountsOf(items));
      const scale: number = 0.3;
      const reqQ: PageRenderRequest = new PageRenderRequest(items, layout, spec, 0,
        '第 1 / 1 页', '姓名：____ 日期：____', false, scale);
      const pmQ: image.PixelMap = await SheetRenderer.renderPage(reqQ);
      const infoQ = await pmQ.getImageInfo();
      expect(infoQ.size.width).assertEqual(Math.round(2480 * scale));
      expect(infoQ.size.height).assertEqual(Math.round(3508 * scale));
      await pmQ.release();
      const reqA: PageRenderRequest = new PageRenderRequest(items, layout, spec, 0,
        '第 1 / 1 页', '姓名：____ 日期：____', true, scale);
      const pmA: image.PixelMap = await SheetRenderer.renderPage(reqA);
      const infoA = await pmA.getImageInfo();
      expect(infoA.size.width).assertEqual(Math.round(2480 * scale));
      await pmA.release();
    });

    // ---- 面积模型拆分（四年级）：结构（4 行协议、m∈[11,49] 个位非零、c∈[12,29]）+ 判分回环 ----
    it('Fig_area_structure_judge', 0, () => {
      const rng: Rng = new Rng(88);
      const keys: Set<string> = new Set<string>();
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.areaModel(rng);
        const lines: string[] = item.questionText.split('\n');
        expect(lines.length).assertEqual(4);
        expect(lines[1]).assertEqual('');
        expect(lines[2]).assertEqual('');
        expect(lines[3]).assertEqual('\u25a1');
        const seg: string[] = lines[0].split(' ');
        expect(seg.length).assertEqual(4);
        expect(seg[1]).assertEqual('\u00d7');
        expect(seg[3]).assertEqual('=');
        const m: number = Number(seg[0]);
        const c: number = Number(seg[2]);
        expect(m >= 11 && m <= 49).assertTrue();
        expect(m % 10 >= 1).assertTrue(); // 个位非零，整十|个位分割有意义
        expect(c >= 12 && c <= 29).assertTrue();
        expect(item.key).assertEqual(`far${m}x${c}`);
        expect(item.answerText).assertEqual(`${lines[0]}\n\n\n${m * c}`);
        keys.add(item.key);
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(m * c));
        expect(QuizJudge.isCorrect(String(m * c), expected)).assertTrue();
        expect(QuizJudge.isCorrect('0', expected)).assertFalse();
      }
      expect(keys.size >= 150).assertTrue(); // 键空间 36×18=648，300 次采样期望唯一 ≈240
    });

    // ---- 面积模型：预设/家族（f4_area 两档同源，四年级默认勾选不含）+ 渲染（far 矢量 + 非 far 回退） ----
    it('Fig_area_presets_render', 0, async (): Promise<void> => {
      const e: PresetEntry | null = GradePresets.byId('g4_area');
      expect(e !== null).assertTrue();
      if (e !== null) {
        expect(e.kind).assertEqual('figure');
        expect(e.figKind).assertEqual('area');
        expect(e.grade).assertEqual(4);
      }
      expect(TypeFamilies.resolvePresetIds(['f4_area'], false).join(',')).assertEqual('g4_area');
      expect(TypeFamilies.resolvePresetIds(['f4_area'], true).join(',')).assertEqual('g4_area');
      expect(TypeFamilies.defaultsForGrade(4).indexOf('f4_area') < 0).assertTrue();
      const rng: Rng = new Rng(888);
      const items: SheetItem[] = [];
      // 竖式对照（\n 结尾走 M8 分支）+ far 4 项 + 非 far 前缀 4 行项（键前缀拒绝 → 逐行文本兜底）
      items.push(new SheetItem('345\n+678\n\n', '345\n+678\n\n1023', 'varea'));
      for (let i: number = 0; i < 4; i++) {
        items.push(FigureGen.areaModel(rng));
      }
      items.push(new SheetItem('25 \u00d7 13 =\n\n\n\u25a1', '25 \u00d7 13 =\n\n\n325', 'xnotfar'));
      const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, '面积模型');
      const layout = SheetLayout.layout(items.length, spec, SheetLayout.lineCountsOf(items));
      const scale: number = 0.3;
      const reqQ: PageRenderRequest = new PageRenderRequest(items, layout, spec, 0,
        '第 1 / 1 页', '姓名：____ 日期：____', false, scale);
      const pmQ: image.PixelMap = await SheetRenderer.renderPage(reqQ);
      const infoQ = await pmQ.getImageInfo();
      expect(infoQ.size.width).assertEqual(Math.round(2480 * scale));
      await pmQ.release();
      const reqA: PageRenderRequest = new PageRenderRequest(items, layout, spec, 0,
        '第 1 / 1 页', '姓名：____ 日期：____', true, scale);
      const pmA: image.PixelMap = await SheetRenderer.renderPage(reqA);
      const infoA = await pmA.getImageInfo();
      expect(infoA.size.width).assertEqual(Math.round(2480 * scale));
      await pmA.release();
    });

    // ---- 小数数轴（五年级）：结构（0 起等差 3 刻度，步 0.1–0.5 一位小数，□ 刻度 1/2）+ 判分数值容忍 ----
    it('Fig_decnumline_structure_judge', 0, () => {
      const rng: Rng = new Rng(66);
      const keys: Set<string> = new Set<string>();
      const fmt = (n: number): string => n % 10 === 0 ? String(n / 10) : (n / 10).toFixed(1);
      for (let i: number = 0; i < 200; i++) {
        const item: SheetItem = FigureGen.decNumLine(rng);
        keys.add(item.key);
        // 键自解析：fdl{stepT}_{pos}（stepT = 步长十分位 1..5，pos = □ 刻度 1..2）
        expect(item.key.indexOf('fdl')).assertEqual(0);
        expect(item.key.length).assertEqual(6);
        const stepTInt: number = Number(item.key.charAt(3));
        const pos: number = Number(item.key.charAt(5));
        expect(item.key.charAt(4)).assertEqual('_');
        expect(stepTInt >= 1 && stepTInt <= 5).assertTrue();
        expect(pos === 1 || pos === 2).assertTrue();
        // 刻度重建：0、s、2s（整除 10 不带点，如 0.5×2 = "1"）→ 题面/答案全文本比对
        const expA: string = `0\u2014${fmt(stepTInt)}\u2014${fmt(2 * stepTInt)}`;
        const expQ: string = pos === 1
          ? `0\u2014\u25a1\u2014${fmt(2 * stepTInt)}`
          : `0\u2014${fmt(stepTInt)}\u2014\u25a1`;
        expect(item.questionText).assertEqual(expQ);
        expect(item.answerText).assertEqual(expA);
        const valueT: number = pos * stepTInt;
        const valueStr: string = fmt(valueT);
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(valueStr);
        expect(QuizJudge.isCorrect(valueStr, expected)).assertTrue();
        expect(QuizJudge.isCorrect('0', expected)).assertFalse();
        if (valueT === 10) {
          // 整值刻度 "1" 与 "1.0" 数值等价（isCorrect 数值比较容忍）
          expect(QuizJudge.isCorrect('1.0', expected)).assertTrue();
        }
      }
      expect(keys.size).assertEqual(10); // 键空间 5 步长 × 2 位置，200 采样全覆盖
    });

    // ---- 小数面积模型（五年级）：结构（w.d×c，w/d∈[1,9]，c∈[2,9]，4 行）+ 结果补 .0 + 判分 + 确定性 ----
    it('Fig_decarea_structure_judge', 0, () => {
      const rng: Rng = new Rng(67);
      const keysA: string[] = [];
      const keySet: Set<string> = new Set<string>();
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.decAreaModel(rng);
        keysA.push(item.key);
        keySet.add(item.key);
        const lines: string[] = item.questionText.split('\n');
        expect(lines.length).assertEqual(4);
        expect(lines[1]).assertEqual('');
        expect(lines[2]).assertEqual('');
        expect(lines[3]).assertEqual('\u25a1');
        const seg: string[] = lines[0].split(' ');
        expect(seg.length).assertEqual(4);
        expect(seg[1]).assertEqual('\u00d7');
        expect(seg[3]).assertEqual('=');
        const dotIdx: number = seg[0].indexOf('.');
        expect(dotIdx).assertEqual(1); // w.d：一位整数 + 点 + 一位小数
        const w: number = Number(seg[0].charAt(0));
        const d: number = Number(seg[0].charAt(2));
        const c: number = Number(seg[2]);
        expect(w >= 1 && w <= 9).assertTrue();
        expect(d >= 1 && d <= 9).assertTrue();
        expect(c >= 2 && c <= 9).assertTrue();
        const m10: number = w * 10 + d;
        expect(item.key).assertEqual(`fdr${m10}x${c}`);
        // 结果补 .0 约定（3.0 而非 3；一位小数 toFixed）
        const productT: number = m10 * c;
        const productStr: string = productT % 10 === 0 ? `${productT / 10}.0` : (productT / 10).toFixed(1);
        expect(item.answerText).assertEqual(`${lines[0]}\n\n\n${productStr}`);
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(productStr);
        expect(QuizJudge.isCorrect(productStr, expected)).assertTrue();
        // 数值容忍："7.5" 输入 "7.5" 或补零形态等价
        expect(QuizJudge.isCorrect(String(productT / 10), expected)).assertTrue();
        expect(QuizJudge.isCorrect('0', expected)).assertFalse();
      }
      expect(keySet.size >= 150).assertTrue(); // 键空间 81×8=648，300 采样期望唯一 ≈240
      const rng2: Rng = new Rng(67);
      for (let i: number = 0; i < 300; i++) {
        expect(FigureGen.decAreaModel(rng2).key).assertEqual(keysA[i]);
      }
    });

    // ---- 六年级单行文本三题型：结构（最简性/区间/形态）+ 判分回环 + 确定性 ----
    it('Fig_g6text_structure_judge', 0, () => {
      const gcd = (x: number, y: number): number => {
        let a: number = x;
        let b: number = y;
        while (b !== 0) {
          const t: number = a % b;
          a = b;
          b = t;
        }
        return a;
      };
      // 分数乘整数：a/b 最简（a<b，b∈[2,9]），c=k·b（k∈[1,3]），□ 三位轮换
      const rngF: Rng = new Rng(166);
      const keysF: string[] = [];
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.fracMul(rngF);
        keysF.push(item.key);
        expect(item.questionText.indexOf('\n') < 0).assertTrue(); // 单行
        expect(countChar(item.questionText, '\u25a1')).assertEqual(1);
        // 键自解析：ffm{a}_{b}x{k}_{pos}
        const underIdx: number = item.key.indexOf('_');
        const a: number = Number(item.key.substring(3, underIdx));
        const xIdx: number = item.key.indexOf('x');
        const b: number = Number(item.key.substring(underIdx + 1, xIdx));
        const lastUnder: number = item.key.lastIndexOf('_');
        const k: number = Number(item.key.substring(xIdx + 1, lastUnder));
        const pos: number = Number(item.key.charAt(item.key.length - 1));
        expect(a >= 1 && a < b).assertTrue();
        expect(b >= 2 && b <= 9).assertTrue();
        expect(gcd(a, b)).assertEqual(1);
        expect(k >= 1 && k <= 3).assertTrue();
        expect(pos >= 0 && pos <= 2).assertTrue();
        const c: number = k * b;
        const frac: string = `${a}/${b}`;
        const product: number = k * a;
        let value: number = 0;
        if (pos === 0) {
          expect(item.questionText).assertEqual(`${frac} \u00d7 ${c} = \u25a1`);
          value = product;
        } else if (pos === 1) {
          expect(item.questionText).assertEqual(`${frac} \u00d7 \u25a1 = ${product}`);
          value = c;
        } else {
          expect(item.questionText).assertEqual(`\u25a1/${b} \u00d7 ${c} = ${product}`);
          value = a;
        }
        expect(item.answerText).assertEqual(item.questionText.replace('\u25a1', String(value)));
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(value));
        expect(QuizJudge.isCorrect(String(value), expected)).assertTrue();
        expect(QuizJudge.isCorrect('0', expected)).assertFalse();
      }
      const rngF2: Rng = new Rng(166);
      for (let i: number = 0; i < 300; i++) {
        expect(FigureGen.fracMul(rngF2).key).assertEqual(keysF[i]);
      }
      // 百分数互化：x=5t∈[10,95]，分数/小数/百分数三形态
      const rngP: Rng = new Rng(167);
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.percentX(rngP);
        expect(item.questionText.indexOf('\n') < 0).assertTrue();
        expect(countChar(item.questionText, '\u25a1')).assertEqual(1);
        const underIdx: number = item.key.indexOf('_');
        const x: number = Number(item.key.substring(3, underIdx));
        const form: number = Number(item.key.charAt(item.key.length - 1));
        expect(x >= 10 && x <= 95 && x % 5 === 0).assertTrue();
        expect(form >= 0 && form <= 2).assertTrue();
        const g: number = gcd(x, 100);
        const dec: string = (x / 100).toFixed(2);
        let value: string = '';
        if (form === 0) {
          expect(item.questionText).assertEqual(`${x / g}/${100 / g} = \u25a1%`);
          value = String(x);
        } else if (form === 1) {
          expect(item.questionText).assertEqual(`${dec} = \u25a1%`);
          value = String(x);
        } else {
          expect(item.questionText).assertEqual(`${x}% = \u25a1`);
          value = dec;
        }
        expect(item.answerText).assertEqual(item.questionText.replace('\u25a1', value));
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(value);
        expect(QuizJudge.isCorrect(value, expected)).assertTrue();
        expect(QuizJudge.isCorrect('1', expected)).assertFalse();
      }
      // 比的化简：p<q 最简，k∈[2,9]，pk/qk ≤ 99，□ 在化简侧
      const rngR: Rng = new Rng(168);
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.ratioSimplify(rngR);
        expect(item.questionText.indexOf('\n') < 0).assertTrue();
        expect(countChar(item.questionText, '\u25a1')).assertEqual(1);
        const underIdx: number = item.key.indexOf('_');
        const p: number = Number(item.key.substring(3, underIdx));
        const xIdx: number = item.key.indexOf('x');
        const q: number = Number(item.key.substring(underIdx + 1, xIdx));
        const lastUnder: number = item.key.lastIndexOf('_');
        const k: number = Number(item.key.substring(xIdx + 1, lastUnder));
        const pos: number = Number(item.key.charAt(item.key.length - 1));
        expect(p >= 1 && p < q && q <= 9).assertTrue();
        expect(gcd(p, q)).assertEqual(1);
        expect(k >= 2 && k <= 9).assertTrue();
        expect(p * k <= 99 && q * k <= 99).assertTrue();
        let value: number = 0;
        if (pos === 0) {
          expect(item.questionText).assertEqual(`${p * k} : ${q * k} = ${p} : \u25a1`);
          value = q;
        } else {
          expect(item.questionText).assertEqual(`${p * k} : ${q * k} = \u25a1 : ${q}`);
          value = p;
        }
        expect(item.answerText).assertEqual(item.questionText.replace('\u25a1', String(value)));
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(value));
        expect(QuizJudge.isCorrect(String(value), expected)).assertTrue();
        expect(QuizJudge.isCorrect('99', expected)).assertFalse();
      }
    });

    // ---- 分数面积模型（六年级）：结构（4 行协议、a/b 最简、c=k·b）+ 判分 + 键空间 + 确定性 ----
    it('Fig_fracarea_structure_judge', 0, () => {
      const rng: Rng = new Rng(169);
      const keysA: string[] = [];
      const keySet: Set<string> = new Set<string>();
      const gcd = (x: number, y: number): number => {
        let a: number = x;
        let b: number = y;
        while (b !== 0) {
          const t: number = a % b;
          a = b;
          b = t;
        }
        return a;
      };
      for (let i: number = 0; i < 300; i++) {
        const item: SheetItem = FigureGen.fracAreaModel(rng);
        keysA.push(item.key);
        keySet.add(item.key);
        const lines: string[] = item.questionText.split('\n');
        expect(lines.length).assertEqual(4);
        expect(lines[1]).assertEqual('');
        expect(lines[2]).assertEqual('');
        expect(lines[3]).assertEqual('\u25a1');
        const seg: string[] = lines[0].split(' ');
        expect(seg.length).assertEqual(4);
        expect(seg[1]).assertEqual('\u00d7');
        expect(seg[3]).assertEqual('=');
        const slashIdx: number = seg[0].indexOf('/');
        expect(slashIdx).assertEqual(1); // a/b：分子一位 + 斜杠 + 分母
        const a: number = Number(seg[0].charAt(0));
        const b: number = Number(seg[0].charAt(2));
        const c: number = Number(seg[2]);
        expect(a >= 1 && a < b && b >= 2 && b <= 6).assertTrue();
        expect(gcd(a, b)).assertEqual(1); // 最简分数
        expect(c % b).assertEqual(0); // b | c（结果整数）
        const k: number = c / b;
        expect(k >= 1 && k <= 4 && c <= 24).assertTrue();
        expect(item.key).assertEqual(`ffr${a}_${b}x${k}`);
        expect(item.answerText).assertEqual(`${lines[0]}\n\n\n${k * a}`);
        const expected: string = QuizJudge.expectedAnswerOf(item.questionText, item.answerText);
        expect(expected).assertEqual(String(k * a));
        expect(QuizJudge.isCorrect(String(k * a), expected)).assertTrue();
        expect(QuizJudge.isCorrect('0', expected)).assertFalse();
      }
      expect(keySet.size >= 30).assertTrue(); // 键空间 44（11 组合 × 4），300 采样期望唯一 ≈38
      const rng2: Rng = new Rng(169);
      for (let i: number = 0; i < 300; i++) {
        expect(FigureGen.fracAreaModel(rng2).key).assertEqual(keysA[i]);
      }
    });
  });
}
