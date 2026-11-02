/**
 * M6 数据备份恢复（1.0.1 计划）：全量单 JSON 导出 / 导入（本地文件，无需云）。
 *
 * - 备份范围：成员索引 + 全部成员（卷库 sheetlib 整目录 / 错题本 / 每日打卡）；
 * - 文件格式：{ magic, version, exportedAt, checksum, payload }，
 *   payload = { profilesJson, members: [{ id, sheets: [{ name, text }], mistakes, daily }] }；
 * - 校验：djb2(payload JSON) 十六进制校验和；导入先验 magic / version / checksum，
 *   损坏文件整体拒绝（UI 提示），不留半恢复状态；
 * - 恢复语义：整体替换——逐成员写入后覆盖索引，最后清理索引外残留成员目录；
 *   打卡空成员清库（对齐导出侧 '' 语义）；
 * - 安全防护：成员 id 限小写字母数字；sheet 文件名限 .json 且不含路径分隔符。
 */

import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ProfileStore } from '../core/ProfileStore';
import { ProfileCodec, ProfileIndex, MemberScope } from '../core/ProfileCodec';
import { DailyStore } from './DailyStore';

/** 备份内单文件条目（sheetlib 目录快照）。 */
export class BackupFileEntry {
  name: string;
  text: string;

  constructor(name: string, text: string) {
    this.name = name;
    this.text = text;
  }
}

/** 备份内成员数据。 */
export class BackupMemberData {
  id: string;
  sheets: BackupFileEntry[];
  mistakes: string;
  daily: string;

  constructor(id: string, sheets: BackupFileEntry[], mistakes: string, daily: string) {
    this.id = id;
    this.sheets = sheets;
    this.mistakes = mistakes;
    this.daily = daily;
  }
}

export class BackupStore {
  static readonly MAGIC: string = 'MATHSHEET_BACKUP_V1';
  static readonly VERSION: number = 1;
  /** 成员 id 白名单（生成式 id 与 'default' 均为小写字母数字）。 */
  private static readonly ID_RE: RegExp = /^[a-z0-9]+$/;

  private static profilesRoot(ctx: Context): string {
    return ctx.filesDir + '/profiles';
  }

  private static indexFile(ctx: Context): string {
    return ctx.filesDir + '/profiles.json';
  }

  // ---------- 基础 I/O（同步；单文件小体量） ----------

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

  private static ensureDir(path: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  private static removeFile(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      // 删除失败留置（随卸载清理），不阻断
    }
  }

  /** 递归删除目录（rmdirSync 非空语义与平台相关，手动递归稳妥）。 */
  private static removeDir(path: string): void {
    try {
      if (!fs.accessSync(path)) {
        return;
      }
      const st: fs.Stat = fs.statSync(path);
      if (!st.isDirectory()) {
        fs.unlinkSync(path);
        return;
      }
      for (const name of fs.listFileSync(path)) {
        BackupStore.removeDir(path + '/' + name);
      }
      fs.rmdirSync(path);
    } catch (e) {
      // 见上
    }
  }

  // ---------- 类型收窄辅助（避免散落的 as 断言） ----------

  private static str(v: Object | undefined): string {
    return typeof v === 'string' ? v : '';
  }

  private static num(v: Object | undefined): number {
    return typeof v === 'number' ? v : -1;
  }

  private static arr(v: Object | undefined): Object[] {
    if (v !== undefined && Array.isArray(v)) {
      return v as Object[];
    }
    return [];
  }

  // ---------- 校验和 ----------

  /** djb2 哈希 → 无符号 32 位十六进制（小写）。 */
  static djb2Hex(s: string): string {
    let h: number = 5381;
    for (let i: number = 0; i < s.length; i++) {
      h = ((h << 5) + h + s.charCodeAt(i)) | 0;
    }
    return (h >>> 0).toString(16);
  }

