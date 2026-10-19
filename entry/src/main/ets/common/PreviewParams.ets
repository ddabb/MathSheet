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
}
