/**
 * M7 家庭成员档案 I/O（计划 §5.3）：
 *
 * - 索引：filesDir/profiles.json（ProfileCodec 编解码，脏容忍）；
 * - 数据根：filesDir/profiles/{memberId}/——sheetlib/ 与 mistakes.json 由
 *   SheetStore/MistakeStore 按 MemberScope 落位；打卡走 preferences 'daily_{memberId}'；
 * - 首启迁移（ensureDefault）：无索引时创建默认成员，存量 filesDir/sheetlib 与
 *   mistakes.json 原地移入其目录（rename 原子移动，失败留置不阻断，数据不丢）；
 * - 删除级联：成员目录递归清理 + 对应打卡 preferences 删除（fire-and-forget）；
 * - 成员 id：m + 时间戳36 + 进程序列36（文件与 preferences 名安全字符，无连字符）。
 */

import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { Profile, ProfileIndex, MemberScope, ProfileCodec } from './ProfileCodec';

export class ProfileStore {
  /** 旧版（M7 前）每日一练 preferences 名，迁移源。 */
  static readonly LEGACY_DAILY: string = 'daily_practice';
  private static seq: number = 0;

  private static indexFile(ctx: Context): string {
    return ctx.filesDir + '/profiles.json';
  }

  private static profilesRoot(ctx: Context): string {
    return ctx.filesDir + '/profiles';
  }

  private static memberDir(ctx: Context, id: string): string {
    return ProfileStore.profilesRoot(ctx) + '/' + id;
  }

