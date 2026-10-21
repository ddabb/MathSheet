/**
 * M4 错题本持久化（计划 §6.4；M7 §5.3 作用域化）：MemberScope/mistakes.json 单文件物化存储。
 *
 * - commitSheet 幂等协议：先移除本卷旧引用（srcId === sheet.id）再入库当前错题，
 *   重复批改/改判不重复堆叠（跨卷同表达式合并为一条，wrongCount 累计严重度）；
 * - 容量防护：MAX_MISTAKES 上限淘汰最早标记；
 * - 全同步 I/O（单文件 < 200KB）。
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { MemberScope } from './ProfileCodec';
import { MistakeEntry, MistakeCodec } from './MistakeCodec';
import { StoredSheet } from './SheetCodec';

export class MistakeStore {
  /** 错题容量上限（超出淘汰最早标记）。 */
  static MAX_MISTAKES: number = 1000;

  private static file(scope: MemberScope): string {
    return scope.baseDir + '/mistakes.json';
  }

  private static readText(path: string): string {
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = fs.statSync(file.fd);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } finally {
      fs.closeSync(file);
    }
  }

  static load(scope: MemberScope): MistakeEntry[] {
    try {
      const f: string = MistakeStore.file(scope);
      if (!fs.accessSync(f)) {
        return [];
      }
      return MistakeCodec.fromJson(MistakeStore.readText(f));
    } catch (e) {
      return [];
    }
  }

  private static saveAll(scope: MemberScope, entries: MistakeEntry[]): void {
    let list: MistakeEntry[] = entries;
    while (list.length > MistakeStore.MAX_MISTAKES) {
      let oldestIdx: number = 0;
      for (let i: number = 1; i < list.length; i++) {
        if (list[i].lastWrongAt < list[oldestIdx].lastWrongAt) {
          oldestIdx = i;
        }
      }
      list = list.filter((e: MistakeEntry, i: number) => i !== oldestIdx);
    }
    try {
      const file: fs.File = fs.openSync(MistakeStore.file(scope),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, MistakeCodec.toJson(list));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      // 写失败不阻断批改主流程
    }
  }

  /**
   * 卷批改完成 → 错题入本（计划 §4.1：完成即自动汇总）。
   * 幂等：先移除 srcId === sheet.id 的旧条目，再入库当前错题；
   * 跨卷同表达式（key 相同）合并：wrongCount + 1、来源更新为本卷。
   * @returns 本次入库的错题条数
   */
  static commitSheet(scope: MemberScope, sheet: StoredSheet): number {
    const kept: MistakeEntry[] = [];
    for (const e of MistakeStore.load(scope)) {
      if (e.srcId !== sheet.id) {
        kept.push(e);
      }
    }
    let wrong: number = 0;
    const now: number = Date.now();
    for (let i: number = 0; i < sheet.items.length && i < sheet.marks.length; i++) {
      if (sheet.marks[i] !== 2) {
        continue;
      }
      wrong++;
      const item = sheet.items[i];
      let merged: boolean = false;
      for (let k: number = 0; k < kept.length; k++) {
        if (kept[k].key === item.key) {
          const e: MistakeEntry = kept[k];
          kept[k] = new MistakeEntry(e.key, item.q, item.a, item.p,
            sheet.id, sheet.title, e.wrongCount + 1, now);
          merged = true;
          break;
        }
      }
      if (!merged) {
        kept.push(new MistakeEntry(item.key, item.q, item.a, item.p,
          sheet.id, sheet.title, 1, now));
      }
    }
    MistakeStore.saveAll(scope, kept);
    return wrong;
  }

  /** 清空错题本（破坏性操作，调用方需二次确认）。 */
  static clearAll(scope: MemberScope): void {
    try {
      const f: string = MistakeStore.file(scope);
      if (fs.accessSync(f)) {
        fs.unlinkSync(f);
      }
    } catch (e) {
      // 见上
    }
  }
}
