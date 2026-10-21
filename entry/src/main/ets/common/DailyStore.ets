/**
 * 每日一练持久化（计划 §4.1 / §6.4；M7 §5.3 作用域化）：
 * preferences 轻量存储，按成员分库（'daily_' + 成员 id，见 ProfileStore.dailyNameOf）——
 * 记忆上次生成配置（首页一键"生成今天的题卡"）+ 本地连续打卡天数。
 * 打卡语义：同日重复生成不累计；昨日有记录则 +1；隔日未练重新起算。
 * migrate：M7 升级首启将旧库（daily_practice）整库搬入新库；目标库 KEY_MIGRATED
 * 标记保证幂等（避免每次启动建/删空旧库）。
 * 纯本地统计，零上传（与零网络权限一致）。
 */

import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

/** 每日一练持久化快照（UI 展开用；全字段物化，避免版本漂移）。 */
export class DailyState {
  hasConfig: boolean = false;
  lastDate: string = '';
  streak: number = 0;
  typeIds: string[] = [];
  count: number = 50;
  columns: number = 3;
  headerOn: boolean = true;
  answerOn: boolean = true;
  sets: number = 1;
}

export class DailyStore {
  private static readonly KEY_HAS_CFG: string = 'has_cfg';
  private static readonly KEY_LAST_DATE: string = 'last_date';
  private static readonly KEY_STREAK: string = 'streak';
  private static readonly KEY_TYPE_IDS: string = 'type_ids';
  private static readonly KEY_COUNT: string = 'count';
  private static readonly KEY_COLUMNS: string = 'columns';
  private static readonly KEY_HEADER: string = 'header_on';
  private static readonly KEY_ANSWER: string = 'answer_on';
  private static readonly KEY_SETS: string = 'sets';
  /** 迁移完成标记（存目标库；旧库删除后仍可判定，防止重复建/删空旧库）。 */
  private static readonly KEY_MIGRATED: string = 'migrated_from_legacy';

  /** ms → yyyy-MM-dd（本地时区，打卡判定基准）。 */
  static fmtDay(ms: number): string {
    const d: Date = new Date(ms);
    const m: string = d.getMonth() + 1 < 10 ? `0${d.getMonth() + 1}` : `${d.getMonth() + 1}`;
    const day: string = d.getDate() < 10 ? `0${d.getDate()}` : `${d.getDate()}`;
    return `${d.getFullYear()}-${m}-${day}`;
  }

