/**
 * 1.0.1 M8 测试套件（g45Test）——四/五年级扩展：小数（dp=1 缩放整数）/ 竖式 / 简便运算 + M7 边界回归。
 *
 * 覆盖：
 *   - 小数核心：缩放整数恒等式、fmt 一位小数还原、乘法整数因子不缩放、键含小数点不冲突；
 *   - 竖式模型：fromVertical 4 行文本/键 'v' 前缀/判分推导（QuizJudge 竖式 + 小数分支）；
 *   - 版面流式算法：lineCountsOf 行数推导、竖式块不越界、lineCounts 全 1 与缺省逐坐标一致（黄金兼容）；
 *   - 四/五年级预设：全条目可生成、简便运算凑整性质、TypeFamilies f4/f5 映射与默认勾选；
 *   - M7 边界回归：MixedGen 极值规格（innerMin>innerMax / innerMax≫cMax / 零可行域）不崩溃 + relaxed 兜底。
 *
 * 运行协议（模拟器 class 过滤定向跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class g45Test -s timeout 30000
 */
import { describe, it, expect } from '@ohos/hypium';
import { Rng } from '../../../main/ets/core/Rng';
import { ProblemGen, ProblemSpec, Problem } from '../../../main/ets/core/ProblemGen';
import { MixedGen, MixedSpec, MixedProblem } from '../../../main/ets/core/MixedGen';
import { FillBlank, BlankProblem } from '../../../main/ets/core/FillBlank';
import { Dedup } from '../../../main/ets/core/Dedup';
import { SheetGen } from '../../../main/ets/core/SheetGen';
import { GradePresets, PresetEntry } from '../../../main/ets/core/GradePresets';
import { SheetItem } from '../../../main/ets/core/SheetModel';
import { SheetLayout, LayoutSpec, LayoutResult } from '../../../main/ets/core/SheetLayout';
import { QuizJudge } from '../../../main/ets/core/QuizJudge';
import { ProfileCodec } from '../../../main/ets/core/ProfileCodec';
import { TypeFamilies, TypeFamily } from '../../../main/ets/common/TypeFamilies';

const BATCH: number = 1000;

/** 单步小数/多位数性质断言（dp>0 时数值为缩放整数；乘法 b 为不缩放整数因子）。 */
function assertProblem(p: Problem, spec: ProblemSpec): void {
  const lo: number = Math.min(spec.min, spec.max);
  const hi: number = Math.max(spec.min, spec.max);
  if (p.op === 'add') {
    expect(p.a + p.b).assertEqual(p.answer);
    expect(p.answer >= lo && p.answer <= hi).assertTrue();
    expect(p.a >= 0 && p.a <= hi).assertTrue();
    expect(p.b >= 0 && p.b <= hi).assertTrue();
  } else if (p.op === 'sub') {
    expect(p.a - p.b).assertEqual(p.answer);
    expect(p.answer >= 0).assertTrue();
    expect(p.a >= lo && p.a <= hi).assertTrue();
    expect(p.b >= 0 && p.b <= p.a).assertTrue();
  } else if (p.op === 'mul') {
    expect(p.a * p.b).assertEqual(p.answer);
    if (spec.tableMul) {
      expect(p.a >= 2 && p.a <= 9).assertTrue();
      expect(p.b >= 2 && p.b <= 9).assertTrue();
    } else if (spec.dp > 0) {
      expect(p.a >= Math.max(1, lo) && p.a <= hi).assertTrue();
      expect(p.b >= Math.max(2, spec.bMin) && p.b <= spec.bMax).assertTrue();
    } else if (hi >= 10) {
      expect(p.b >= Math.max(2, spec.bMin) && p.b <= spec.bMax).assertTrue();
      expect(p.a >= Math.max(10, lo) && p.a <= hi).assertTrue();
    } else {
      expect(p.a >= Math.max(2, lo) && p.a <= Math.min(9, hi)).assertTrue();
      expect(p.b >= Math.max(2, lo) && p.b <= Math.min(9, hi)).assertTrue();
    }
  } else {
    expect(p.a % p.b).assertEqual(0);
    expect(p.a / p.b).assertEqual(p.answer);
    expect(p.a <= hi).assertTrue();
    expect(p.b >= 2 && p.b <= Math.max(2, Math.min(99, spec.divisorMax))).assertTrue();
    expect(p.answer >= 1).assertTrue();
    expect(p.a >= p.b).assertTrue();
  }
}

