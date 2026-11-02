/**
 * 1.0.1 M1 测试套件（drillTest）——错题重练闭环打磨：
 *   - MistakeDrill 模式与比例：'only' 仅错题零新题 / 'mixed' 1:1·1:2·1:3 混编 /
 *     比例钳制（>3 收 3、非法值收 1）/ maxItems 截断保序 / 同种子确定性；
 *   - DrillFlow 来源日期：标题追加最新错题 MM-DD（本地时区正午基准），无时间信息原样；
 *   - DrillFlow.buildDrillSheet：错题物化入库（真 Context I/O），空错题返回 null。
 *
 * 运行协议（模拟器 class 过滤定向跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class drillTest -s timeout 30000
 */
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Context, UIAbility, Want, common } from '@kit.AbilityKit';
import { MistakeEntry } from '../../../main/ets/core/MistakeCodec';
import { MistakeDrill, DRILL_MODE_ONLY, DRILL_MODE_MIXED } from '../../../main/ets/core/MistakeDrill';
import { StoredItem, StoredSheet, StoredMeta } from '../../../main/ets/core/SheetCodec';
import { SheetStore } from '../../../main/ets/core/SheetStore';
import { MemberScope } from '../../../main/ets/core/ProfileCodec';
import { DrillFlow } from '../../../main/ets/common/DrillFlow';
import { fileIo as fs } from '@kit.CoreFileKit';

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
    console.info(`[drillTest] ctxOf: startAbility rejected: ${JSON.stringify(e)}`);
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
      console.info(`[drillTest] ctxOf: top#${i} rejected: ${JSON.stringify(e)}`);
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