  private static async open(context: Context, storeName: string): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, storeName);
  }

  /** 读取持久化快照（无记录时返回全默认值，hasConfig=false）。 */
  static async load(context: Context, storeName: string): Promise<DailyState> {
    const s: DailyState = new DailyState();
    try {
      const p: preferences.Preferences = await DailyStore.open(context, storeName);
      s.hasConfig = p.getSync(DailyStore.KEY_HAS_CFG, false) as boolean;
      s.lastDate = p.getSync(DailyStore.KEY_LAST_DATE, '') as string;
      s.streak = p.getSync(DailyStore.KEY_STREAK, 0) as number;
      const csv: string = p.getSync(DailyStore.KEY_TYPE_IDS, '') as string;
      if (csv !== '') {
        s.typeIds = csv.split(',');
      }
      s.count = p.getSync(DailyStore.KEY_COUNT, 50) as number;
      s.columns = p.getSync(DailyStore.KEY_COLUMNS, 3) as number;
      s.headerOn = p.getSync(DailyStore.KEY_HEADER, true) as boolean;
      s.answerOn = p.getSync(DailyStore.KEY_ANSWER, true) as boolean;
      s.sets = p.getSync(DailyStore.KEY_SETS, 1) as number;
    } catch (e) {
      // 读取失败按无记录处理，不阻断生成主流程
    }
    return s;
  }

  /** 记录一次生成：刷新打卡（见类注释语义）并物化本次配置，返回最新快照。 */
  static async record(context: Context, storeName: string, typeIds: string[], count: number,
                      columns: number, headerOn: boolean, answerOn: boolean,
                      sets: number): Promise<DailyState> {
    const s: DailyState = new DailyState();
    s.hasConfig = typeIds.length > 0;
    s.typeIds = typeIds.slice();
    s.count = count;
    s.columns = columns;
    s.headerOn = headerOn;
    s.answerOn = answerOn;
    s.sets = sets;
    try {
      const p: preferences.Preferences = await DailyStore.open(context, storeName);
      const lastDate: string = p.getSync(DailyStore.KEY_LAST_DATE, '') as string;
      const prevStreak: number = p.getSync(DailyStore.KEY_STREAK, 0) as number;
      const today: string = DailyStore.fmtDay(Date.now());
      if (lastDate === today) {
        s.streak = prevStreak > 0 ? prevStreak : 1;
      } else {
        const yesterday: string = DailyStore.fmtDay(Date.now() - 86400000);
        s.streak = lastDate === yesterday ? prevStreak + 1 : 1;
      }
      s.lastDate = today;
      p.putSync(DailyStore.KEY_HAS_CFG, s.hasConfig);
      p.putSync(DailyStore.KEY_LAST_DATE, s.lastDate);
      p.putSync(DailyStore.KEY_STREAK, s.streak);
      p.putSync(DailyStore.KEY_TYPE_IDS, s.typeIds.join(','));
      p.putSync(DailyStore.KEY_COUNT, s.count);
      p.putSync(DailyStore.KEY_COLUMNS, s.columns);
      p.putSync(DailyStore.KEY_HEADER, s.headerOn);
      p.putSync(DailyStore.KEY_ANSWER, s.answerOn);
      p.putSync(DailyStore.KEY_SETS, s.sets);
      p.flush().catch(() => {
      });
    } catch (e) {
      // 写入失败不影响本次生成，仅打卡/记忆不更新
      s.streak = 0;
      s.lastDate = '';
    }
    return s;
  }

  private static copyKey(src: preferences.Preferences, dest: preferences.Preferences,
                         key: string): void {
    if (src.hasSync(key)) {
      const v: preferences.ValueType = src.getSync(key, '');
      dest.putSync(key, v);
    }
  }

  /**
   * 旧打卡库 → 新库整库搬迁（M7 升级首启）：
   * 仅当旧库有记录且新库无记录时拷贝（新库已有数据不回退覆盖）；
   * 成功后置新库 KEY_MIGRATED 并删除旧库；幂等——已迁移则直接返回。
   */
  static async migrate(context: Context, fromName: string, toName: string): Promise<void> {
    try {
      const dest: preferences.Preferences = await DailyStore.open(context, toName);
      if (dest.getSync(DailyStore.KEY_MIGRATED, false) as boolean) {
        return;
      }
      const src: preferences.Preferences = await DailyStore.open(context, fromName);
      const srcHas: boolean = src.getSync(DailyStore.KEY_HAS_CFG, false) as boolean;
      const destHas: boolean = dest.getSync(DailyStore.KEY_HAS_CFG, false) as boolean;
      if (srcHas && !destHas) {
        DailyStore.copyKey(src, dest, DailyStore.KEY_HAS_CFG);
        DailyStore.copyKey(src, dest, DailyStore.KEY_LAST_DATE);
        DailyStore.copyKey(src, dest, DailyStore.KEY_STREAK);
        DailyStore.copyKey(src, dest, DailyStore.KEY_TYPE_IDS);
        DailyStore.copyKey(src, dest, DailyStore.KEY_COUNT);
        DailyStore.copyKey(src, dest, DailyStore.KEY_COLUMNS);
        DailyStore.copyKey(src, dest, DailyStore.KEY_HEADER);
        DailyStore.copyKey(src, dest, DailyStore.KEY_ANSWER);
        DailyStore.copyKey(src, dest, DailyStore.KEY_SETS);
      }
      dest.putSync(DailyStore.KEY_MIGRATED, true);
      await dest.flush();
      preferences.deletePreferences(context, fromName).catch(() => {
        // 旧库删除失败留置（不影响新库已生效），下次不再重试（KEY_MIGRATED 已置位）
      });
    } catch (e) {
      // 迁移失败下次启动重试（KEY_MIGRATED 未置位）
    }
  }
}
