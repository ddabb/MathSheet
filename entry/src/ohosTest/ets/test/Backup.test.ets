/**
 * 1.0.1 M6 测试套件（backupTest）——数据备份恢复（换机迁移）：
 *   - 全量回环：多成员（卷库/错题本/打卡）→ buildText（magic/version/checksum）
 *     → 抹库（模拟卸载重装）→ restoreFromText 整体替换 → 数据完整恢复；
 *   - 损坏拒绝：非 JSON / 错 magic / 错版本 / 篡改校验和 / 篡改 payload / 空成员
 *     均整体拒绝，真实数据不被半恢复污染；
 *   - 残留清理：恢复后索引外成员目录级联清除（含其打卡库）；
 *   - 空态：无成员导出 null；djb2 校验和与导出文件名契约。
 *
 * 运行协议（模拟器 class 过滤定向跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class backupTest -s timeout 30000
 */
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Context, UIAbility, Want, common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { Profile, ProfileCodec, MemberScope, ProfileIndex } from '../../../main/ets/core/ProfileCodec';
import { ProfileStore } from '../../../main/ets/core/ProfileStore';
import { StoredItem, StoredSheet, StoredMeta } from '../../../main/ets/core/SheetCodec';
import { MistakeEntry } from '../../../main/ets/core/MistakeCodec';
import { SheetStore } from '../../../main/ets/core/SheetStore';
import { MistakeStore } from '../../../main/ets/core/MistakeStore';
import { DailyStore, DailyState } from '../../../main/ets/common/DailyStore';
import { BackupStore } from '../../../main/ets/common/BackupStore';

let cachedCtx: Context | undefined = undefined;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/** 测试上下文：拉起 TestAbility 取其 UIAbilityContext（同 memberTest 协议）。 */
async function ctxOf(): Promise<Context> {
  if (cachedCtx !== undefined) {
    return cachedCtx;
  }
  const delegator: abilityDelegatorRegistry.AbilityDelegator =
    abilityDelegatorRegistry.getAbilityDelegator();
  const want: Want = {
    bundleName: 'com.ddabb.mathsheet',
    moduleName: 'entry_test',
    abilityName: 'TestAbility'
  };
  try {
    await delegator.startAbility(want);
  } catch (e) {
    console.info(`[backupTest] ctxOf: startAbility rejected: ${JSON.stringify(e)}`);
  }
  for (let i: number = 0; i < 10; i++) {
    try {
      const top: UIAbility = await delegator.getCurrentTopAbility();
      if (top !== undefined) {
        const c: common.UIAbilityContext = top.context;
        const nm: string = c !== undefined && c.abilityInfo !== undefined ? c.abilityInfo.name : '';
        if (nm === 'TestAbility') {
          cachedCtx = c;
          return c;
        }
      }
    } catch (e) {
      console.info(`[backupTest] ctxOf: top#${i} rejected: ${JSON.stringify(e)}`);
    }
    await sleep(200);
  }
  cachedCtx = delegator.getAppContext();
  return cachedCtx;
}

