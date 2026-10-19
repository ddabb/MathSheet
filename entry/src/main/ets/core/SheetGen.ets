/**
 * M1 生成编排：单卷 / 多套同构卷（A/B/C/D，同参数不同种子——教师防抄袭场景）。
 *
 * 多套卷语义（计划 §4.1）：seeds = baseSeed .. baseSeed + setCount - 1；
 * 同参数 + 同种子 = 同卷（复现基石），换一套 = 换种子。
 */

import { Rng } from './Rng';
import { ProblemGen, ProblemSpec } from './ProblemGen';
import { Dedup, DedupResult, Collected } from './Dedup';
import { MixedGen, MixedSpec, MixedProblem } from './MixedGen';
import { FillBlank, BlankProblem } from './FillBlank';

export class SheetGen {
  /** 单卷：同种子复现的基石。 */
  static buildSheet(spec: ProblemSpec, seed: number, count: number): DedupResult {
    const rng: Rng = new Rng(seed);
    return Dedup.collect(count, () => ProblemGen.generate(spec, rng));
  }

  /** 多套同构卷（A/B/C/D）：同参数不同种子。 */
  static buildSets(spec: ProblemSpec, baseSeed: number, count: number, setCount: number): DedupResult[] {
    const sets: DedupResult[] = [];
    for (let i = 0; i < setCount; i++) {
      sets.push(SheetGen.buildSheet(spec, baseSeed + i, count));
    }
    return sets;
  }

  /** 混合卷（连加连减/乘加乘减/带括号）。 */
  static buildSheetMixed(spec: MixedSpec, seed: number, count: number): Collected<MixedProblem> {
    const rng: Rng = new Rng(seed);
    return Dedup.collectBy(count, () => MixedGen.generate(spec, rng), (m: MixedProblem) => m.key());
  }

  /** 填空卷（按基础单步规格生成后挖空）。 */
  static buildSheetBlanks(spec: ProblemSpec, seed: number, count: number): Collected<BlankProblem> {
    const rng: Rng = new Rng(seed);
    return Dedup.collectBy(count,
      () => FillBlank.fromProblem(ProblemGen.generate(spec, rng), rng, true),
      (b: BlankProblem) => b.key());
  }
}
