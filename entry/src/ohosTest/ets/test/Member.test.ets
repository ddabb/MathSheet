/**
 * M7 家庭成员档案测试套件（memberTest）——本地多档（计划 §5.3）：
 *   - ProfileStore 全生命周期：ensureDefault 首启建档（幂等）、add（不切换当前/上限 6/空名守卫）、
 *     rename（trim + 年级钳制）、setCurrent、remove（级联清理/当前被删回落首位/最后一名禁删）；
 *   - 存量迁移：M7 前布局（filesDir/sheetlib + mistakes.json + daily_practice）
 *     → 默认成员目录原子搬入；DailyStore.migrate 打卡库搬迁幂等；
 *   - 成员隔离：卷库/错题本按 MemberScope 物理隔离，删除成员级联清理不伤他档。
 * 纯逻辑（ProfileCodec 编解码/钳制）离线 verify 已覆盖，此处聚焦真 Context I/O。
 *
 * 运行协议（模拟器 class 过滤定向跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class memberTest -s timeout 30000
 */
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Context, UIAbility, Want, common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { Profile, ProfileIndex, MemberScope, ProfileCodec } from '../../../main/ets/core/ProfileCodec';
import { ProfileStore } from '../../../main/ets/core/ProfileStore';
import { StoredItem, StoredSheet, StoredMeta, SheetCodec } from '../../../main/ets/core/SheetCodec';
import { MistakeEntry, MistakeCodec } from '../../../main/ets/core/MistakeCodec';
import { SheetStore } from '../../../main/ets/core/SheetStore';
import { MistakeStore } from '../../../main/ets/core/MistakeStore';
import { DailyStore, DailyState } from '../../../main/ets/common/DailyStore';

let cachedCtx: Context | undefined = undefined;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/**
 * 测试上下文：拉起 TestAbility 取其 UIAbilityContext——delegator 的 ApplicationContext
 * 对 preferences 全系 401（context invalid），而 DailyStore/ProfileStore 依赖 preferences。
 * TestAbility 属 entry_test HAP，filesDir/preferences 均独立于主应用（haps/entry）真实数据。
 */
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
    console.info('[memberTest] ctxOf: startAbility begin');
    await delegator.startAbility(want);
    console.info('[memberTest] ctxOf: startAbility resolved');
  } catch (e) {
    console.info(`[memberTest] ctxOf: startAbility rejected: ${JSON.stringify(e)}`);
  }
  for (let i: number = 0; i < 10; i++) {
    try {
      const top: UIAbility = await delegator.getCurrentTopAbility();
      if (top !== undefined) {
        const c: common.UIAbilityContext = top.context;
        const nm: string = c !== undefined && c.abilityInfo !== undefined ? c.abilityInfo.name : '';
        console.info(`[memberTest] ctxOf: top#${i} ability=${nm}`);
        if (nm === 'TestAbility') {
          cachedCtx = c;
          return c;
        }
      } else {
        console.info(`[memberTest] ctxOf: top#${i} undefined`);
      }
    } catch (e) {
      console.info(`[memberTest] ctxOf: top#${i} rejected: ${JSON.stringify(e)}`);
    }
    await sleep(200);
  }
  console.info('[memberTest] ctxOf: FALLBACK to appContext');
  cachedCtx = delegator.getAppContext();
  return cachedCtx;
}

/** 递归删除文件/目录（rmdirSync 非空语义与平台相关，手动递归稳妥）。 */
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

/** 写文本文件（TRUNC 覆盖）。 */
function writeRaw(path: string, text: string): void {
  const f: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    fs.writeSync(f.fd, text);
  } finally {
    fs.closeSync(f);
  }
}

