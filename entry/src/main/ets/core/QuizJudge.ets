/**
 * 在线作答判分核心（计划 §5.5）：从物化题面/答案文本推导期望答案并判分。
 *
 * - 纯函数（无 I/O、无状态）：全部历史卷免迁移即可在线作答；
 * - 推导协议与 SheetModel.answerText 生成规则一一对应：
 *   非填空 a = q + ' ' + 结果 → 取 q 后缀；
 *   填空 a = q.replace('□', 值) → 从 □ 位起在 a 中扫描连续数字；
 * - 判分数值比较（容忍前导零），非数字输入拒绝（键盘仅产数字，兜底防御）。
 */

export class QuizJudge {
  /** 输入答案最大位数（口算结果防护，防误触长串）。 */
  static readonly MAX_INPUT_LEN: number = 6;

  /** 数字文本判定（判分数值化前置校验）。 */
  private static readonly DIGIT_RE: RegExp = /^\d+$/;

  /**
   * 期望答案（数字文本）。
   * - 非填空：a 以 q + ' ' 开头 → 空格后即答案；
   * - 填空：q 含 '□' → a 同位置起扫描连续数字；
   * - 兜底：a 最后一个空格分隔 token（历史脏数据容忍）。
   */
  static expectedAnswerOf(q: string, a: string): string {
    if (q.length > 0 && a.length > q.length + 1 && a.indexOf(q + ' ') === 0) {
      return a.substring(q.length + 1).trim();
    }
    const box: number = q.indexOf('□');
    if (box >= 0 && box < a.length) {
      let end: number = box;
      while (end < a.length && a.charAt(end) >= '0' && a.charAt(end) <= '9') {
        end++;
      }
      if (end > box) {
        return a.substring(box, end);
      }
    }
    const parts: string[] = a.trim().split(' ');
    return parts.length > 0 ? parts[parts.length - 1] : '';
  }

  /** 判分：先文本相等，再数值比较（容忍前导零）；任一非纯数字拒绝。 */
  static isCorrect(input: string, expected: string): boolean {
    const x: string = input.trim();
    const y: string = expected.trim();
    if (x === y) {
      return true;
    }
    if (x.length === 0 || y.length === 0) {
      return false;
    }
    if (QuizJudge.DIGIT_RE.test(x) && QuizJudge.DIGIT_RE.test(y)) {
      return parseInt(x) === parseInt(y);
    }
    return false;
  }
}
