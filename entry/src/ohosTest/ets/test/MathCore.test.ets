/**
 * M0 核心引擎测试套件（mathCoreTest）——性质测试为核心（计划 §8）：
 * 单题断言无意义，批量性质断言才是引擎正确性证明：
 *   - 每题型 × 难度 1000 次批量断言（结果范围/非负/整除/进退位约束全量成立）；
 *   - 种子复现（同 seed 两跑逐题相等）；
 *   - 去重（可行域充足零放行 + 可行域不足放行协议 + 交换律归一 + 列表保序）；
 *   - Rng 分布抽查（和值直方图粗校验防偏斜）。
 *
 * 运行协议（模拟器 class 过滤定向跑，勿全量跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class mathCoreTest -s timeout 15000
 * class 过滤模式下 delegator.getAppContext() 为壳 context，本套件为纯逻辑直测，不依赖 context。
 */
import { describe, it, expect } from '@ohos/hypium';
import { Rng } from '../../../main/ets/core/Rng';
import { ProblemGen, ProblemSpec, Problem } from '../../../main/ets/core/ProblemGen';
import { Dedup, DedupResult, Collected } from '../../../main/ets/core/Dedup';
import { MixedGen, MixedSpec, MixedProblem } from '../../../main/ets/core/MixedGen';
import { FillBlank, BlankProblem } from '../../../main/ets/core/FillBlank';
import { SheetGen } from '../../../main/ets/core/SheetGen';
import { GradePresets, PresetEntry } from '../../../main/ets/core/GradePresets';

const BATCH: number = 1000;

/** 单题硬约束全量断言；弱约束在未放宽（relaxed=false）时断言。 */
function assertProblem(p: Problem, spec: ProblemSpec): void {
  const lo: number = Math.min(spec.min, spec.max);
  const hi: number = Math.max(spec.min, spec.max);
  if (p.op === 'add') {
    expect(p.a + p.b).assertEqual(p.answer);
    expect(p.answer >= lo && p.answer <= hi).assertTrue();
    expect(p.a >= 0 && p.a <= hi).assertTrue();
    expect(p.b >= 0 && p.b <= hi).assertTrue();
    if (spec.noCarry && !p.relaxed) {
      expect((p.a % 10) + (p.b % 10) < 10).assertTrue();
    }
  } else if (p.op === 'sub') {
    expect(p.a - p.b).assertEqual(p.answer);
    expect(p.answer >= 0).assertTrue();
    expect(p.a >= lo && p.a <= hi).assertTrue();
    expect(p.b >= 0 && p.b <= p.a).assertTrue();
    if (spec.noBorrow && !p.relaxed) {
      expect((p.a % 10) >= (p.b % 10)).assertTrue();
    }
  } else if (p.op === 'mul') {
    expect(p.a * p.b).assertEqual(p.answer);
    if (spec.tableMul) {
      expect(p.a >= 2 && p.a <= 9).assertTrue();
      expect(p.b >= 2 && p.b <= 9).assertTrue();
    } else if (hi >= 10) {
      expect(p.b >= 2 && p.b <= 9).assertTrue();
      expect(p.a >= Math.max(10, lo) && p.a <= hi).assertTrue();
    } else {
      expect(p.a >= Math.max(2, lo) && p.a <= Math.min(9, hi)).assertTrue();
      expect(p.b >= Math.max(2, lo) && p.b <= Math.min(9, hi)).assertTrue();
    }
  } else {
    expect(p.a % p.b).assertEqual(0);
    expect(p.a / p.b).assertEqual(p.answer);
    expect(p.a <= hi).assertTrue();
    expect(p.b >= 2 && p.b <= Math.max(2, Math.min(9, spec.divisorMax))).assertTrue();
    expect(p.answer >= 1).assertTrue();
    expect(p.a >= p.b).assertTrue();
  }
}

