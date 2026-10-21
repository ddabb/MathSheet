/**
 * 路由参数模型（共享类型声明一次，Index → PreviewPage 传递）。
 * 参数即生成配置（同参数 + 同种子 = 同卷），PreviewPage 按参数确定性重建。
 */

export interface PreviewParams {
  /** 勾选的题型预设 id 列表（GradePresets ENTRIES 的 id）。 */
  typeIds: string[];
  /** 生成种子（换一批 = 新种子）。 */
  seed: number;
  /** 题数。 */
  count: number;
  /** 列数（2/3/4）。 */
  columns: number;
  /** 首页题头开关。 */
  headerOn: boolean;
  /** 答案页开关（末页红色答案）。 */
  answerOn: boolean;
  /** 同构卷套数（1/2/4，A/B/C/D 卷，种子 = seed..seed+sets-1）。 */
  sets: number;
  /**
   * M3 卷库重开模式：传入即从卷库加载该卷（物化题目，不重生成、隐藏换一批）；
   * 缺省 = 新鲜生成模式（参数 + 种子确定性重建，生成即入库）。
   * 卷库模式仅消费 sheetId，其余字段由调用方传占位值。
   */
  sheetId?: string;
}

/** M4 批改页路由参数（Index 卷库卡片 → 批改）。 */
export interface GradeParams {
  sheetId: string;
}