export default function drillTest() {
  describe('drillTest', () => {
    // ---- MistakeDrill 模式与比例（1.0.1 M1） ----
    it('MistakeDrill_modeOnly：仅错题零新题 + 去重 + maxItems 截断保序', 0, () => {
      const m1: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 1, 1730000000000);
      const m2: MistakeEntry = new MistakeEntry('8\u00d77', '8 \u00d7 7 =', '8 \u00d7 7 = 56',
        'g2_mul_table', 's1', '卷一', 2, 1730000100000);
      const dup: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 3, 1730000200000);
      // 仅错题：原样收录，比例参数不生效，重复 key 去重
      const items: StoredItem[] = MistakeDrill.buildItems([m1, m2, dup], 9527, 200, DRILL_MODE_ONLY, 3);
      expect(items.length).assertEqual(2);
      expect(items[0].key).assertEqual('15+23');
      expect(items[1].key).assertEqual('8\u00d77');
      // maxItems 截断：保序不跳跃
      const cut: StoredItem[] = MistakeDrill.buildItems([m1, m2], 9527, 1, DRILL_MODE_ONLY, 2);
      expect(cut.length).assertEqual(1);
      expect(cut[0].key).assertEqual('15+23');
    });

    it('MistakeDrill_ratio：1:1 / 1:2 / 1:3 混编 + 原题居首 + 新题不重复', 0, () => {
      const m1: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 1, 1730000000000);
      for (const ratio of [1, 2, 3]) {
        const items: StoredItem[] = MistakeDrill.buildItems([m1], 4100 + ratio, 200,
          DRILL_MODE_MIXED, ratio);
        expect(items.length).assertEqual(1 + ratio);
        expect(items[0].key).assertEqual('15+23');
        const keys: Set<string> = new Set<string>();
        for (const it of items) {
          keys.add(it.key);
        }
        expect(keys.size).assertEqual(items.length);
      }
    });

    it('MistakeDrill_ratioClamp：>3 收 3、0/负值收 1（Math.max 钳制）', 0, () => {
      const m1: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 1, 1730000000000);
      const hi: StoredItem[] = MistakeDrill.buildItems([m1], 4201, 200, DRILL_MODE_MIXED, 99);
      expect(hi.length).assertEqual(4);
      const zero: StoredItem[] = MistakeDrill.buildItems([m1], 4202, 200, DRILL_MODE_MIXED, 0);
      expect(zero.length).assertEqual(2);
      const neg: StoredItem[] = MistakeDrill.buildItems([m1], 4203, 200, DRILL_MODE_MIXED, -5);
      expect(neg.length).assertEqual(2);
    });

    it('MistakeDrill_determinism：同种子同卷 + 默认参数 = 历史 1:2 行为', 0, () => {
      const m1: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 1, 1730000000000);
      const m2: MistakeEntry = new MistakeEntry('8\u00d77', '8 \u00d7 7 =', '8 \u00d7 7 = 56',
        'g2_mul_table', 's1', '卷一', 2, 1730000100000);
      const a: StoredItem[] = MistakeDrill.buildItems([m1, m2], 31337, 200);
      const b: StoredItem[] = MistakeDrill.buildItems([m1, m2], 31337, 200,
        DRILL_MODE_MIXED, 2);
      expect(a.map((it: StoredItem) => it.key).join('|'))
        .assertEqual(b.map((it: StoredItem) => it.key).join('|'));
      // 历史黄金：2 错题 × (1 原题 + 2 新题) = 6
      expect(a.length).assertEqual(6);
      // 换种子新题不同（键序不相等）
      const c: StoredItem[] = MistakeDrill.buildItems([m1, m2], 777, 200);
      expect(c.map((it: StoredItem) => it.key).join('|') === a.map((it: StoredItem) => it.key).join('|'))
        .assertFalse();
    });

    it('MistakeDrill_buildSheet：模式/比例透传 + 空错题 null + marks 全 0', 0, () => {
      const m1: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 1, 1730000000000);
      const only: StoredSheet | null = MistakeDrill.buildSheet('dr1', 9, '仅错题卷',
        [m1], 55, 200, DRILL_MODE_ONLY, 2);
      expect(only !== null).assertTrue();
      if (only !== null) {
        expect(only.items.length).assertEqual(1);
        expect(only.marks.length).assertEqual(1);
        expect(only.marks[0]).assertEqual(0);
        expect(only.typeIds.join(',')).assertEqual('g2_add100_plus');
      }
      const mixed: StoredSheet | null = MistakeDrill.buildSheet('dr2', 9, '混编卷',
        [m1], 55, 200, DRILL_MODE_MIXED, 3);
      expect(mixed !== null).assertTrue();
      if (mixed !== null) {
        expect(mixed.items.length).assertEqual(4);
        for (const mk of mixed.marks) {
          expect(mk).assertEqual(0);
        }
      }
      expect(MistakeDrill.buildSheet('dr3', 0, 'T', [], 1, 200, DRILL_MODE_MIXED, 2) === null)
        .assertTrue();
    });

    // ---- DrillFlow 来源日期（1.0.1 M1 来源可追溯） ----
    it('DrillFlow_titleWithSourceDate：最新错题 MM-DD 后缀 / 无时间原样', 0, () => {
      // 本地时区正午基准（任意时区偏移 < 12h 时日期稳定）
      const oct30: number = new Date(2026, 9, 30, 12, 0, 0).getTime();
      const oct05: number = new Date(2026, 9, 5, 12, 0, 0).getTime();
      const mA: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 1, oct05);
      const mB: MistakeEntry = new MistakeEntry('8\u00d77', '8 \u00d7 7 =', '8 \u00d7 7 = 56',
        'g2_mul_table', 's1', '卷一', 2, oct30);
      // 取最新 lastWrongAt（10-30 > 10-05）
      expect(DrillFlow.titleWithSourceDate('错题重练', [mA, mB])).assertEqual('错题重练 10-30');
      expect(DrillFlow.titleWithSourceDate('错题重练', [mB, mA])).assertEqual('错题重练 10-30');
      // 单条 / 无时间信息（lastWrongAt=0）/ 空列表
      expect(DrillFlow.titleWithSourceDate('错题重练', [mB])).assertEqual('错题重练 10-30');
      const noTime: MistakeEntry = new MistakeEntry('1+1', '1 + 1 =', '1 + 1 = 2',
        'g2_add100_plus', 's1', '卷一', 1, 0);
      expect(DrillFlow.titleWithSourceDate('错题重练', [noTime])).assertEqual('错题重练');
      expect(DrillFlow.titleWithSourceDate('错题重练', [])).assertEqual('错题重练');
    });

    // ---- DrillFlow 物化入库（真 Context I/O） ----
    it('DrillFlow_buildDrillSheet：入库卷库 + 标题带来源日期 + 空错题 null', 0, async (): Promise<void> => {
      const ctx: Context = await ctxOf();
      const scope: MemberScope = new MemberScope(ctx.filesDir + '/profiles/drillflow');
      rmIfExists(scope.baseDir);
      const oct30: number = new Date(2026, 9, 30, 12, 0, 0).getTime();
      const m1: MistakeEntry = new MistakeEntry('15+23', '15 + 23 =', '15 + 23 = 38',
        'g2_add100_plus', 's1', '卷一', 1, oct30);
      const m2: MistakeEntry = new MistakeEntry('8\u00d77', '8 \u00d7 7 =', '8 \u00d7 7 = 56',
        'g2_mul_table', 's1', '卷一', 2, oct30);
      const sheet: StoredSheet | null = DrillFlow.buildDrillSheet(scope, [m1, m2], '错题重练',
        DRILL_MODE_MIXED, 2);
      expect(sheet !== null).assertTrue();
      if (sheet !== null) {
        expect(sheet.title).assertEqual('错题重练 10-30');
        // 入库后卷库索引可见（1 卷 = 2 错题 × (1 + 2) = 6 题）
        const metas: StoredMeta[] = SheetStore.loadIndex(scope);
        expect(metas.length).assertEqual(1);
        expect(metas[0].id).assertEqual(sheet.id);
        const loaded: StoredSheet | null = SheetStore.loadSheet(scope, sheet.id);
        expect(loaded !== null).assertTrue();
        if (loaded !== null) {
          expect(loaded.title).assertEqual('错题重练 10-30');
          expect(loaded.items.length).assertEqual(6);
          expect(loaded.marks.length).assertEqual(6);
        }
      }
      // 空错题：返回 null 不入库
      expect(DrillFlow.buildDrillSheet(scope, [], '错题重练') === null).assertTrue();
      // 仅错题模式：2 原题入库
      const only: StoredSheet | null = DrillFlow.buildDrillSheet(scope, [m1, m2], '仅错题',
        DRILL_MODE_ONLY, 2);
      expect(only !== null).assertTrue();
      if (only !== null) {
        expect(only.items.length).assertEqual(2);
      }
      rmIfExists(scope.baseDir);
    });
  });
}
