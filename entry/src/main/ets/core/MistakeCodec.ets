/**
 * M4 错题本物化编解码（计划 §6.4）：错题 = 题面 + 答案 + 来源卷引用 + 标记时间。
 *
 * - 物化存储：错题不随历史卷删除而失效、不随版本演进变题；
 * - 重练卷"同类新题"依据 p（presetId，随物化题目一并入库）；
 * - 纯函数：JSON 文本 ↔ 数据类互转，脏数据容忍（非法条目剔除）。
 */

/** 错题条目（srcId/srcTitle = 来源卷引用；wrongCount = 重复出错严重度指示）。 */
export class MistakeEntry {
  key: string;
  q: string;
  a: string;
  /** 题型溯源（presetId）。 */
  p: string;
  srcId: string;
  srcTitle: string;
  wrongCount: number;
  lastWrongAt: number;

  constructor(key: string, q: string, a: string, p: string,
              srcId: string, srcTitle: string, wrongCount: number, lastWrongAt: number) {
    this.key = key;
    this.q = q;
    this.a = a;
    this.p = p;
    this.srcId = srcId;
    this.srcTitle = srcTitle;
    this.wrongCount = wrongCount;
    this.lastWrongAt = lastWrongAt;
  }
}

export class MistakeCodec {
  private static str(v: Object | undefined, d: string): string {
    return typeof v === 'string' ? v : d;
  }

  private static num(v: Object | undefined, d: number): number {
    return typeof v === 'number' ? v : d;
  }

  private static rec(v: Object): Record<string, Object> {
    return v as Record<string, Object>;
  }

  private static arr(v: Object | undefined): Object[] {
    if (v !== undefined && Array.isArray(v)) {
      return v as Object[];
    }
    return [];
  }

  static toJson(entries: MistakeEntry[]): string {
    const arr: Object[] = [];
    for (const e of entries) {
      const o: Record<string, Object> = {
        'key': e.key,
        'q': e.q,
        'a': e.a,
        'p': e.p,
        'srcId': e.srcId,
        'srcTitle': e.srcTitle,
        'wrongCount': e.wrongCount,
        'lastWrongAt': e.lastWrongAt
      };
      arr.push(o);
    }
    return JSON.stringify(arr);
  }

  static fromJson(text: string): MistakeEntry[] {
    let root: Object;
    try {
      root = JSON.parse(text);
    } catch (e) {
      return [];
    }
    const out: MistakeEntry[] = [];
    for (const el of MistakeCodec.arr(root)) {
      const r: Record<string, Object> = MistakeCodec.rec(el);
      const key: string = MistakeCodec.str(r['key'], '');
      const q: string = MistakeCodec.str(r['q'], '');
      if (key === '' || q === '') {
        continue;
      }
      out.push(new MistakeEntry(key, q, MistakeCodec.str(r['a'], ''),
        MistakeCodec.str(r['p'], ''), MistakeCodec.str(r['srcId'], ''),
        MistakeCodec.str(r['srcTitle'], ''),
        Math.max(1, MistakeCodec.num(r['wrongCount'], 1)),
        MistakeCodec.num(r['lastWrongAt'], 0)));
    }
    return out;
  }
}
