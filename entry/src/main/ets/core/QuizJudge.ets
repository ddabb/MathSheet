/**
 * 在线作答判分核心（计划 §5.5；1.0.1 M3 小数/负号、M8 竖式）：从物化题面/答案文本推导期望答案并判分。
 *
 * - 纯函数（无 I/O、无状态）：全部历史卷免迁移即可在线作答；
 * - 推导协议与 SheetModel 生成规则一一对应：
 *   竖式 q 以换行结尾且 a = q + 结果 → 去前缀取结果（M8，须最先判定）；
 *   非填空 a = q + ' ' + 结果 → 取 q 后缀；
 *   填空 a = q.replace('□', 值) → 从 □ 位起在 a 中扫描连续数字；
 * - 判分数值比较（容忍前导零/小数/负号），非数字输入拒绝（键盘兜底防御）。
 */

export class QuizJudge {
  /** 输入答案最大位数（口算结果防护，防误触长串）。 */
  static readonly MAX_INPUT_LEN: number = 6;

  /** 数字文本判定（判分数值化前置校验；支持小数与负号，'−' 为键盘负号 U+2212）。 */
  private static readonly NUM_RE: RegExp = /^[−-]?\d+(\.\d+)?$/;

  /**
   * 期望答案（数字文本）。
   * - 竖式：q 以 '\n' 结尾且 a 以 q 为前缀 → q 后缀即结果（M8）；
   * - 非填空：a 以 q + ' ' 开头 → 空格后即答案；
   * - 填空：q 含 '□' → a 同位置起扫描连续数字；
   * - 兜底：a 最后一个空格分隔 token（历史脏数据容忍）。
   */
  static expectedAnswerOf(q: string, a: string): string {
    if (q.length > 0 && q.charAt(q.length - 1) === '\n' && a.indexOf(q) === 0
      && a.length > q.length) {
      return a.substring(q.length).trim();
    }
    if (q.length > 0 && a.length > q.length + 1 && a.indexOf(q + ' ') === 0) {
      return a.substring(q.length + 1).trim();
    }
    const box: number = q.indexOf('□');
    if (box >= 0 && box < a.length) {
      // 挖位扫描：连续数字 + 至多一个内嵌小数点（1.0.1 M8 一位小数填空，如 "2.8"）
      let end: number = box;
      let dotUsed: boolean = false;
      while (end < a.length) {
        const ch: string = a.charAt(end);
        if (ch >= '0' && ch <= '9') {
          end++;
        } else if (ch === '.' && !dotUsed && end > box && end + 1 < a.length
          && a.charAt(end + 1) >= '0' && a.charAt(end + 1) <= '9') {
          dotUsed = true;
          end++;
        } else {
          break;
        }
      }
      if (end > box) {
        return a.substring(box, end);
      }
    }
    const parts: string[] = a.trim().split(' ');
    return parts.length > 0 ? parts[parts.length - 1] : '';
  }

  /** 键盘负号（U+2212）转 ASCII，供 parseFloat 解析。 */
  private static toAsciiMinus(s: string): string {
    return s.replace(new RegExp('−', 'g'), '-');
  }

  /** 判分：先文本相等，再数值比较（容忍前导零/小数/负号）；任一非数字拒绝。 */
  static isCorrect(input: string, expected: string): boolean {
    const x: string = input.trim();
    const y: string = expected.trim();
    if (x === y) {
      return true;
    }
    if (x.length === 0 || y.length === 0) {
      return false;
    }
    if (QuizJudge.NUM_RE.test(x) && QuizJudge.NUM_RE.test(y)) {
      return parseFloat(QuizJudge.toAsciiMinus(x)) === parseFloat(QuizJudge.toAsciiMinus(y));
    }
    return false;
  }
}