  /** 导出文件基名（ASCII：mathsheet_backup_yyyyMMdd）。 */
  static exportFileName(): string {
    const d: Date = new Date();
    const mm: string = d.getMonth() + 1 < 10 ? `0${d.getMonth() + 1}` : `${d.getMonth() + 1}`;
    const dd: string = d.getDate() < 10 ? `0${d.getDate()}` : `${d.getDate()}`;
    return `mathsheet_backup_${d.getFullYear()}${mm}${dd}`;
  }

  // ---------- 导出 ----------

  /** 全量备份文本（无成员返回 null）。 */
  static async buildText(ctx: Context): Promise<string | null> {
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    if (idx.members.length === 0) {
      return null;
    }
    const members: BackupMemberData[] = [];
    for (const m of idx.members) {
      members.push(await BackupStore.snapshotMember(ctx, m.id));
    }
    const payload: Record<string, Object> = {
      'profilesJson': ProfileCodec.indexToJson(idx),
      'members': members
    };
    const root: Record<string, Object> = {
      'magic': BackupStore.MAGIC,
      'version': BackupStore.VERSION,
      'exportedAt': Date.now(),
      'checksum': BackupStore.djb2Hex(JSON.stringify(payload)),
      'payload': payload
    };
    return JSON.stringify(root);
  }

  /** 备份文本 → 沙箱临时文件（cacheDir，供保存器取用；每次覆盖）。 */
  static async buildTempFile(ctx: Context): Promise<string | null> {
    const text: string | null = await BackupStore.buildText(ctx);
    if (text === null) {
      return null;
    }
    const path: string = ctx.cacheDir + '/mathsheet_backup.json';
    BackupStore.writeText(path, text);
    return path;
  }

  private static async snapshotMember(ctx: Context, id: string): Promise<BackupMemberData> {
    const scope: MemberScope = ProfileStore.scopeOf(ctx, id);
    const daily: string = await DailyStore.exportJson(ctx, ProfileStore.dailyNameOf(id));
    return new BackupMemberData(id, BackupStore.snapshotSheets(scope),
      BackupStore.snapshotMistakes(scope), daily);
  }

  /** sheetlib 整目录快照（*.json 全量；缺目录回空）。 */
  private static snapshotSheets(scope: MemberScope): BackupFileEntry[] {
    const out: BackupFileEntry[] = [];
    const dir: string = scope.baseDir + '/sheetlib';
    try {
      if (!fs.accessSync(dir)) {
        return out;
      }
      for (const name of fs.listFileSync(dir)) {
        if (name.length > 5 && name.substring(name.length - 5) === '.json') {
          out.push(new BackupFileEntry(name, BackupStore.readText(dir + '/' + name)));
        }
      }
    } catch (e) {
      // 目录缺失/读取失败按空处理
    }
    return out;
  }

  private static snapshotMistakes(scope: MemberScope): string {
    const f: string = scope.baseDir + '/mistakes.json';
    try {
      if (fs.accessSync(f)) {
        return BackupStore.readText(f);
      }
    } catch (e) {
      // 见上
    }
    return '';
  }

  // ---------- 导入 ----------

  /** 读取用户选择的备份文件（picker URI；失败返回 null）。 */
  static readPicked(uri: string): string | null {
    try {
      const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const stat: fs.Stat = fs.statSync(file.fd);
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        return decoder.decodeToString(new Uint8Array(buf));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return null;
    }
  }

