/**
 * M1 生成编排：单卷 / 多套同构卷（A/B/C/D，同参数不同种子——教师防抄袭场景）。
 *
 * 多套卷语义（计划 §4.1）：seeds = baseSeed .. baseSeed + setCount - 1；
 * 同参数 + 同种子 = 同卷（复现基石），换一套 = 换种子。
 */

import { Rng } from './Rng';
import { ProblemGen, ProblemSpec, Problem } from './ProblemGen';
import { Dedup, DedupResult, Collected } from './Dedup';
import { MixedGen, MixedSpec, MixedProblem } from './MixedGen';
import { FillBlank, BlankProblem } from './FillBlank';
import { GradePresets, PresetEntry } from './GradePresets';
import { SheetItem } from './SheetModel';

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

  /**
   * M2 多预设混编（计划 §4.1 题型多选）：勾选的题型轮转交织成一卷
   * （各题型交错分布，避免同题型扎堆）；同参数同种子 = 同卷。
   * entries 由调用方保证非空（表完整性见 GradePresets 测试）。
   */
  static buildMultiSheet(entries: PresetEntry[], seed: number, count: number): Collected<SheetItem> {
    const rng: Rng = new Rng(seed);
    const n: number = entries.length;
    let turn: number = 0;
    return Dedup.collectBy(count,
      () => {
        const entry: PresetEntry = entries[turn % n];
        turn++;
        return SheetGen.genItemForEntry(entry, rng);
      },
      (item: SheetItem) => item.key);
  }

  /** 单表目 → SheetItem（single/mixed/fill 三态分发；非法表项退化为 10 以内加法兜底）。 */
  private static genItemForEntry(entry: PresetEntry, rng: Rng): SheetItem {
    if (entry.kind === 'mixed') {
      const ms: MixedSpec | null = entry.mixed;
      if (ms !== null) {
        return SheetItem.fromMixed(MixedGen.generate(ms, rng));
      }
    } else if (entry.kind === 'fill') {
      const spec: ProblemSpec | null = GradePresets.resolveSpec(entry);
      if (spec !== null) {
        return SheetItem.fromBlank(FillBlank.fromProblem(ProblemGen.generate(spec, rng), rng, true));
      }
    } else {
      const spec: ProblemSpec | null = entry.spec;
      if (spec !== null) {
        const p: Problem = ProblemGen.generate(spec, rng);
        return SheetItem.fromProblem(p);
      }
    }
    return SheetItem.fromProblem(ProblemGen.generate(new ProblemSpec('add', 1, 10, true), rng));
  }
}