/** 清打卡库（legacy + 默认成员），保证 migrate/record 用例幂等。 */
async function wipeDailyPrefs(ctx: Context): Promise<void> {
  try {
    await preferences.deletePreferences(ctx, ProfileStore.LEGACY_DAILY);
  } catch (e) {
    // 库不存在视为已清
  }
  try {
    await preferences.deletePreferences(ctx, ProfileStore.dailyNameOf(ProfileCodec.DEFAULT_ID));
  } catch (e) {
    // 库不存在视为已清
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

export default function memberTest() {
  describe('memberTest', () => {
    // ---- ProfileStore 全生命周期（真 Context I/O） ----
    it('ProfileStore_lifecycle', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      await resetProfiles(ctx);
      // 无索引：scopeCurrent 防御性回落默认成员
      expect(ProfileStore.scopeCurrent(ctx).baseDir)
        .assertEqual(ctx.filesDir + '/profiles/' + ProfileCodec.DEFAULT_ID);
      // 首启建档
      let idx: ProfileIndex = ProfileStore.ensureDefault(ctx, '默认孩子');
      expect(idx.members.length).assertEqual(1);
      expect(idx.currentId).assertEqual(ProfileCodec.DEFAULT_ID);
      expect(idx.members[0].name).assertEqual('默认孩子');
      expect(idx.members[0].grade).assertEqual(2);
      // 幂等：已有索引原样返回（默认名不再生效）
      const again: ProfileIndex = ProfileStore.ensureDefault(ctx, '不应生效');
      expect(again.members.length).assertEqual(1);
      expect(again.members[0].name).assertEqual('默认孩子');
      // 打卡库名约定
      expect(ProfileStore.dailyNameOf('abc')).assertEqual('daily_abc');
      // 新增：trim 昵称 / 年级钳制透传 / 不切换当前 / 建目录
      const b: Profile | null = ProfileStore.add(ctx, '  小明  ', 1);
      expect(b !== null).assertTrue();
      if (b !== null) {
        expect(b.name).assertEqual('小明');
        expect(b.grade).assertEqual(1);
        idx = ProfileStore.loadIndex(ctx);
        expect(idx.members.length).assertEqual(2);
        expect(idx.currentId).assertEqual(ProfileCodec.DEFAULT_ID);
        expect(fs.accessSync(ctx.filesDir + '/profiles/' + b.id)).assertTrue();
        // 空名新增拒绝
        expect(ProfileStore.add(ctx, '   ', 2) === null).assertTrue();
        // 改名 + 调年级（id/createdAt 不变）
        expect(ProfileStore.rename(ctx, b.id, '  小红  ', 3)).assertTrue();
        idx = ProfileStore.loadIndex(ctx);
        const rb: Profile | null = ProfileCodec.findById(idx, b.id);
        expect(rb !== null).assertTrue();
        if (rb !== null) {
          expect(rb.name).assertEqual('小红');
          expect(rb.grade).assertEqual(3);
          expect(rb.id).assertEqual(b.id);
          expect(rb.createdAt).assertEqual(b.createdAt);
        }
        // 空名改名 / 未知 id 拒绝
        expect(ProfileStore.rename(ctx, b.id, '   ', 2)).assertFalse();
        expect(ProfileStore.rename(ctx, 'no_such_member', 'X', 2)).assertFalse();
        // 切换当前
        expect(ProfileStore.setCurrent(ctx, b.id)).assertTrue();
        expect(ProfileStore.loadIndex(ctx).currentId).assertEqual(b.id);
        expect(ProfileStore.setCurrent(ctx, 'no_such_member')).assertFalse();
        // 补满至上限 6，第 7 个拒绝
        for (let i: number = idx.members.length; i < ProfileCodec.MAX_MEMBERS; i++) {
          expect(ProfileStore.add(ctx, `成员${i}`, 2) !== null).assertTrue();
        }
        expect(ProfileStore.loadIndex(ctx).members.length).assertEqual(ProfileCodec.MAX_MEMBERS);
        expect(ProfileStore.add(ctx, '超限', 2) === null).assertTrue();
        // 删除当前：级联目录清理 + currentId 回落首位
        const curId: string = ProfileStore.loadIndex(ctx).currentId;
        const curDir: string = ctx.filesDir + '/profiles/' + curId;
        expect(fs.accessSync(curDir)).assertTrue();
        expect(ProfileStore.remove(ctx, curId)).assertTrue();
        idx = ProfileStore.loadIndex(ctx);
        expect(idx.members.length).assertEqual(ProfileCodec.MAX_MEMBERS - 1);
        expect(idx.currentId).assertEqual(idx.members[0].id);
        expect(fs.accessSync(curDir)).assertFalse();
        // 删除未知 id 拒绝
        expect(ProfileStore.remove(ctx, 'no_such_member')).assertFalse();
        // 收缩到 1 名：最后一名禁删
        const all: Profile[] = idx.members.slice();
        for (let i: number = 1; i < all.length; i++) {
          expect(ProfileStore.remove(ctx, all[i].id)).assertTrue();
        }
        idx = ProfileStore.loadIndex(ctx);
        expect(idx.members.length).assertEqual(1);
        expect(ProfileStore.remove(ctx, idx.members[0].id)).assertFalse();
        expect(ProfileStore.loadIndex(ctx).members.length).assertEqual(1);
      }
    });

    // ---- 存量迁移（M7 前布局 → 默认成员目录） ----
    it('ProfileStore_legacyMigration', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      await resetProfiles(ctx);
      // 种 legacy 卷库
      const legacyLib: string = ctx.filesDir + '/sheetlib';
      fs.mkdirSync(legacyLib, true);
      const sheet: StoredSheet = new StoredSheet('m7leg0', 1700000000000, '存量卷', 2,
        ['g2_add_100'], 2, 3, true, true, 7,
        [new StoredItem('23 + 15 =', '23 + 15 = 38', '15+23', 'g2_add_100'),
        new StoredItem('6 × 7 =', '6 × 7 = 42', '6×7', 'g2_mul_table')], [1, 2]);
      writeRaw(legacyLib + '/m7leg0.json', SheetCodec.sheetToJson(sheet));
      writeRaw(legacyLib + '/index.json', SheetCodec.metaListToJson([SheetCodec.metaOf(sheet)]));
      // 种 legacy 错题本
      writeRaw(ctx.filesDir + '/mistakes.json', MistakeCodec.toJson([
        new MistakeEntry('15+23', '23 + 15 =', '23 + 15 = 38', 'g2_add_100',
          'm7leg0', '存量卷', 1, 1700000000001)
      ]));
      // 种 legacy 打卡库（30 题 3 列无答案）
      const seeded: DailyState = await DailyStore.record(ctx, ProfileStore.LEGACY_DAILY,
        ['g2_add_100'], 30, 3, true, false, 1);
      expect(seeded.streak).assertEqual(1);
      // 首启：建档 + 存量原子搬入
      const idx: ProfileIndex = ProfileStore.ensureDefault(ctx, '默认成员');
      expect(idx.members.length).assertEqual(1);
      expect(fs.accessSync(legacyLib)).assertFalse();
      expect(fs.accessSync(ctx.filesDir + '/mistakes.json')).assertFalse();
      const scope: MemberScope = ProfileStore.scopeOf(ctx, ProfileCodec.DEFAULT_ID);
      const metas: StoredMeta[] = SheetStore.loadIndex(scope);
      expect(metas.length).assertEqual(1);
      expect(metas[0].id).assertEqual('m7leg0');
      expect(metas[0].title).assertEqual('存量卷');
      const loaded: StoredSheet | null = SheetStore.loadSheet(scope, 'm7leg0');
      expect(loaded !== null).assertTrue();
      if (loaded !== null) {
        expect(loaded.items.length).assertEqual(2);
        expect(loaded.seed).assertEqual(7);
      }
      const mis: MistakeEntry[] = MistakeStore.load(scope);
      expect(mis.length).assertEqual(1);
      expect(mis[0].key).assertEqual('15+23');
      expect(mis[0].srcId).assertEqual('m7leg0');
      // 打卡库搬迁：legacy → daily_default
      const dailyName: string = ProfileStore.dailyNameOf(ProfileCodec.DEFAULT_ID);
      await DailyStore.migrate(ctx, ProfileStore.LEGACY_DAILY, dailyName);
      const daily: DailyState = await DailyStore.load(ctx, dailyName);
      expect(daily.hasConfig).assertTrue();
      expect(daily.count).assertEqual(30);
      expect(daily.columns).assertEqual(3);
      expect(daily.headerOn).assertTrue();
      expect(daily.answerOn).assertFalse();
      expect(daily.sets).assertEqual(1);
      expect(daily.streak).assertEqual(1);
      expect(daily.typeIds.length).assertEqual(1);
      expect(daily.typeIds[0]).assertEqual('g2_add_100');
      // 幂等：重复 migrate / 重复 ensureDefault 不重复不报错
      await DailyStore.migrate(ctx, ProfileStore.LEGACY_DAILY, dailyName);
      const daily2: DailyState = await DailyStore.load(ctx, dailyName);
      expect(daily2.streak).assertEqual(1);
      const idx2: ProfileIndex = ProfileStore.ensureDefault(ctx, '默认成员');
      expect(idx2.members.length).assertEqual(1);
      expect(SheetStore.loadIndex(scope).length).assertEqual(1);
    });

    // ---- 成员隔离：卷库/错题本物理隔离 + 级联删除不伤他档 ----
    it('ProfileStore_memberIsolation', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      await resetProfiles(ctx);
      const idx: ProfileIndex = ProfileStore.ensureDefault(ctx, '甲');
      const b: Profile | null = ProfileStore.add(ctx, '乙', 2);
      expect(b !== null).assertTrue();
      if (b !== null) {
        const sa: MemberScope = ProfileStore.scopeOf(ctx, idx.currentId);
        const sb: MemberScope = ProfileStore.scopeOf(ctx, b.id);
        expect(sa.baseDir !== sb.baseDir).assertTrue();
        // 甲：入库 1 卷（1 错）
        const sheetA: StoredSheet = new StoredSheet('m7isoA', 1700000000000, '甲卷', 2,
          ['g2_add_100'], 2, 3, true, true, 1,
          [new StoredItem('1 + 1 =', '1 + 1 = 2', '1+1', 'g2_add_100'),
          new StoredItem('2 + 2 =', '2 + 2 = 4', '2+2', 'g2_add_100')], [2, 1]);
        SheetStore.saveSheets(sa, [sheetA]);
        expect(MistakeStore.commitSheet(sa, sheetA)).assertEqual(1);
        // 乙：入库另 1 卷（全对）
        const sheetB: StoredSheet = new StoredSheet('m7isoB', 1700000000001, '乙卷', 2,
          ['g2_add_100'], 1, 3, true, true, 2,
          [new StoredItem('5 + 5 =', '5 + 5 = 10', '5+5', 'g2_add_100')], [1]);
        SheetStore.saveSheets(sb, [sheetB]);
        // 隔离断言：各见各卷，互不可见
        const metasA: StoredMeta[] = SheetStore.loadIndex(sa);
        const metasB: StoredMeta[] = SheetStore.loadIndex(sb);
        expect(metasA.length).assertEqual(1);
        expect(metasA[0].id).assertEqual('m7isoA');
        expect(metasB.length).assertEqual(1);
        expect(metasB[0].id).assertEqual('m7isoB');
        expect(SheetStore.loadSheet(sa, 'm7isoB') === null).assertTrue();
        expect(SheetStore.loadSheet(sb, 'm7isoA') === null).assertTrue();
        expect(MistakeStore.load(sa).length).assertEqual(1);
        expect(MistakeStore.load(sb).length).assertEqual(0);
        // 删除乙：目录级联清理，甲档原样
        const dirB: string = ctx.filesDir + '/profiles/' + b.id;
        expect(fs.accessSync(dirB)).assertTrue();
        expect(ProfileStore.remove(ctx, b.id)).assertTrue();
        expect(fs.accessSync(dirB)).assertFalse();
        expect(SheetStore.loadIndex(sa).length).assertEqual(1);
        expect(MistakeStore.load(sa).length).assertEqual(1);
        expect(ProfileStore.scopeCurrent(ctx).baseDir).assertEqual(sa.baseDir);
      }
    });
  });
}