/** 混合题性质断言：恒等式/内层非负/外层项界/结果区间（未放宽时）/括号文本形态。 */
function assertMixed(m: MixedProblem, spec: MixedSpec): void {
  const lo: number = Math.min(spec.min, spec.max);
  const hi: number = Math.max(spec.min, spec.max);
  const inner: number = spec.op1 === 'add' ? m.a + m.b : spec.op1 === 'sub' ? m.a - m.b : m.a * m.b;
  const expected: number = spec.op2 === 'add' ? inner + m.c : spec.op2 === 'sub' ? inner - m.c : inner * m.c;
  expect(m.answer).assertEqual(expected);
  if (spec.op1 === 'add') {
    expect(m.a >= 0 && m.b >= 0).assertTrue();
    expect(m.a + m.b >= Math.min(spec.innerMin, spec.innerMax)).assertTrue();
    expect(m.a + m.b <= Math.max(spec.innerMin, spec.innerMax)).assertTrue();
  } else if (spec.op1 === 'sub') {
    expect(m.a - m.b >= 0).assertTrue();
    expect(m.a >= Math.min(spec.innerMin, spec.innerMax)).assertTrue();
    expect(m.a <= Math.max(spec.innerMin, spec.innerMax)).assertTrue();
    expect(m.b >= 0 && m.b <= m.a).assertTrue();
  } else {
    expect(m.a >= 2 && m.a <= spec.factorMax).assertTrue();
    expect(m.b >= 2 && m.b <= spec.factorMax).assertTrue();
  }
  if (spec.op2 === 'add') {
    expect(m.c >= 0 && m.c <= spec.cMax).assertTrue();
  } else if (spec.op2 === 'sub') {
    expect(m.c >= 0 && m.c <= inner).assertTrue();
    expect(m.answer >= 0).assertTrue();
  } else {
    expect(m.c >= 2 && m.c <= spec.cFactorMax).assertTrue();
  }
  if (!m.relaxed) {
    expect(m.answer >= lo && m.answer <= hi).assertTrue();
  }
  if (spec.bracket) {
    expect(m.text.indexOf('(')).assertEqual(0);
    expect(m.text.indexOf(')') > 0).assertTrue();
  } else {
    expect(m.text.indexOf('(') < 0).assertTrue();
  }
}

/** 填空题性质断言：挖位/值/文本三态 + 还原恒等式（□ 换回值 = 完整式）。 */
function assertBlank(b: BlankProblem, base: Problem): void {
  const sym: string = ProblemGen.keySymbolOf(base.op);
  const full: string = base.a + sym + base.b + '=' + base.answer;
  if (b.blankPos === 'a') {
    expect(b.blankValue).assertEqual(base.a);
    expect(b.text.indexOf('\u25a1')).assertEqual(0);
  } else if (b.blankPos === 'b') {
    expect(b.blankValue).assertEqual(base.b);
    expect(b.text.indexOf('\u25a1') > 0).assertTrue();
  } else {
    expect(b.blankValue).assertEqual(base.answer);
    expect(b.text.charAt(b.text.length - 1)).assertEqual('\u25a1');
  }
  const restored: string = b.text.replace('\u25a1', String(b.blankValue));
  expect(restored).assertEqual(full);
}

