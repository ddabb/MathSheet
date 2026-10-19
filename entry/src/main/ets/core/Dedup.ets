/**
 * M0 核心③：表达式规范化去重（计划 §4.1 去重 + §6.2 可行域不足放行协议）。
 *
 * - 规范化键：加/乘按交换律归一（小操作数在前），减/除保序；
 * - 同卷不重题；可行域不足（如 3 的口诀仅 9 题）时单题尝试达上限放行，
 *   放行数随结果返回，调用方 toast 说明（计划 §5.2 反馈约定）。
 */

import { Problem } from './ProblemGen';

/** 去重结果（duplicates 语义随入口：collect = 放行重复数；unique = 剔除重复数）。 */
export class DedupResult {
  problems: Problem[];
  duplicates: number;

  constructor(problems: Problem[], duplicates: number) {
    this.problems = problems;
    this.duplicates = duplicates;
  }
}

/** 泛化收集结果（M1 混合/填空等非 Problem 题型；duplicates = 放行重复数）。 */
export class Collected<T> {
  items: T[];
  duplicates: number;

  constructor(items: T[], duplicates: number) {
    this.items = items;
    this.duplicates = duplicates;
  }
}

export class Dedup {
  /** 单题去重尝试上限（达上限放行并计入 duplicates）。 */
  static readonly ATTEMPT_LIMIT: number = 64;

  /** 规范化键（委托 Problem.key，保持单一事实源）。 */
  static keyOf(p: Problem): string {
    return p.key();
  }

  /**
   * 生成期去重：用 gen 凑 count 题，同卷不重题；
   * 单题尝试达 ATTEMPT_LIMIT 仍重复（可行域不足）→ 放行并计入 duplicates。
   */
  static collect(count: number, gen: () => Problem): DedupResult {
    const seen: Set<string> = new Set<string>();
    const problems: Problem[] = [];
    let released: number = 0;
    for (let n = 0; n < count; n++) {
      let p: Problem = gen();
      let attempts: number = 1;
      while (seen.has(Dedup.keyOf(p)) && attempts < Dedup.ATTEMPT_LIMIT) {
        p = gen();
        attempts++;
      }
      const key: string = Dedup.keyOf(p);
      if (seen.has(key)) {
        released++;
      } else {
        seen.add(key);
      }
      problems.push(p);
    }
    return new DedupResult(problems, released);
  }

  /** 列表去重（保序）：已生成列表的重复剔除，duplicates = 剔除数。 */
  static unique(problems: Problem[]): DedupResult {
    const seen: Set<string> = new Set<string>();
    const kept: Problem[] = [];
    let dropped: number = 0;
    for (const p of problems) {
      const key: string = Dedup.keyOf(p);
      if (seen.has(key)) {
        dropped++;
      } else {
        seen.add(key);
        kept.push(p);
      }
    }
    return new DedupResult(kept, dropped);
  }

  /**
   * 泛化生成期去重（M1 混合/填空等非 Problem 题型）：
   * 语义同 collect，键由调用方 keyOf 给出（题型自带 key() 时传 (x) => x.key()）。
   */
  static collectBy<T>(count: number, gen: () => T, keyOf: (item: T) => string): Collected<T> {
    const seen: Set<string> = new Set<string>();
    const items: T[] = [];
    let released: number = 0;
    for (let n = 0; n < count; n++) {
      let item: T = gen();
      let attempts: number = 1;
      while (seen.has(keyOf(item)) && attempts < Dedup.ATTEMPT_LIMIT) {
        item = gen();
        attempts++;
      }
      const key: string = keyOf(item);
      if (seen.has(key)) {
        released++;
      } else {
        seen.add(key);
      }
      items.push(item);
    }
    return new Collected<T>(items, released);
  }
}