  /**
   * 备份文本 → 校验（magic / version / checksum / 结构）→ 整体替换落盘。
   * 任一校验失败返回 false（UI 提示损坏）。
   */
  static async restoreFromText(ctx: Context, text: string): Promise<boolean> {
    let root: Object;
    try {
      root = JSON.parse(text);
    } catch (e) {
      return false;
    }
    const r: Record<string, Object> = root as Record<string, Object>;
    if (BackupStore.str(r['magic']) !== BackupStore.MAGIC
      || BackupStore.num(r['version']) !== BackupStore.VERSION) {
      return false;
    }
    const payloadObj: Object | undefined = r['payload'];
    if (payloadObj === undefined) {
      return false;
    }
    if (BackupStore.djb2Hex(JSON.stringify(payloadObj)) !== BackupStore.str(r['checksum'])) {
      return false;
    }
    const p: Record<string, Object> = payloadObj as Record<string, Object>;
    const profilesJson: string = BackupStore.str(p['profilesJson']);
    const idx: ProfileIndex = ProfileCodec.indexFromJson(profilesJson);
    if (idx.members.length === 0) {
      return false;
    }
    const members: BackupMemberData[] = BackupStore.parseMembers(p['members']);
    if (members.length === 0) {
      return false;
    }
    // 落盘：逐成员 → 索引覆盖 → 索引外残留清理（任一步 IO 失败整体回 false）
    const ids: Set<string> = new Set<string>();
    try {
      for (const m of members) {
        ids.add(m.id);
        if (!await BackupStore.restoreMember(ctx, m)) {
          return false;
        }
      }
      BackupStore.writeText(BackupStore.indexFile(ctx), profilesJson);
    } catch (e) {
      return false;
    }
    BackupStore.cleanStaleMembers(ctx, ids);
    return true;
  }

  /** 解析成员数组（id 安全校验；文件名路径注入防护；坏条目剔除）。 */
  private static parseMembers(v: Object | undefined): BackupMemberData[] {
    const out: BackupMemberData[] = [];
    for (const el of BackupStore.arr(v)) {
      const mr: Record<string, Object> = el as Record<string, Object>;
      const id: string = BackupStore.str(mr['id']);
      if (!BackupStore.ID_RE.test(id)) {
        continue;
      }
      const sheets: BackupFileEntry[] = [];
      for (const sel of BackupStore.arr(mr['sheets'])) {
        const sr: Record<string, Object> = sel as Record<string, Object>;
        const name: string = BackupStore.str(sr['name']);
        if (name.indexOf('/') >= 0 || name.indexOf('\\') >= 0
          || name.length <= 5 || name.substring(name.length - 5) !== '.json') {
          continue;
        }
        sheets.push(new BackupFileEntry(name, BackupStore.str(sr['text'])));
      }
      out.push(new BackupMemberData(id, sheets, BackupStore.str(mr['mistakes']),
        BackupStore.str(mr['daily'])));
    }
    return out;
  }

  /** 单成员落盘（恢复 = 替换：先清旧卷库目录再写快照；打卡空清库）。 */
  private static async restoreMember(ctx: Context, m: BackupMemberData): Promise<boolean> {
    const dir: string = BackupStore.profilesRoot(ctx) + '/' + m.id;
    if (!BackupStore.ensureDir(dir)) {
      return false;
    }
    BackupStore.removeDir(dir + '/sheetlib');
    if (!BackupStore.ensureDir(dir + '/sheetlib')) {
      return false;
    }
    for (const f of m.sheets) {
      BackupStore.writeText(dir + '/sheetlib/' + f.name, f.text);
    }
    const misPath: string = dir + '/mistakes.json';
    if (m.mistakes !== '') {
      BackupStore.writeText(misPath, m.mistakes);
    } else {
      BackupStore.removeFile(misPath);
    }
    if (m.daily !== '') {
      await DailyStore.restoreJson(ctx, ProfileStore.dailyNameOf(m.id), m.daily);
    } else {
      DailyStore.clear(ctx, ProfileStore.dailyNameOf(m.id));
    }
    return true;
  }

  /** 清理恢复后索引外残留成员目录（含其打卡库）。 */
  private static cleanStaleMembers(ctx: Context, keep: Set<string>): void {
    const rootDir: string = BackupStore.profilesRoot(ctx);
    try {
      if (!fs.accessSync(rootDir)) {
        return;
      }
      for (const name of fs.listFileSync(rootDir)) {
        const st: fs.Stat = fs.statSync(rootDir + '/' + name);
        if (st.isDirectory() && !keep.has(name)) {
          BackupStore.removeDir(rootDir + '/' + name);
          if (BackupStore.ID_RE.test(name)) {
            DailyStore.clear(ctx, ProfileStore.dailyNameOf(name));
          }
        }
      }
    } catch (e) {
      // 残留清理失败不阻断恢复主流程
    }
  }
}