export default function mathCoreTest() {
  describe('mathCoreTest', () => {
    describe('Rng', () => {
      it('同种子同序列（前 100 项逐项相等）', 0, () => {
        const r1: Rng = new Rng(20261019);
        const r2: Rng = new Rng(20261019);
        for (let i = 0; i < 100; i++) {
          expect(r1.next()).assertEqual(r2.next());
        }
      })

      it('不同种子序列不同（100 项全异）', 0, () => {
        const r1: Rng = new Rng(1);
        const r2: Rng = new Rng(2);
        let diff: number = 0;
        for (let i = 0; i < 100; i++) {
          if (r1.next() !== r2.next()) {
            diff++;
          }
        }
        expect(diff).assertEqual(100);
      })

      it('nextFloat 落 [0,1) 且万次均值 ≈ 0.5', 0, () => {
        const r: Rng = new Rng(42);
        let sum: number = 0;
        for (let i = 0; i < 10000; i++) {
          const f: number = r.nextFloat();
          expect(f >= 0 && f < 1).assertTrue();
          sum += f;
        }
        const mean: number = sum / 10000;
        expect(mean > 0.47 && mean < 0.53).assertTrue();
      })

      it('nextInt 落 [min,max) 且两端边界可达', 0, () => {
        const r: Rng = new Rng(7);
        let hitMin: boolean = false;
        let hitMax: boolean = false;
        for (let i = 0; i < BATCH; i++) {
          const v: number = r.nextInt(3, 9);
          expect(v >= 3 && v < 9).assertTrue();
          if (v === 3) {
            hitMin = true;
          }
          if (v === 8) {
            hitMax = true;
          }
        }
        expect(hitMin).assertTrue();
        expect(hitMax).assertTrue();
      })
    })

    describe('ProblemGen', () => {
      it('加法 1000 次性质（和/操作数受控 + 不进位弱约束）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 10, 99, true);
        const rng: Rng = new Rng(101);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genAdd(spec, rng), spec);
        }
      })

      it('加法 1000 次性质（20 以内含进位）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 1, 20, false);
        const rng: Rng = new Rng(102);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genAdd(spec, rng), spec);
        }
      })

      it('减法 1000 次性质（结果非负 + 不退位弱约束）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('sub', 20, 99, false, true);
        const rng: Rng = new Rng(103);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genSub(spec, rng), spec);
        }
      })

      it('减法 1000 次性质（100 以内含退位）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('sub', 1, 100, false, false);
        const rng: Rng = new Rng(104);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genSub(spec, rng), spec);
        }
      })

      it('表内乘法 1000 次性质（两因子 ∈ [2,9]）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('mul', 2, 9, false, false, true);
        const rng: Rng = new Rng(105);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genMul(spec, rng), spec);
        }
      })

      it('两位数×一位数 1000 次性质', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('mul', 10, 99, false, false, false);
        const rng: Rng = new Rng(106);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genMul(spec, rng), spec);
        }
      })

      it('表内除法 1000 次性质（整除先天保证）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('div', 2, 81, false, false, false, 9);
        const rng: Rng = new Rng(107);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genDiv(spec, rng), spec);
        }
      })

      it('100 以内除法 1000 次性质（被除数 ≤ 100）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('div', 10, 100, false, false, false, 9);
        const rng: Rng = new Rng(108);
        for (let i = 0; i < BATCH; i++) {
          assertProblem(ProblemGen.genDiv(spec, rng), spec);
        }
      })

      it('分发入口与专用入口逐题相等（每题型 1000 次）', 0, () => {
        const cases: ProblemSpec[] = [
          new ProblemSpec('add', 5, 50, true),
          new ProblemSpec('sub', 5, 50, false, true),
          new ProblemSpec('mul', 2, 9, false, false, true),
          new ProblemSpec('mul', 10, 99, false, false, false),
          new ProblemSpec('div', 2, 81, false, false, false, 9)
        ];
        for (const spec of cases) {
          const rngA: Rng = new Rng(109);
          const rngB: Rng = new Rng(109);
          for (let i = 0; i < BATCH; i++) {
            const p1: Problem = ProblemGen.generate(spec, rngA);
            let p2: Problem;
            if (spec.op === 'add') {
              p2 = ProblemGen.genAdd(spec, rngB);
            } else if (spec.op === 'sub') {
              p2 = ProblemGen.genSub(spec, rngB);
            } else if (spec.op === 'mul') {
              p2 = ProblemGen.genMul(spec, rngB);
            } else {
              p2 = ProblemGen.genDiv(spec, rngB);
            }
            expect(Dedup.keyOf(p1)).assertEqual(Dedup.keyOf(p2));
            expect(p1.relaxed).assertEqual(p2.relaxed);
          }
        }
      })

      it('分布抽查：和值直方图无偏斜（1-20 每桶 ≥ 100/10000）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 1, 20, false);
        const rng: Rng = new Rng(202);
        const bins: number[] = new Array(21).fill(0);
        for (let i = 0; i < 10000; i++) {
          const p: Problem = ProblemGen.genAdd(spec, rng);
          bins[p.answer]++;
        }
        for (let s = 1; s <= 20; s++) {
          expect(bins[s] >= 100).assertTrue();
        }
      })
    })

    describe('Dedup', () => {
      it('交换律归一：加/乘保序归一，减/除保序', 0, () => {
        expect(Dedup.keyOf(new Problem(3, 7, 'add', 10)))
          .assertEqual(Dedup.keyOf(new Problem(7, 3, 'add', 10)));
        expect(Dedup.keyOf(new Problem(3, 7, 'mul', 21)))
          .assertEqual(Dedup.keyOf(new Problem(7, 3, 'mul', 21)));
        expect(Dedup.keyOf(new Problem(10, 3, 'sub', 7)) !== Dedup.keyOf(new Problem(3, 10, 'sub', -7)))
          .assertTrue();
        expect(Dedup.keyOf(new Problem(12, 3, 'div', 4)) !== Dedup.keyOf(new Problem(3, 12, 'div', 0)))
          .assertTrue();
      })

      it('collect 可行域充足：50 题零放行、键全唯一、性质全成立', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 10, 99, false);
        const rng: Rng = new Rng(303);
        const res: DedupResult = Dedup.collect(50, () => ProblemGen.genAdd(spec, rng));
        expect(res.problems.length).assertEqual(50);
        expect(res.duplicates).assertEqual(0);
        const keys: Set<string> = new Set<string>();
        for (const p of res.problems) {
          keys.add(Dedup.keyOf(p));
          assertProblem(p, spec);
        }
        expect(keys.size).assertEqual(50);
      })

      it('collect 可行域不足：表内乘法 100 题必有放行（唯一键 ≤ 64）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('mul', 2, 9, false, false, true);
        const rng: Rng = new Rng(404);
        const res: DedupResult = Dedup.collect(100, () => ProblemGen.genMul(spec, rng));
        expect(res.problems.length).assertEqual(100);
        expect(res.duplicates > 0).assertTrue();
        const keys: Set<string> = new Set<string>();
        for (const p of res.problems) {
          keys.add(Dedup.keyOf(p));
          assertProblem(p, spec);
        }
        expect(keys.size <= 64).assertTrue();
      })

      it('unique 列表去重保序（交换律同键计重）', 0, () => {
        const list: Problem[] = [
          new Problem(1, 2, 'add', 3),
          new Problem(2, 1, 'add', 3),
          new Problem(5, 2, 'sub', 3),
          new Problem(5, 2, 'sub', 3),
          new Problem(6, 3, 'div', 2)
        ];
        const res: DedupResult = Dedup.unique(list);
        expect(res.problems.length).assertEqual(3);
        expect(res.duplicates).assertEqual(2);
        expect(Dedup.keyOf(res.problems[0])).assertEqual('1+2');
        expect(Dedup.keyOf(res.problems[1])).assertEqual('5-2');
        expect(Dedup.keyOf(res.problems[2])).assertEqual('6\u00f73');
      })

      it('种子复现：同种子同参数 → 同卷逐题相等', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 10, 99, true);
        const r1: Rng = new Rng(505);
        const r2: Rng = new Rng(505);
        const s1: DedupResult = Dedup.collect(30, () => ProblemGen.genAdd(spec, r1));
        const s2: DedupResult = Dedup.collect(30, () => ProblemGen.genAdd(spec, r2));
        expect(s1.duplicates).assertEqual(s2.duplicates);
        for (let i = 0; i < 30; i++) {
          expect(Dedup.keyOf(s1.problems[i])).assertEqual(Dedup.keyOf(s2.problems[i]));
        }
      })

      it('换一批：新种子 → 卷面不同（前 30 题键序列不全同）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 10, 99, false);
        const r1: Rng = new Rng(606);
        const r2: Rng = new Rng(607);
        const s1: DedupResult = Dedup.collect(30, () => ProblemGen.genAdd(spec, r1));
        const s2: DedupResult = Dedup.collect(30, () => ProblemGen.genAdd(spec, r2));
        let same: number = 0;
        for (let i = 0; i < 30; i++) {
          if (Dedup.keyOf(s1.problems[i]) === Dedup.keyOf(s2.problems[i])) {
            same++;
          }
        }
        expect(same < 30).assertTrue();
      })
    })

    describe('MixedGen', () => {
      it('连加 1000 次性质（和受控 + 恒等式 + 无括号文本）', 0, () => {
        const spec: MixedSpec = new MixedSpec('add', 'add', false, 2, 30, 1, 10, 10);
        const rng: Rng = new Rng(201);
        for (let i = 0; i < BATCH; i++) {
          assertMixed(MixedGen.generate(spec, rng), spec);
        }
      })

      it('连减 1000 次性质（内层非负 + 结果非负硬约束）', 0, () => {
        const spec: MixedSpec = new MixedSpec('add', 'sub', false, 1, 20, 1, 10, 10);
        const rng: Rng = new Rng(202);
        for (let i = 0; i < BATCH; i++) {
          assertMixed(MixedGen.generate(spec, rng), spec);
        }
      })

      it('乘加 1000 次性质（表内因子 + 加减项界）', 0, () => {
        const spec: MixedSpec = new MixedSpec('mul', 'add', false, 2, 90, 2, 9, 9, 9, 9);
        const rng: Rng = new Rng(203);
        for (let i = 0; i < BATCH; i++) {
          assertMixed(MixedGen.generate(spec, rng), spec);
        }
      })

      it('乘减 1000 次性质（结果非负硬约束）', 0, () => {
        const spec: MixedSpec = new MixedSpec('mul', 'sub', false, 2, 90, 2, 9, 9, 9, 9);
        const rng: Rng = new Rng(204);
        for (let i = 0; i < BATCH; i++) {
          assertMixed(MixedGen.generate(spec, rng), spec);
        }
      })

      it('带括号 (a+b)×c 1000 次性质（括号文本 + 因子界）', 0, () => {
        const spec: MixedSpec = new MixedSpec('add', 'mul', true, 20, 400, 10, 99, 20, 9);
        const rng: Rng = new Rng(205);
        for (let i = 0; i < BATCH; i++) {
          assertMixed(MixedGen.generate(spec, rng), spec);
        }
      })

      it('带括号 (a−b)×c 1000 次性质（内层非负）', 0, () => {
        const spec: MixedSpec = new MixedSpec('sub', 'mul', true, 10, 400, 20, 99, 20, 9);
        const rng: Rng = new Rng(206);
        for (let i = 0; i < BATCH; i++) {
          assertMixed(MixedGen.generate(spec, rng), spec);
        }
      })

      it('混合题同种子复现（100 题逐题相等）', 0, () => {
        const spec: MixedSpec = new MixedSpec('mul', 'add', false, 2, 90, 2, 9, 9, 9, 9);
        const r1: Rng = new Rng(207);
        const r2: Rng = new Rng(207);
        for (let i = 0; i < 100; i++) {
          expect(MixedGen.generate(spec, r1).key()).assertEqual(MixedGen.generate(spec, r2).key());
        }
      })
    })

    describe('FillBlank', () => {
      it('填空 1000 次性质（挖位/值/文本三态 + 还原恒等式）', 0, () => {
        const specs: ProblemSpec[] = [
          new ProblemSpec('add', 1, 20, false),
          new ProblemSpec('sub', 1, 100, false, false),
          new ProblemSpec('mul', 2, 9, false, false, true),
          new ProblemSpec('div', 2, 81, false, false, false, 9)
        ];
        for (const spec of specs) {
          const rng: Rng = new Rng(301);
          for (let i = 0; i < BATCH; i++) {
            const base: Problem = ProblemGen.generate(spec, rng);
            assertBlank(FillBlank.fromProblem(base, rng, true), base);
          }
        }
      })

      it('只挖操作数模式（allowAnswer=false，1000 次无答案挖空）', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 1, 20, false);
        const rng: Rng = new Rng(302);
        for (let i = 0; i < BATCH; i++) {
          const base: Problem = ProblemGen.generate(spec, rng);
          const b: BlankProblem = FillBlank.fromProblem(base, rng, false);
          expect(b.blankPos === 'a' || b.blankPos === 'b').assertTrue();
          assertBlank(b, base);
        }
      })
    })

    describe('GradePresets', () => {
      it('表完整性：id 唯一/年级合法/fillFrom 可解析/规格非空', 0, () => {
        const all: PresetEntry[] = GradePresets.ENTRIES;
        const ids: Set<string> = new Set<string>();
        for (const e of all) {
          expect(!ids.has(e.id)).assertTrue();
          ids.add(e.id);
          expect(e.grade >= 1 && e.grade <= 3).assertTrue();
          expect(e.labelZh.length > 0 && e.labelEn.length > 0).assertTrue();
          if (e.kind === 'mixed') {
            expect(e.mixed !== null).assertTrue();
          } else {
            expect(GradePresets.resolveSpec(e) !== null).assertTrue();
          }
          if (e.kind === 'fill') {
            const from: string | null = e.fillFrom;
            expect(from !== null).assertTrue();
            if (from !== null) {
              expect(GradePresets.byId(from) !== null).assertTrue();
            }
          }
        }
        expect(all.length >= 20).assertTrue();
        expect(GradePresets.forGrade(1).length >= 5).assertTrue();
        expect(GradePresets.forGrade(2).length >= 7).assertTrue();
        expect(GradePresets.forGrade(3).length >= 5).assertTrue();
      })

      it('全预设可生成：每条目 20 题 + 性质/文本断言', 0, () => {
        for (const e of GradePresets.ENTRIES) {
          if (e.kind === 'mixed') {
            const ms: MixedSpec | null = e.mixed;
            if (ms !== null) {
              const sheet: Collected<MixedProblem> = SheetGen.buildSheetMixed(ms, 777, 20);
              expect(sheet.items.length).assertEqual(20);
              for (const m of sheet.items) {
                assertMixed(m, ms);
              }
            }
          } else {
            const sp: ProblemSpec | null = GradePresets.resolveSpec(e);
            if (sp !== null) {
              if (e.kind === 'fill') {
                const sheet: Collected<BlankProblem> = SheetGen.buildSheetBlanks(sp, 777, 20);
                expect(sheet.items.length).assertEqual(20);
                for (const b of sheet.items) {
                  expect(b.text.indexOf('\u25a1') >= 0).assertTrue();
                }
              } else {
                const sheet: DedupResult = SheetGen.buildSheet(sp, 777, 20);
                expect(sheet.problems.length).assertEqual(20);
                for (const p of sheet.problems) {
                  assertProblem(p, sp);
                }
              }
            }
          }
        }
      })
    })

    describe('SheetGen', () => {
      it('多套同构卷 A/B/C/D：套间不同、套内零重复、同种子复现', 0, () => {
        const spec: ProblemSpec = new ProblemSpec('add', 10, 99, false);
        const sets: DedupResult[] = SheetGen.buildSets(spec, 9001, 20, 4);
        expect(sets.length).assertEqual(4);
        const firsts: Set<string> = new Set<string>();
        for (const s of sets) {
          expect(s.problems.length).assertEqual(20);
          expect(s.duplicates).assertEqual(0);
          const keys: Set<string> = new Set<string>();
          for (const p of s.problems) {
            keys.add(Dedup.keyOf(p));
            assertProblem(p, spec);
          }
          expect(keys.size).assertEqual(20);
          firsts.add(Dedup.keyOf(s.problems[0]));
        }
        expect(firsts.size).assertEqual(4);
        const again: DedupResult = SheetGen.buildSheet(spec, 9001, 20);
        for (let i = 0; i < 20; i++) {
          expect(Dedup.keyOf(again.problems[i])).assertEqual(Dedup.keyOf(sets[0].problems[i]));
        }
      })

      it('混合卷/填空卷：换种子卷面不同 + 同种子复现', 0, () => {
        const ms: MixedSpec = new MixedSpec('mul', 'add', false, 2, 90, 2, 9, 9, 9, 9);
        const s1: Collected<MixedProblem> = SheetGen.buildSheetMixed(ms, 9101, 20);
        const s2: Collected<MixedProblem> = SheetGen.buildSheetMixed(ms, 9102, 20);
        let same: number = 0;
        for (let i = 0; i < 20; i++) {
          if (s1.items[i].key() === s2.items[i].key()) {
            same++;
          }
        }
        expect(same < 20).assertTrue();
        const again: Collected<MixedProblem> = SheetGen.buildSheetMixed(ms, 9101, 20);
        for (let i = 0; i < 20; i++) {
          expect(again.items[i].key()).assertEqual(s1.items[i].key());
        }

        const sp: ProblemSpec = new ProblemSpec('add', 10, 99, false);
        const b1: Collected<BlankProblem> = SheetGen.buildSheetBlanks(sp, 9201, 20);
        const b2: Collected<BlankProblem> = SheetGen.buildSheetBlanks(sp, 9202, 20);
        let bSame: number = 0;
        for (let i = 0; i < 20; i++) {
          if (b1.items[i].key() === b2.items[i].key()) {
            bSame++;
          }
        }
        expect(bSame < 20).assertTrue();
      })
    })
  })
}