/** 递归删除文件/目录。 */
function rmIfExists(path: string): void {
  try {
    if (!fs.accessSync(path)) {
      return;
    }
    if (fs.statSync(path).isDirectory()) {
      for (const name of fs.listFileSync(path)) {
        rmIfExists(path + '/' + name);
      }
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  } catch (e) {
    // 留置不阻断
  }
}

/** 清打卡库（legacy + default），保证用例幂等。 */
async function wipeDailyPrefs(ctx: Context): Promise<void> {
  const names: string[] = [ProfileStore.LEGACY_DAILY, ProfileStore.dailyNameOf(ProfileCodec.DEFAULT_ID)];
  for (const n of names) {
    try {
      await preferences.deletePreferences(ctx, n);
    } catch (e) {
      // 库不存在视为已清
    }
  }
}

/** 每用例前复位：索引/成员目录/legacy 布局/打卡库全清。 */
async function resetProfiles(ctx: Context): Promise<void> {
  rmIfExists(ctx.filesDir + '/profiles.json');
  rmIfExists(ctx.filesDir + '/profiles');
  rmIfExists(ctx.filesDir + '/sheetlib');
  rmIfExists(ctx.filesDir + '/mistakes.json');
  await wipeDailyPrefs(ctx);
}

export default function backupTest() {
  describe('backupTest', () => {
    // ---- 全量回环（导出 → 抹库 → 导入 = 换机迁移） ----
    it('Backup_roundtrip：双成员卷库/错题/打卡全量恢复', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      await resetProfiles(ctx);
      // 种子：默认成员甲（1 卷 2 题 1 错 + 打卡）+ 成员乙（1 卷全对）
      ProfileStore.ensureDefault(ctx, '甲');
      const b: Profile | null = ProfileStore.add(ctx, '乙', 3);
      expect(b !== null).assertTrue();
      if (b !== null) {
        const sa: MemberScope = ProfileStore.scopeOf(ctx, ProfileCodec.DEFAULT_ID);
        const sb: MemberScope = ProfileStore.scopeOf(ctx, b.id);
        const sheetA: StoredSheet = new StoredSheet('bkA1', 1700000000000, '甲卷', 2,
          ['g2_add_100'], 2, 3, true, true, 11,
          [new StoredItem('1 + 1 =', '1 + 1 = 2', '1+1', 'g2_add_100'),
          new StoredItem('2 + 2 =', '2 + 2 = 4', '2+2', 'g2_add_100')], [1, 2]);
        SheetStore.saveSheets(sa, [sheetA]);
        expect(MistakeStore.commitSheet(sa, sheetA)).assertEqual(1);
        const sheetB: StoredSheet = new StoredSheet('bkB1', 1700000000001, '乙卷', 3,
          ['g3_add_1000'], 1, 2, true, false, 12,
          [new StoredItem('100 + 200 =', '100 + 200 = 300', '100+200', 'g3_add_1000')], [1]);
        SheetStore.saveSheets(sb, [sheetB]);
        const daily: DailyState = await DailyStore.record(ctx,
          ProfileStore.dailyNameOf(ProfileCodec.DEFAULT_ID), ['g2_add_100'], 30, 3, true, true, 1);
        expect(daily.streak).assertEqual(1);

        // 导出：结构契约（magic / version / checksum 一致性）
        const text: string | null = await BackupStore.buildText(ctx);
        expect(text !== null).assertTrue();
        if (text !== null) {
          const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
          expect(root['magic'] as string).assertEqual(BackupStore.MAGIC);
          expect(root['version'] as number).assertEqual(BackupStore.VERSION);
          const payload: Object = root['payload'] as Object;
          expect(BackupStore.djb2Hex(JSON.stringify(payload))).assertEqual(root['checksum'] as string);

          // 抹库（模拟卸载重装丢数据）
          await resetProfiles(ctx);
          expect(ProfileStore.loadIndex(ctx).members.length).assertEqual(0);

          // 导入：整体替换恢复
          expect(await BackupStore.restoreFromText(ctx, text)).assertTrue();
          const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
          expect(idx.members.length).assertEqual(2);
          expect(idx.currentId).assertEqual(ProfileCodec.DEFAULT_ID);
          const pa: Profile | null = ProfileCodec.findById(idx, ProfileCodec.DEFAULT_ID);
          const pb: Profile | null = ProfileCodec.findById(idx, b.id);
          expect(pa !== null).assertTrue();
          expect(pb !== null).assertTrue();
          if (pa !== null && pb !== null) {
            expect(pa.name).assertEqual('甲');
            expect(pa.grade).assertEqual(2);
            expect(pb.name).assertEqual('乙');
            expect(pb.grade).assertEqual(3);
          }
          // 卷库：各成员各卷完整（题面/答案/键/marks）
          const metasA: StoredMeta[] = SheetStore.loadIndex(sa);
          expect(metasA.length).assertEqual(1);
          expect(metasA[0].id).assertEqual('bkA1');
          expect(metasA[0].title).assertEqual('甲卷');
          const loadedA: StoredSheet | null = SheetStore.loadSheet(sa, 'bkA1');
          expect(loadedA !== null).assertTrue();
          if (loadedA !== null) {
            expect(loadedA.items.length).assertEqual(2);
            expect(loadedA.items[0].key).assertEqual('1+1');
            expect(loadedA.marks.join(',')).assertEqual('1,2');
            expect(loadedA.seed).assertEqual(11);
          }
          const metasB: StoredMeta[] = SheetStore.loadIndex(sb);
          expect(metasB.length).assertEqual(1);
          expect(metasB[0].id).assertEqual('bkB1');
          // 错题本：甲 1 条（'2+2' 错）、乙 0 条
          const misA: MistakeEntry[] = MistakeStore.load(sa);
          expect(misA.length).assertEqual(1);
          expect(misA[0].key).assertEqual('2+2');
          expect(misA[0].srcId).assertEqual('bkA1');
          expect(MistakeStore.load(sb).length).assertEqual(0);
          // 打卡：甲恢复（streak/配置），乙无记录
          const dailyA: DailyState = await DailyStore.load(ctx,
            ProfileStore.dailyNameOf(ProfileCodec.DEFAULT_ID));
          expect(dailyA.hasConfig).assertTrue();
          expect(dailyA.streak).assertEqual(1);
          expect(dailyA.count).assertEqual(30);
          expect(dailyA.columns).assertEqual(3);
          expect(dailyA.typeIds.join(',')).assertEqual('g2_add_100');
          const dailyB: DailyState = await DailyStore.load(ctx, ProfileStore.dailyNameOf(b.id));
          expect(dailyB.hasConfig).assertFalse();
        }
      }
    });

    // ---- 损坏拒绝（任一校验失败整体拒绝，真实数据不被污染） ----
    it('Backup_rejectsCorruption：非JSON/错magic/错版本/篡改校验和/篡改payload/空成员', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      await resetProfiles(ctx);
      ProfileStore.ensureDefault(ctx, '甲');
      const scope: MemberScope = ProfileStore.scopeOf(ctx, ProfileCodec.DEFAULT_ID);
      const sheet: StoredSheet = new StoredSheet('bkC1', 1700000000000, '守护卷', 2,
        ['g2_add_100'], 1, 3, true, true, 13,
        [new StoredItem('5 + 5 =', '5 + 5 = 10', '5+5', 'g2_add_100')], [1]);
      SheetStore.saveSheets(scope, [sheet]);
      const text: string | null = await BackupStore.buildText(ctx);
      expect(text !== null).assertTrue();
      if (text !== null) {
        // ① 非 JSON
        expect(await BackupStore.restoreFromText(ctx, '{{{not json')).assertFalse();
        // ② 错 magic
        const badMagic: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
        badMagic['magic'] = 'EVIL_BACKUP';
        expect(await BackupStore.restoreFromText(ctx, JSON.stringify(badMagic))).assertFalse();
        // ③ 错版本
        const badVer: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
        badVer['version'] = 99;
        expect(await BackupStore.restoreFromText(ctx, JSON.stringify(badVer))).assertFalse();
        // ④ 篡改校验和
        const badSum: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
        badSum['checksum'] = 'deadbeef';
        expect(await BackupStore.restoreFromText(ctx, JSON.stringify(badSum))).assertFalse();
        // ⑤ 篡改 payload（校验和拦截，重算校验和后结构校验拦截见 ⑥）
        const badPayload: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
        const p: Record<string, Object> = badPayload['payload'] as Record<string, Object>;
        const members: Object[] = p['members'] as Object[];
        const m0: Record<string, Object> = members[0] as Record<string, Object>;
        m0['mistakes'] = 'tampered';
        expect(await BackupStore.restoreFromText(ctx, JSON.stringify(badPayload))).assertFalse();
        // ⑥ 空成员（校验和重算通过，结构校验拒绝）
        const emptyMembers: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
        const p2: Record<string, Object> = emptyMembers['payload'] as Record<string, Object>;
        p2['members'] = [] as Object[];
        emptyMembers['checksum'] = BackupStore.djb2Hex(JSON.stringify(p2));
        expect(await BackupStore.restoreFromText(ctx, JSON.stringify(emptyMembers))).assertFalse();
        // 全部拒绝后真实数据原样（未被半恢复污染）
        const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
        expect(idx.members.length).assertEqual(1);
        expect(idx.members[0].name).assertEqual('甲');
        const metas: StoredMeta[] = SheetStore.loadIndex(scope);
        expect(metas.length).assertEqual(1);
        expect(metas[0].id).assertEqual('bkC1');
      }
    });

    // ---- 残留清理（恢复后索引外成员目录与打卡库级联清除） ----
    it('Backup_cleansStaleMembers：残留目录 + 残留打卡库清除，恢复成员保留', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      await resetProfiles(ctx);
      ProfileStore.ensureDefault(ctx, '甲');
      const text: string | null = await BackupStore.buildText(ctx);
      expect(text !== null).assertTrue();
      if (text !== null) {
        // 种残留：目录成员 stale01（含卷文件）+ 其打卡库
        const staleDir: string = ctx.filesDir + '/profiles/stale01/sheetlib';
        fs.mkdirSync(staleDir, true);
        const staleFile: fs.File = fs.openSync(staleDir + '/junk.json',
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(staleFile.fd, '{}');
        fs.closeSync(staleFile);
        const staleDaily: DailyState = await DailyStore.record(ctx,
          ProfileStore.dailyNameOf('stale01'), ['g2_add_100'], 20, 2, true, false, 1);
        expect(staleDaily.hasConfig).assertTrue();
        // 恢复：备份仅含 default，残留 stale01 被清
        expect(await BackupStore.restoreFromText(ctx, text)).assertTrue();
        expect(fs.accessSync(ctx.filesDir + '/profiles/stale01')).assertFalse();
        expect(fs.accessSync(ctx.filesDir + '/profiles/' + ProfileCodec.DEFAULT_ID)).assertTrue();
        const staleAfter: DailyState = await DailyStore.load(ctx, ProfileStore.dailyNameOf('stale01'));
        expect(staleAfter.hasConfig).assertFalse();
        expect(ProfileStore.loadIndex(ctx).members.length).assertEqual(1);
      }
    });

    // ---- 空态与工具契约 ----
    it('Backup_emptyState：无成员导出 null + djb2/文件名契约', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      await resetProfiles(ctx);
      expect(await BackupStore.buildText(ctx) === null).assertTrue();
      // djb2 黄金值（空串 5381 → '1505'；'a' 177670 → '2b606'）
      expect(BackupStore.djb2Hex('')).assertEqual('1505');
      expect(BackupStore.djb2Hex('a')).assertEqual('2b606');
      // 导出文件名：mathsheet_backup_yyyyMMdd
      const nameRe: RegExp = new RegExp('^mathsheet_backup_\\d{8}$');
      expect(nameRe.test(BackupStore.exportFileName())).assertTrue();
      await wipeDailyPrefs(ctx);
    });
  });
}
