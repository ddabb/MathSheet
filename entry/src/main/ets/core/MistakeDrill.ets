/**
 * M4 错题重练卷（计划 §4.1 / §6.4 核心差异化；1.0.1 M1 模式与比例可调）：
 * 「仅错题」模式只收原题；「错题+同类」模式按 1:1 / 1:2 / 1:3 混编——
 * 同类 = 物化题目携带的 presetId（如 100 以内加法·进阶，含进位约束），
 * 新题与原题及彼此去重（可行域不足时少补，不强行凑数）。
 */

import { Rng } from './Rng';
import { SheetGen } from './SheetGen';
import { MistakeEntry } from './MistakeCodec';
import { StoredItem, StoredSheet } from './SheetCodec';

/** 重练模式常量：'only' 仅错题 / 'mixed' 错题+同类新题。 */
export const DRILL_MODE_ONLY: string = 'only';
export const DRILL_MODE_MIXED: string = 'mixed';

export class MistakeDrill {
  /** 单条错题新题补充尝试上限（可行域不足时放弃补充）。 */
  static readonly NEW_TRY_LIMIT: number = 48;

  /**
   * 重练卷题目：逐条错题 → [原题, 新题 × ratio] 混编（同类新题数不足时顺延）。
   * @param mistakes 错题列表（展示顺序即混编顺序）
   * @param seed 新题随机种子（同错题同种子 = 同重练卷）
   * @param maxItems 题数上限（生成器表单上限 200）
   * @param mode 'only' 仅错题 / 'mixed' 错题+同类新题（默认，历史行为）
   * @param ratio 混编比例（1:1 / 1:2 / 1:3，仅 mixed 生效，默认 2）
   */
  static buildItems(mistakes: MistakeEntry[], seed: number, maxItems: number,
                    mode: string = DRILL_MODE_MIXED, ratio: number = 2): StoredItem[] {
    const rng: Rng = new Rng(seed);
    const seen: Set<string> = new Set<string>();
    const out: StoredItem[] = [];
    const newPerMistake: number = mode === DRILL_MODE_ONLY
      ? 0 : Math.max(1, Math.min(3, Math.round(ratio)));
    for (const m of mistakes) {
      if (out.length >= maxItems) {
        break;
      }
      if (!seen.has(m.key)) {
        seen.add(m.key);
        out.push(new StoredItem(m.q, m.a, m.key, m.p));
      }
      for (let k = 0; k < newPerMistake; k++) {
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
                    mistakes: MistakeEntry[], seed: number, maxItems: number,
                    mode: string = DRILL_MODE_MIXED, ratio: number = 2): StoredSheet | null {
    const items: StoredItem[] = MistakeDrill.buildItems(mistakes, seed, maxItems, mode, ratio);
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
