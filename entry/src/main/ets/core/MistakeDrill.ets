/**
 * M4 错题重练卷（计划 §4.1 / §6.4 核心差异化）：
 * 错题原题 + 按 {spec, 新种子} 生成的同类新题按 1:2 混编——
 * 同类 = 物化题目携带的 presetId（如 100 以内加法·进阶，含进位约束），
 * 新题与原题及彼此去重（可行域不足时少补，不强行凑数）。
 */

import { Rng } from './Rng';
import { SheetGen } from './SheetGen';
import { MistakeEntry } from './MistakeCodec';
import { StoredItem, StoredSheet } from './SheetCodec';

export class MistakeDrill {
  /** 单条错题新题补充尝试上限（可行域不足时放弃补充）。 */
  static readonly NEW_TRY_LIMIT: number = 48;

  /**
   * 重练卷题目：逐条错题 → [原题, 新题, 新题] 混编（同类新题数不足时顺延）。
   * @param mistakes 错题列表（展示顺序即混编顺序）
   * @param seed 新题随机种子（同错题同种子 = 同重练卷）
   * @param maxItems 题数上限（生成器表单上限 200）
   */
  static buildItems(mistakes: MistakeEntry[], seed: number, maxItems: number): StoredItem[] {
    const rng: Rng = new Rng(seed);
    const seen: Set<string> = new Set<string>();
    const out: StoredItem[] = [];
    for (const m of mistakes) {
      if (out.length >= maxItems) {
        break;
      }
      if (!seen.has(m.key)) {
        seen.add(m.key);
        out.push(new StoredItem(m.q, m.a, m.key, m.p));
      }
      for (let k = 0; k < 2; k++) {
        if (out.length >= maxItems) {
          break;
        }
        let tries: number = 0;
        while (tries < MistakeDrill.NEW_TRY_LIMIT) {
          tries++;
          const item = SheetGen.itemForPresetId(m.p, rng);
          if (item === null) {
            break;
          }
          if (!seen.has(item.key)) {
            seen.add(item.key);
            out.push(new StoredItem(item.questionText, item.answerText, item.key, m.p));
            break;
          }
        }
      }
    }
    return out;
  }

  /**
   * 组装重练卷 StoredSheet（供卷库物化 + 预览/批改复用）。
   * id 由调用方（SheetStore）分配；marks 全 0 待批改。
   */
  static buildSheet(id: string, createdAt: number, title: string,
                    mistakes: MistakeEntry[], seed: number, maxItems: number): StoredSheet | null {
    const items: StoredItem[] = MistakeDrill.buildItems(mistakes, seed, maxItems);
    if (items.length === 0) {
      return null;
    }
    const typeIds: string[] = [];
    for (const it of items) {
      if (it.p !== '' && typeIds.indexOf(it.p) < 0) {
        typeIds.push(it.p);
      }
    }
    const marks: number[] = [];
    for (let i = 0; i < items.length; i++) {
      marks.push(0);
    }
    return new StoredSheet(id, createdAt, title, 0, typeIds, items.length, 3,
      true, true, seed, items, marks);
  }
}
