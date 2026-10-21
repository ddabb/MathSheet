/**
 * M3 卷库持久化（计划 §6.4；M7 §5.3 作用域化）：MemberScope/sheetlib/ 物化存储。
 *
 * - index.json = 元数据索引（列表渲染只读索引，500 卷加载 < 100ms 预算）；
 * - {id}.json = 整卷物化（题目 + 批改状态，编解码见 SheetCodec）；
 * - 容量防护：MAX_SHEETS 上限淘汰最旧（文件与索引同步删除）；
 * - 全同步 I/O（单卷 ≤ 10KB，主线程安全）；脏数据容忍（读写失败回空/原值不阻断）。
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { MemberScope } from './ProfileCodec';
import { StoredMeta, StoredSheet, SheetCodec } from './SheetCodec';

export class SheetStore {
  /** 卷库容量上限（超出淘汰最旧）。 */
  static MAX_SHEETS: number = 500;
  private static seq: number = 0;

  private static dir(scope: MemberScope): string {
    return scope.baseDir + '/sheetlib';
  }

  private static indexFile(scope: MemberScope): string {
    return SheetStore.dir(scope) + '/index.json';
  }

  private static sheetFile(scope: MemberScope, id: string): string {
    return SheetStore.dir(scope) + '/' + id + '.json';
  }

  /** 生成卷 id（时间戳 + 进程序列，文件名安全字符）。 */
  static newId(): string {
    SheetStore.seq++;
    return `${Date.now().toString(36)}-${SheetStore.seq.toString(36)}`;
  }

  private static ensureDir(scope: MemberScope): boolean {
    const d: string = SheetStore.dir(scope);
    try {
      if (!fs.accessSync(d)) {
        fs.mkdirSync(d, true);
      }
      return true;
    } catch (e) {
      return false;
    }
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

  private static writeText(path: string, text: string): void {
    const file: fs.File = fs.openSync(path,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  }

  private static removeFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      // 删除失败不阻断（残留文件随卷库容量淘汰/卸载清理）
    }
  }

  // ---------- 读 ----------

  /** 元数据索引（最新在前；无索引/脏数据回空表）。 */
  static loadIndex(scope: MemberScope): StoredMeta[] {
    try {
      const f: string = SheetStore.indexFile(scope);
      if (!fs.accessSync(f)) {
        return [];
      }
      return SheetCodec.metaListFromJson(SheetStore.readText(f));
    } catch (e) {
      return [];
    }
  }

  /** 整卷（不存在/脏数据回 null）。 */
  static loadSheet(scope: MemberScope, id: string): StoredSheet | null {
    try {
      const f: string = SheetStore.sheetFile(scope, id);
      if (!fs.accessSync(f)) {
        return null;
      }
      return SheetCodec.sheetFromJson(SheetStore.readText(f));
    } catch (e) {
      return null;
    }
  }

  // ---------- 写 ----------

  private static writeIndex(scope: MemberScope, metas: StoredMeta[]): void {
    SheetStore.writeText(SheetStore.indexFile(scope), SheetCodec.metaListToJson(metas));
  }

  /**
   * 批量入库（生成即入库；同 id 覆盖）：索引最新在前，
   * 超容量淘汰最旧（索引与文件同步删除）。
   */
  static saveSheets(scope: MemberScope, sheets: StoredSheet[]): void {
    if (sheets.length === 0 || !SheetStore.ensureDir(scope)) {
      return;
    }
    const old: StoredMeta[] = SheetStore.loadIndex(scope);
    const incomingIds: Set<string> = new Set<string>();
    for (const s of sheets) {
      incomingIds.add(s.id);
    }
    const metas: StoredMeta[] = [];
    for (const s of sheets) {
      metas.push(SheetCodec.metaOf(s));
      try {
        SheetStore.writeText(SheetStore.sheetFile(scope, s.id), SheetCodec.sheetToJson(s));
      } catch (e) {
        // 单卷写失败跳过（其余卷正常入库）
      }
    }
    for (const m of old) {
      if (!incomingIds.has(m.id)) {
        metas.push(m);
      }
    }
    while (metas.length > SheetStore.MAX_SHEETS) {
      const evicted: StoredMeta | undefined = metas.pop();
      if (evicted === undefined) {
        break;
      }
      SheetStore.removeFile(SheetStore.sheetFile(scope, evicted.id));
    }
    try {
      SheetStore.writeIndex(scope, metas);
    } catch (e) {
      // 索引写失败：文件已入库，下次写入重试
    }
  }

  static saveSheet(scope: MemberScope, sheet: StoredSheet): void {
    SheetStore.saveSheets(scope, [sheet]);
  }

  /** 批改状态更新：整卷重写 + 索引统计刷新。 */
  static updateSheet(scope: MemberScope, sheet: StoredSheet): void {
    if (!SheetStore.ensureDir(scope)) {
      return;
    }
    try {
      SheetStore.writeText(SheetStore.sheetFile(scope, sheet.id), SheetCodec.sheetToJson(sheet));
    } catch (e) {
      return;
    }
    const metas: StoredMeta[] = SheetStore.loadIndex(scope);
    const fresh: StoredMeta = SheetCodec.metaOf(sheet);
    let found: boolean = false;
    for (let i: number = 0; i < metas.length; i++) {
      if (metas[i].id === sheet.id) {
        metas[i] = fresh;
        found = true;
        break;
      }
    }
    if (!found) {
      metas.unshift(fresh);
    }
    try {
      SheetStore.writeIndex(scope, metas);
    } catch (e) {
      // 索引写失败不阻断批改主流程
    }
  }

  /** 批量删除（文件与索引同步）。 */
  static removeSheets(scope: MemberScope, ids: string[]): void {
    if (ids.length === 0) {
      return;
    }
    const removing: Set<string> = new Set<string>();
    for (const id of ids) {
      removing.add(id);
    }
    const metas: StoredMeta[] = SheetStore.loadIndex(scope).filter((m: StoredMeta) => !removing.has(m.id));
    for (const id of ids) {
      SheetStore.removeFile(SheetStore.sheetFile(scope, id));
    }
    try {
      SheetStore.writeIndex(scope, metas);
    } catch (e) {
      // 见上
    }
  }
}
