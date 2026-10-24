/**
 * 一键重练共享流（批改小结 / 错题本两处入口复用）：
 * 错题 1:2 混编（MistakeDrill）→ 物化入库（SheetStore）→ 调用方提示并跳预览。
 */

import { MistakeEntry } from '../core/MistakeCodec';
import { MistakeDrill } from '../core/MistakeDrill';
import { StoredSheet } from '../core/SheetCodec';
import { SheetStore } from '../core/SheetStore';
import { MemberScope } from '../core/ProfileCodec';

export class DrillFlow {
  /** 重练卷题数上限（与生成器表单上限一致）。 */
  static readonly MAX_ITEMS: number = 200;

  /**
   * 构建并入库重练卷（新种子，同错题集每次重练题目不同）。
   * @returns 新卷（null = 无错题或构建失败，调用方静默返回）
   */
  static buildDrillSheet(scope: MemberScope, mistakes: MistakeEntry[],
                         title: string): StoredSheet | null {
    if (mistakes.length === 0) {
      return null;
    }
    const id: string = SheetStore.newId();
    const sheet: StoredSheet | null = MistakeDrill.buildSheet(id, Date.now(), title,
      mistakes, Math.floor(Math.random() * 2147483647), DrillFlow.MAX_ITEMS);
    if (sheet === null) {
      return null;
    }
    SheetStore.saveSheet(scope, sheet);
    return sheet;
  }
}
