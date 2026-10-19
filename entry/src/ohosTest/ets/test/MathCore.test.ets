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
import { Dedup } from '../../../main/ets/core/Dedup';

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
  })
}
