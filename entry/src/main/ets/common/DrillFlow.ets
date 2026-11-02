/**
 * 一键重练共享流（批改小结 / 错题本 / 在线作答结果页三处入口复用）：
 * 错题按模式混编（MistakeDrill，1.0.1 M1 比例可调）→ 物化入库（SheetStore）
 * → 标题标注来源日期（最新错题时间，来源可追溯）→ 调用方提示并跳预览。
 */

import { MistakeEntry } from '../core/MistakeCodec';
import { MistakeDrill, DRILL_MODE_MIXED } from '../core/MistakeDrill';
import { StoredSheet } from '../core/SheetCodec';
import { SheetStore } from '../core/SheetStore';
import { MemberScope } from '../core/ProfileCodec';

export class DrillFlow {
  /** 重练卷题数上限（与生成器表单上限一致）。 */
  static readonly MAX_ITEMS: number = 200;

  /**
   * 构建并入库重练卷（新种子，同错题集每次重练题目不同）。
   * @param mode 'only' 仅错题 / 'mixed' 错题+同类新题（默认）
   * @param ratio 混编比例 1|2|3（仅 mixed 生效，默认 2）
   * @returns 新卷（null = 无错题或构建失败，调用方静默返回）
   */
  static buildDrillSheet(scope: MemberScope, mistakes: MistakeEntry[],
                         title: string, mode: string = DRILL_MODE_MIXED,
                         ratio: number = 2): StoredSheet | null {
    if (mistakes.length === 0) {
      return null;
    }
    const id: string = SheetStore.newId();
    const sheet: StoredSheet | null = MistakeDrill.buildSheet(id, Date.now(),
      DrillFlow.titleWithSourceDate(title, mistakes),
      mistakes, Math.floor(Math.random() * 2147483647), DrillFlow.MAX_ITEMS, mode, ratio);
    if (sheet === null) {
      return null;
    }
    SheetStore.saveSheet(scope, sheet);
    return sheet;
  }

  /**
   * 重练卷标题追加来源日期（1.0.1 M1 来源可追溯）：
   * 取错题最新 lastWrongAt 的 MM-DD；无时间信息时原样返回。
   */
  static titleWithSourceDate(title: string, mistakes: MistakeEntry[]): string {
    let latest: number = 0;
    for (const m of mistakes) {
      if (m.lastWrongAt > latest) {
        latest = m.lastWrongAt;
      }
    }
    if (latest <= 0) {
      return title;
    }
    const d: Date = new Date(latest);
    const mo: number = d.getMonth() + 1;
    const da: number = d.getDate();
    const moS: string = mo < 10 ? `0${mo}` : `${mo}`;
    const daS: string = da < 10 ? `0${da}` : `${da}`;
    return `${title} ${moS}-${daS}`;
  }
}