export default function g45Test() {
  describe('g45Test', () => {
    // ---- 小数核心（dp=1 缩放整数） ----
    describe('decimalCore', () => {
      it('fmt 缩放还原：一位小数补 .0，dp=0 原样', 0, () => {
        expect(ProblemGen.fmt(35, 1)).assertEqual('3.5');
        expect(ProblemGen.fmt(105, 1)).assertEqual('10.5');
        expect(ProblemGen.fmt(7, 1)).assertEqual('0.7');
        expect(ProblemGen.fmt(0, 1)).assertEqual('0.0');
        expect(ProblemGen.fmt(35, 0)).assertEqual('35');
      })

      it('一位小数加法 1000 次性质（缩放恒等式 + 文本含小数点 + 键含小数点）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 1, 99, false, false, false, 9, 2, 9, 1);
        const rng: Rng = new Rng(4001);
        for (let i = 0; i < BATCH; i++) {
          const p: Problem = ProblemGen.genAdd(spec, rng);
          assertProblem(p, spec);
          const it2: SheetItem = SheetItem.fromProblem(p);
          expect(it2.questionText.indexOf('.') > 0).assertTrue();
          expect(it2.key.indexOf('.') > 0).assertTrue();
          expect(QuizJudge.expectedAnswerOf(it2.questionText, it2.answerText).indexOf('.') > 0).assertTrue();
        }
      })

      it('一位小数减法 1000 次性质（结果非负 + 文本形态）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('sub', 1, 99, false, false, false, 9, 2, 9, 1);
        const rng: Rng = new Rng(4002);
        for (let i = 0; i < BATCH; i++) {
          const p: Problem = ProblemGen.genSub(spec, rng);
          assertProblem(p, spec);
          expect(p.answer % 10 >= 0).assertTrue();
          const it2: SheetItem = SheetItem.fromProblem(p);
          expect(it2.questionText.indexOf('\u2212') > 0).assertTrue();
          expect(it2.questionText.indexOf('.') > 0).assertTrue();
        }
      })

      it('小数乘整数 1000 次性质（a 缩放 / b 整数因子无小数点 / 键保序）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('mul', 1, 99, false, false, false, 9, 2, 9, 1);
        const rng: Rng = new Rng(4003);
        for (let i = 0; i < BATCH; i++) {
          const p: Problem = ProblemGen.genMul(spec, rng);
          assertProblem(p, spec);
          const it2: SheetItem = SheetItem.fromProblem(p);
          // 题面 "3.5 × 3 ="：乘号后整数因子无小数点，结果含小数点
          const parts: string[] = it2.questionText.split(' ');
          expect(parts.length).assertEqual(4);
          expect(parts[0].indexOf('.') > 0).assertTrue();
          expect(parts[2].indexOf('.')).assertEqual(-1);
          expect(it2.answerText.indexOf('.') > 0).assertTrue();
          // 键 "3.5×3"：小数在前、整数因子在后，保序无交换重排
          expect(p.key().startsWith(ProblemGen.fmt(p.a, 1))).assertTrue();
          expect(p.key().endsWith(String(p.b))).assertTrue();
        }
      })

      it('小数键与整数键不冲突（"3.5+2.8" ≠ "35+28"；小数乘法键 ≠ 整数乘法键）', 0, () => {
        const dec: Problem = new Problem(35, 28, 'add', 63, false, 1);
        const int: Problem = new Problem(35, 28, 'add', 63, false, 0);
        expect(dec.key()).assertEqual('2.8+3.5');
        expect(int.key()).assertEqual('28+35');
        expect(dec.key() === int.key()).assertFalse();
        const decMul: Problem = new Problem(35, 3, 'mul', 105, false, 1);
        const intMul: Problem = new Problem(35, 3, 'mul', 105, false, 0);
        expect(decMul.key()).assertEqual('3.5\u00d73');
        expect(intMul.key()).assertEqual('3\u00d735');
      })

      it('小数去重：50 题零放行、键全唯一', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 1, 99, false, false, false, 9, 2, 9, 1);
        const rng: Rng = new Rng(4004);
        const res = Dedup.collect(50, () => ProblemGen.genAdd(spec, rng));
        expect(res.problems.length).assertEqual(50);
        expect(res.duplicates).assertEqual(0);
        const keys: Set<string> = new Set<string>();
        for (const p of res.problems) {
          keys.add(p.key());
        }
        expect(keys.size).assertEqual(50);
      })

      it('小数填空：挖位值含一位小数 + 回填完整式', 0, () => {
        const base: Problem = new Problem(35, 28, 'add', 63, false, 1);
        const bA: BlankProblem = new BlankProblem(base, 'a');
        expect(bA.text).assertEqual('\u25a1+2.8=6.3');
        const itemA: SheetItem = SheetItem.fromBlank(bA);
        expect(itemA.questionText).assertEqual('\u25a1 + 2.8 = 6.3');
        expect(itemA.answerText).assertEqual('3.5 + 2.8 = 6.3');
        const bR: BlankProblem = new BlankProblem(base, 'answer');
        const itemR: SheetItem = SheetItem.fromBlank(bR);
        expect(itemR.questionText).assertEqual('3.5 + 2.8 = \u25a1');
        expect(itemR.answerText).assertEqual('3.5 + 2.8 = 6.3');
      })
    })

    // ---- 竖式模型与判分 ----
    describe('verticalModel', () => {
      it('fromVertical 黄金文本：4 行题面 / 答案追加结果行 / 键 v 前缀', 0, () => {
        const add: SheetItem = SheetItem.fromVertical(new Problem(345, 678, 'add', 1023));
        expect(add.questionText).assertEqual('345\n+678\n\n');
        expect(add.answerText).assertEqual('345\n+678\n\n1023');
        expect(add.key).assertEqual('v345+678');

        const sub: SheetItem = SheetItem.fromVertical(new Problem(500, 233, 'sub', 267));
        expect(sub.questionText).assertEqual('500\n\u2212233\n\n');
        expect(sub.key).assertEqual('v233-500');

        const mul: SheetItem = SheetItem.fromVertical(new Problem(34, 67, 'mul', 2278));
        expect(mul.questionText).assertEqual('34\n\u00d767\n\n');
        expect(mul.key).assertEqual('v34\u00d767');

        // 竖式与横式同式不同键（去重/错题本独立）
        const flat: SheetItem = SheetItem.fromProblem(new Problem(345, 678, 'add', 1023));
        expect(flat.key).assertEqual('345+678');
        expect(flat.key === add.key).assertFalse();
      })

      it('QuizJudge 竖式/小数判分推导', 0, () => {
        expect(QuizJudge.expectedAnswerOf('345\n+678\n\n', '345\n+678\n\n1023')).assertEqual('1023');
        expect(QuizJudge.expectedAnswerOf('500\n\u2212233\n\n', '500\n\u2212233\n\n267')).assertEqual('267');
        expect(QuizJudge.expectedAnswerOf('34\n\u00d767\n\n', '34\n\u00d767\n\n2278')).assertEqual('2278');
        expect(QuizJudge.isCorrect('1023', '1023')).assertTrue();

        expect(QuizJudge.expectedAnswerOf('3.5 + 2.8 =', '3.5 + 2.8 = 6.3')).assertEqual('6.3');
        expect(QuizJudge.expectedAnswerOf('3.5 \u00d7 3 =', '3.5 \u00d7 3 = 10.5')).assertEqual('10.5');
        expect(QuizJudge.isCorrect('6.30', '6.3')).assertTrue();
        expect(QuizJudge.isCorrect('6.4', '6.3')).assertFalse();

        // 小数填空：□ 位扫描含小数点（"2.8" 不截断为 "2"）
        expect(QuizJudge.expectedAnswerOf('3.5 + \u25a1 = 6.3', '3.5 + 2.8 = 6.3')).assertEqual('2.8');
        expect(QuizJudge.expectedAnswerOf('\u25a1 + 2.8 = 6.3', '3.5 + 2.8 = 6.3')).assertEqual('3.5');
        expect(QuizJudge.expectedAnswerOf('3.5 + 2.8 = \u25a1', '3.5 + 2.8 = 6.3')).assertEqual('6.3');
        // 整数填空黄金不回归
        expect(QuizJudge.expectedAnswerOf('3 + \u25a1 = 7', '3 + 4 = 7')).assertEqual('4');
        expect(QuizJudge.isCorrect('2.8', '2.8')).assertTrue();
      })
    })

    // ---- 版面流式算法（竖式多行块） ----
    describe('verticalLayout', () => {
      it('lineCountsOf：横式 1 行 / 竖式 4 行', 0, () => {
        const items: SheetItem[] = [
          SheetItem.fromProblem(new Problem(23, 15, 'add', 38)),
          SheetItem.fromVertical(new Problem(345, 678, 'add', 1023)),
          SheetItem.fromBlank(new BlankProblem(new Problem(3, 4, 'add', 7), 'b')),
          new SheetItem('a\nb\nc\nd', 'a\nb\nc\nd!', 'k')
        ];
        const counts: number[] = SheetLayout.lineCountsOf(items);
        expect(counts.length).assertEqual(4);
        expect(counts[0]).assertEqual(1);
        expect(counts[1]).assertEqual(4);
        expect(counts[2]).assertEqual(1);
        expect(counts[3]).assertEqual(4);
      })

      it('lineCounts 全 1 与缺省 null 逐坐标一致（黄金兼容）', 0, () => {
        const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, 'T');
        const ones: number[] = [];
        for (let i = 0; i < 100; i++) {
          ones.push(1);
        }
        const a: LayoutResult = SheetLayout.layout(100, spec, ones);
        const b: LayoutResult = SheetLayout.layout(100, spec);
        expect(a.pages.length).assertEqual(b.pages.length);
        for (let p = 0; p < a.pages.length; p++) {
          expect(a.pages[p].items.length).assertEqual(b.pages[p].items.length);
          for (let k = 0; k < a.pages[p].items.length; k++) {
            const ia = a.pages[p].items[k];
            const ib = b.pages[p].items[k];
            expect(`${ia.index},${ia.x},${ia.y},${ia.lines}`).assertEqual(`${ib.index},${ib.x},${ib.y},${ib.lines}`);
          }
        }
      })

      it('竖式 30 题流式布局快照（3 列 92px：12+12+6 三页，多行块不越界）', 0, () => {
        const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, 'V');
        const fours: number[] = [];
        for (let i = 0; i < 30; i++) {
          fours.push(4);
        }
        const r: LayoutResult = SheetLayout.layout(30, spec, fours);
        expect(r.rowHeight).assertEqual(166);
        expect(r.pages.length).assertEqual(3);
        expect(r.pages[0].items.length).assertEqual(12);
        expect(r.pages[1].items.length).assertEqual(12);
        expect(r.pages[2].items.length).assertEqual(6);
        expect(`${r.pages[0].items[0].index},${r.pages[0].items[0].x},${r.pages[0].items[0].y}`).assertEqual('0,144,620');
        expect(`${r.pages[0].items[1].index},${r.pages[0].items[1].x},${r.pages[0].items[1].y}`).assertEqual('1,144,1284');
        expect(`${r.pages[0].items[4].index},${r.pages[0].items[4].x},${r.pages[0].items[4].y}`).assertEqual('4,890,620');
        expect(`${r.pages[1].items[0].index},${r.pages[1].items[0].x},${r.pages[1].items[0].y}`).assertEqual('12,144,240');
        expect(`${r.pages[2].items[5].index},${r.pages[2].items[5].x},${r.pages[2].items[5].y}`).assertEqual('29,890,904');
        // 多行块底界：y − baselineOffset + lines×rowHeight ≤ bottomLimit
        const bottomLimit: number = SheetLayout.PAGE_H - SheetLayout.MARGIN - SheetLayout.FOOTER_H;
        const baselineOffset: number = Math.round(spec.fontSize * SheetLayout.BASELINE_FACTOR);
        for (const page of r.pages) {
          for (const it of page.items) {
            expect(it.lines).assertEqual(4);
            expect(it.y - baselineOffset + it.lines * r.rowHeight <= bottomLimit).assertTrue();
            expect(it.y >= (page.hasHeader ? 500 : 120) + baselineOffset - 1).assertTrue();
          }
        }
      })

      it('横竖混排流式：[1,1,4,1,4] 单列装填（列优先，块整进整出）', 0, () => {
        const spec: LayoutSpec = new LayoutSpec(2, LayoutSpec.fontSizeForColumns(2), false, '');
        const r: LayoutResult = SheetLayout.layout(5, spec, [1, 1, 4, 1, 4]);
        expect(r.pages.length).assertEqual(1);
        expect(r.pages[0].items.length).assertEqual(5);
        expect(`${r.pages[0].items[0].index},${r.pages[0].items[0].x},${r.pages[0].items[0].y},${r.pages[0].items[0].lines}`)
          .assertEqual('0,144,260,1');
        expect(`${r.pages[0].items[1].index},${r.pages[0].items[1].x},${r.pages[0].items[1].y},${r.pages[0].items[1].lines}`)
          .assertEqual('1,144,454,1');
        expect(`${r.pages[0].items[2].index},${r.pages[0].items[2].x},${r.pages[0].items[2].y},${r.pages[0].items[2].lines}`)
          .assertEqual('2,144,648,4');
        expect(`${r.pages[0].items[3].index},${r.pages[0].items[3].x},${r.pages[0].items[3].y},${r.pages[0].items[3].lines}`)
          .assertEqual('3,144,1424,1');
        expect(`${r.pages[0].items[4].index},${r.pages[0].items[4].x},${r.pages[0].items[4].y},${r.pages[0].items[4].lines}`)
          .assertEqual('4,144,1618,4');
      })

      it('lineCounts 短于题数：缺失下标按 1 行兜底', 0, () => {
        const spec: LayoutSpec = new LayoutSpec(2, LayoutSpec.fontSizeForColumns(2), false, '');
        const r: LayoutResult = SheetLayout.layout(3, spec, [4]);
        expect(r.pages[0].items.length).assertEqual(3);
        expect(r.pages[0].items[0].lines).assertEqual(4);
        expect(r.pages[0].items[1].lines).assertEqual(1);
        expect(r.pages[0].items[2].lines).assertEqual(1);
      })
    })

    // ---- 四/五年级预设与家族 ----
    describe('grade45Presets', () => {
      it('四/五年级全条目单条生成：形态断言（竖式 4 行 / 小数含点 / 简便两乘号 / 填空含 □）', 0, () => {
        const verticalIds: string[] = ['g4_vert_add', 'g4_vert_sub', 'g4_vert_mul'];
        const decimalIds: string[] = ['g5_dec_add', 'g5_dec_sub', 'g5_dec_mul'];
        for (const id of verticalIds) {
          const rng: Rng = new Rng(4100);
          for (let i = 0; i < 50; i++) {
            const it: SheetItem | null = SheetGen.itemForPresetId(id, rng);
            expect(it !== null).assertTrue();
            if (it !== null) {
              expect(it.questionText.split('\n').length).assertEqual(4);
              expect(it.key.indexOf('v')).assertEqual(0);
              expect(QuizJudge.expectedAnswerOf(it.questionText, it.answerText).length > 0).assertTrue();
            }
          }
        }
        for (const id of decimalIds) {
          const rng: Rng = new Rng(4101);
          for (let i = 0; i < 50; i++) {
            const it: SheetItem | null = SheetGen.itemForPresetId(id, rng);
            expect(it !== null).assertTrue();
            if (it !== null) {
              expect(it.questionText.indexOf('.') > 0).assertTrue();
              expect(QuizJudge.expectedAnswerOf(it.questionText, it.answerText).indexOf('.') > 0).assertTrue();
            }
          }
        }
        const assocRng: Rng = new Rng(4102);
        for (let i = 0; i < 50; i++) {
          const it: SheetItem | null = SheetGen.itemForPresetId('g4_assoc', assocRng);
          expect(it !== null).assertTrue();
          if (it !== null) {
            expect(it.questionText.split('\u00d7').length).assertEqual(3);
          }
        }
        const fillRng: Rng = new Rng(4103);
        for (let i = 0; i < 50; i++) {
          const it: SheetItem | null = SheetGen.itemForPresetId('g5_fill', fillRng);
          expect(it !== null).assertTrue();
          if (it !== null) {
            expect(it.questionText.indexOf('\u25a1') >= 0).assertTrue();
            expect(it.questionText.indexOf('.') > 0).assertTrue();
            expect(it.answerText.indexOf('\u25a1')).assertEqual(-1);
          }
        }
      })

      it('简便运算（g4_assoc）1000 次性质：凑整对内层 ∈ {100,200,500,1000} + 零放宽', 0, () => {
        const e: PresetEntry | null = GradePresets.byId('g4_assoc');
        expect(e !== null).assertTrue();
        if (e !== null) {
          const ms: MixedSpec | null = e.mixed;
          expect(ms !== null).assertTrue();
          if (ms !== null) {
            const rng: Rng = new Rng(4104);
            const products: Set<number> = new Set<number>();
            for (let i = 0; i < BATCH; i++) {
              const m: MixedProblem = MixedGen.generate(ms, rng);
              const inner: number = m.a * m.b;
              expect(inner === 100 || inner === 200 || inner === 500 || inner === 1000).assertTrue();
              expect(m.c >= 2 && m.c <= 9).assertTrue();
              expect(m.answer).assertEqual(inner * m.c);
              expect(m.relaxed).assertFalse();
              expect(m.answer >= 200 && m.answer <= 9000).assertTrue();
              expect(m.a >= 2 && m.a <= 125).assertTrue();
              expect(m.b >= 2 && m.b <= 125).assertTrue();
              products.add(inner);
            }
            expect(products.size).assertEqual(4);
          }
        }
      })

      it('四/五年级整卷生成 + 混排布局全放置（横竖混排不越界）', 0, () => {
        const grades: number[] = [4, 5];
        for (const grade of grades) {
          const entries: PresetEntry[] = GradePresets.forGrade(grade);
          expect(entries.length >= 4).assertTrue();
          const sheet = SheetGen.buildMultiSheet(entries, 20261029, 45);
          expect(sheet.items.length).assertEqual(45);
          const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, `G${grade}`);
          const r: LayoutResult = SheetLayout.layout(sheet.items.length, spec,
            SheetLayout.lineCountsOf(sheet.items));
          let placed: number = 0;
          const bottomLimit: number = SheetLayout.PAGE_H - SheetLayout.MARGIN - SheetLayout.FOOTER_H;
          const baselineOffset: number = Math.round(spec.fontSize * SheetLayout.BASELINE_FACTOR);
          for (const page of r.pages) {
            for (const it of page.items) {
              placed++;
              expect(it.y - baselineOffset + it.lines * r.rowHeight <= bottomLimit).assertTrue();
            }
          }
          expect(placed).assertEqual(45);
        }
      })

      it('TypeFamilies f4/f5：家族映射 + 默认勾选 + 预设 id 可解析', 0, () => {
        // 注：数组不能直接 assertEqual（引用比较），用 join 文本比较
        expect(TypeFamilies.resolvePresetIds(['f4_mul'], false).join(',')).assertEqual('g4_mul_3x1');
        expect(TypeFamilies.resolvePresetIds(['f4_mul'], true).join(',')).assertEqual('g4_mul_2x2');
        expect(TypeFamilies.resolvePresetIds(['f4_div'], true).join(',')).assertEqual('g4_div_2d');
        expect(TypeFamilies.resolvePresetIds(['f4_vert'], false).join(',')).assertEqual('g4_vert_add,g4_vert_sub');
        expect(TypeFamilies.resolvePresetIds(['f4_vert'], true).join(','))
          .assertEqual('g4_vert_add,g4_vert_sub,g4_vert_mul');
        expect(TypeFamilies.resolvePresetIds(['f5_dec'], false).join(',')).assertEqual('g5_dec_add,g5_dec_sub');
        expect(TypeFamilies.defaultsForGrade(4).join(',')).assertEqual('f4_mul,f4_div');
        expect(TypeFamilies.defaultsForGrade(5).join(',')).assertEqual('f5_dec,f5_mul');
        for (const fid of TypeFamilies.defaultsForGrade(4).concat(TypeFamilies.defaultsForGrade(5))) {
          expect(TypeFamilies.byId(fid) !== null).assertTrue();
        }
        const f4Ids: string[] = TypeFamilies.forGrade(4).map((f: TypeFamily) => f.id);
        const f5Ids: string[] = TypeFamilies.forGrade(5).map((f: TypeFamily) => f.id);
        const all: string[] = TypeFamilies.resolvePresetIds(f4Ids.concat(f5Ids), false);
        for (const id of all) {
          expect(GradePresets.byId(id) !== null).assertTrue();
        }
      })

      it('ProfileCodec 年级钳制 1-6（非法回 2）', 0, () => {
        // 全量档案编解码见 memberTest；此处仅回归年级扩展点（v1.1 扩六年级）
        expect(ProfileCodec.clampGrade(4)).assertEqual(4);
        expect(ProfileCodec.clampGrade(5)).assertEqual(5);
        expect(ProfileCodec.clampGrade(6)).assertEqual(6);
        expect(ProfileCodec.clampGrade(0)).assertEqual(2);
        expect(ProfileCodec.clampGrade(7)).assertEqual(2);
        expect(ProfileCodec.clampGrade(2.5)).assertEqual(2);
      })
    })

    // ---- M7 边界回归（MixedGen 极值规格） ----
    describe('mixedBoundary', () => {
      it('极值规格不崩溃：innerMin>innerMax / innerMax≫cMax / 因子极小（恒等式全成立）', 0, () => {
        const extremes: MixedSpec[] = [
          new MixedSpec('add', 'add', false, 1, 1000000, 1, 1000000, 5),
          new MixedSpec('add', 'add', false, 5, 10, 100, 1, 5),
          new MixedSpec('sub', 'sub', true, 1, 1000, 1000, 1, 3),
          new MixedSpec('mul', 'mul', false, 4, 36, 2, 6, 2, 2, 6)
        ];
        const rng: Rng = new Rng(4200);
        for (const spec of extremes) {
          for (let i = 0; i < 200; i++) {
            const m: MixedProblem = MixedGen.generate(spec, rng);
            const inner: number = spec.op1 === 'add' ? m.a + m.b : spec.op1 === 'sub' ? m.a - m.b : m.a * m.b;
            const expected: number = spec.op2 === 'add' ? inner + m.c : spec.op2 === 'sub' ? inner - m.c : inner * m.c;
            expect(m.answer).assertEqual(expected);
            if (!m.relaxed) {
              const lo: number = Math.min(spec.min, spec.max);
              const hi: number = Math.max(spec.min, spec.max);
              expect(m.answer >= lo && m.answer <= hi).assertTrue();
            }
          }
        }
      })

      it('零可行域（结果区间不可达）：64 次后放宽标记，恒等式仍成立', 0, () => {
        const spec: MixedSpec = new MixedSpec('add', 'mul', false, 1000000, 2000000, 1, 5, 20, 9);
        const rng: Rng = new Rng(4201);
        for (let i = 0; i < 20; i++) {
          const m: MixedProblem = MixedGen.generate(spec, rng);
          expect(m.relaxed).assertTrue();
          expect((m.a + m.b) * m.c).assertEqual(m.answer);
        }
      })
    })
  })
}