  /** 成员 id（文件与 preferences 名安全：小写字母数字）。 */
  static newId(): string {
    ProfileStore.seq++;
    return `m${Date.now().toString(36)}${ProfileStore.seq.toString(36)}`;
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
        ProfileStore.removeDir(path + '/' + name);
      }
      fs.rmdirSync(path);
    } catch (e) {
      // 删除失败留置（随卸载清理），不阻断
    }
  }

  // ---------- 索引读写 ----------

  static loadIndex(ctx: Context): ProfileIndex {
    try {
      const f: string = ProfileStore.indexFile(ctx);
      if (!fs.accessSync(f)) {
        return new ProfileIndex('', []);
      }
      return ProfileCodec.indexFromJson(ProfileStore.readText(f));
    } catch (e) {
      return new ProfileIndex('', []);
    }
  }

  private static saveIndex(ctx: Context, idx: ProfileIndex): boolean {
    if (!ProfileStore.ensureDir(ProfileStore.profilesRoot(ctx))) {
      return false;
    }
    try {
      ProfileStore.writeText(ProfileStore.indexFile(ctx), ProfileCodec.indexToJson(idx));
      return true;
    } catch (e) {
      return false;
    }
  }

  // ---------- 生命周期 ----------

  /** 存量迁移（M7 前布局 → 默认成员目录）：rename 原子移动。 */
  private static migrateLegacy(ctx: Context, memberId: string): void {
    const target: string = ProfileStore.memberDir(ctx, memberId);
    try {
      const legacyLib: string = ctx.filesDir + '/sheetlib';
      if (fs.accessSync(legacyLib) && !fs.accessSync(target + '/sheetlib')) {
        fs.renameSync(legacyLib, target + '/sheetlib');
      }
    } catch (e) {
      // 见类注释：失败留置不阻断
    }
    try {
      const legacyMis: string = ctx.filesDir + '/mistakes.json';
      if (fs.accessSync(legacyMis) && !fs.accessSync(target + '/mistakes.json')) {
        fs.renameSync(legacyMis, target + '/mistakes.json');
      }
    } catch (e) {
      // 见上
    }
  }

  /**
   * 首启引导：无索引 → 建默认成员（携存量迁移）；有索引 → 原样返回
   * （currentId 有效性由解析层保证）。
   * @param defaultName 默认成员昵称（调用方本地化）
   */
  static ensureDefault(ctx: Context, defaultName: string): ProfileIndex {
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    if (idx.members.length > 0) {
      return idx;
    }
    const name: string = ProfileCodec.clampName(defaultName);
    const p: Profile = new Profile(ProfileCodec.DEFAULT_ID,
      name !== '' ? name : ProfileCodec.DEFAULT_ID, 2, Date.now());
    ProfileStore.ensureDir(ProfileStore.memberDir(ctx, p.id));
    ProfileStore.migrateLegacy(ctx, p.id);
    const fresh: ProfileIndex = new ProfileIndex(p.id, [p]);
    ProfileStore.saveIndex(ctx, fresh);
    return fresh;
  }

  /** 新增成员（上限/空名守卫；建目录；不切换 current）。返回 null = 超上限或昵称为空。 */
  static add(ctx: Context, name: string, grade: number): Profile | null {
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    if (idx.members.length >= ProfileCodec.MAX_MEMBERS) {
      return null;
    }
    const clean: string = ProfileCodec.clampName(name);
    if (clean === '') {
      return null;
    }
    const p: Profile = new Profile(ProfileStore.newId(), clean,
      ProfileCodec.clampGrade(grade), Date.now());
    if (!ProfileStore.ensureDir(ProfileStore.memberDir(ctx, p.id))) {
      return null;
    }
    const members: Profile[] = idx.members.slice();
    members.push(p);
    ProfileStore.saveIndex(ctx, new ProfileIndex(idx.currentId, members));
    return p;
  }

  /** 改名 / 调年级（id 与 createdAt 不变）。 */
  static rename(ctx: Context, id: string, name: string, grade: number): boolean {
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    const clean: string = ProfileCodec.clampName(name);
    if (clean === '') {
      return false;
    }
    const members: Profile[] = [];
    let hit: boolean = false;
    for (const m of idx.members) {
      if (m.id === id) {
        members.push(new Profile(m.id, clean, ProfileCodec.clampGrade(grade), m.createdAt));
        hit = true;
      } else {
        members.push(m);
      }
    }
    if (!hit) {
      return false;
    }
    return ProfileStore.saveIndex(ctx, new ProfileIndex(idx.currentId, members));
  }

  /** 删除成员（最后一名禁删；级联清数据目录与打卡 preferences；当前被删自动回落首位）。 */
  static remove(ctx: Context, id: string): boolean {
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    if (idx.members.length <= 1) {
      return false;
    }
    const members: Profile[] = [];
    let hit: boolean = false;
    for (const m of idx.members) {
      if (m.id === id) {
        hit = true;
      } else {
        members.push(m);
      }
    }
    if (!hit) {
      return false;
    }
    ProfileStore.removeDir(ProfileStore.memberDir(ctx, id));
    try {
      preferences.deletePreferences(ctx, ProfileStore.dailyNameOf(id)).catch(() => {
      });
    } catch (e) {
      // 打卡库清理失败不阻断成员删除（数据目录已清，残留随卸载兜底）
    }
    const cur: string = idx.currentId === id ? members[0].id : idx.currentId;
    return ProfileStore.saveIndex(ctx, new ProfileIndex(cur, members));
  }

  /** 切换当前成员。 */
  static setCurrent(ctx: Context, id: string): boolean {
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    if (ProfileCodec.findById(idx, id) === null) {
      return false;
    }
    if (idx.currentId === id) {
      return true;
    }
    return ProfileStore.saveIndex(ctx, new ProfileIndex(id, idx.members));
  }

  // ---------- 作用域 ----------

  /** 指定成员存储作用域。 */
  static scopeOf(ctx: Context, id: string): MemberScope {
    return new MemberScope(ProfileStore.memberDir(ctx, id));
  }

  /** 当前成员存储作用域（无索引时回落默认成员，防御首启竞态）。 */
  static scopeCurrent(ctx: Context): MemberScope {
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    if (idx.members.length === 0) {
      return ProfileStore.scopeOf(ctx, ProfileCodec.DEFAULT_ID);
    }
    return ProfileStore.scopeOf(ctx, idx.currentId);
  }

  /** 成员打卡 preferences 名（'daily_' + 成员 id）。 */
  static dailyNameOf(id: string): string {
    return 'daily_' + id;
  }
}
