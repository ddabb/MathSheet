/**
 * M3 卷库物化编解码（计划 §6.4 关键技术点③：物化存储防版本漂移）。
 *
 * - 卷库存**物化题目**（题面 + 答案 + 批改状态 + 题型溯源），而非 (spec, seed) 引用
 *   ——生成算法演进不会导致历史卷"重开变题/批改错位"；
 * - 纯函数（无 I/O）：JSON 文本 ↔ 数据类互转，黄金用例离线直测；
 * - 脏数据容忍：字段缺失回默认值、marks 与 items 长度对齐、非法条目剔除；
 * - 体积预算：单卷 ≤ 16KB（200 题 × ~80B 实测，短键 q/a/key/p；
 *   MAX_SHEETS=500 上限下卷库总体积 ≤ 8MB，filesDir 配额内）。
 */

/** 物化题目：题面 + 答案 + 去重键 + 题型溯源（p = presetId，错题重练依据）。 */
export class StoredItem {
  q: string;
  a: string;
  key: string;
  p: string;

  constructor(q: string, a: string, key: string, p: string) {
    this.q = q;
    this.a = a;
    this.key = key;
    this.p = p;
  }
}

/** 物化卷（§6.4：全字段物化；marks 与 items 一一对应，0=未批 1=对 2=错）。 */
export class StoredSheet {
  id: string;
  createdAt: number;
  title: string;
  grade: number;
  typeIds: string[];
  count: number;
  columns: number;
  headerOn: boolean;
  answerOn: boolean;
  seed: number;
  items: StoredItem[];
  marks: number[];

  constructor(id: string, createdAt: number, title: string, grade: number,
              typeIds: string[], count: number, columns: number,
              headerOn: boolean, answerOn: boolean, seed: number,
              items: StoredItem[], marks: number[]) {
    this.id = id;
    this.createdAt = createdAt;
    this.title = title;
    this.grade = grade;
    this.typeIds = typeIds;
    this.count = count;
    this.columns = columns;
    this.headerOn = headerOn;
    this.answerOn = answerOn;
    this.seed = seed;
    this.items = items;
    this.marks = marks;
  }
}

/** 卷库列表元数据（索引文件条目：列表渲染只读索引，不载入整卷）。 */
export class StoredMeta {
  id: string;
  createdAt: number;
  title: string;
  grade: number;
  count: number;
  gradedCount: number;
  wrongCount: number;

  constructor(id: string, createdAt: number, title: string, grade: number,
              count: number, gradedCount: number, wrongCount: number) {
    this.id = id;
    this.createdAt = createdAt;
    this.title = title;
    this.grade = grade;
    this.count = count;
    this.gradedCount = gradedCount;
    this.wrongCount = wrongCount;
  }
}

export class SheetCodec {
  /** 批改状态枚举值（历史 JSON 兼容依赖，冻结勿改）。 */
  static readonly MARK_NONE: number = 0;
  static readonly MARK_RIGHT: number = 1;
  static readonly MARK_WRONG: number = 2;

  // ---------- 类型收窄辅助（避免散落的 as 断言） ----------

  private static str(v: Object | undefined, d: string): string {
    return typeof v === 'string' ? v : d;
  }

  private static num(v: Object | undefined, d: number): number {
    return typeof v === 'number' ? v : d;
  }

  private static bool(v: Object | undefined, d: boolean): boolean {
    return typeof v === 'boolean' ? v : d;
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

  // ---------- 统计（纯函数） ----------

  /** 已批数（marks ≠ 0 的数量）。 */
  static gradedCountOf(sheet: StoredSheet): number {
    let n: number = 0;
    for (const m of sheet.marks) {
      if (m !== SheetCodec.MARK_NONE) {
        n++;
      }
    }
    return n;
  }

  /** 错题数（marks = MARK_WRONG 的数量）。 */
  static wrongCountOf(sheet: StoredSheet): number {
    let n: number = 0;
    for (const m of sheet.marks) {
      if (m === SheetCodec.MARK_WRONG) {
        n++;
      }
    }
    return n;
  }

  static metaOf(sheet: StoredSheet): StoredMeta {
    return new StoredMeta(sheet.id, sheet.createdAt, sheet.title, sheet.grade,
      sheet.count, SheetCodec.gradedCountOf(sheet), SheetCodec.wrongCountOf(sheet));
  }

  // ---------- 整卷编解码（sheets/{id}.json） ----------

  static sheetToJson(sheet: StoredSheet): string {
    const root: Record<string, Object> = {
      'id': sheet.id,
      'createdAt': sheet.createdAt,
      'title': sheet.title,
      'grade': sheet.grade,
      'typeIds': sheet.typeIds as Object,
      'count': sheet.count,
      'columns': sheet.columns,
      'headerOn': sheet.headerOn,
      'answerOn': sheet.answerOn,
      'seed': sheet.seed,
      'items': sheet.items as Object,
      'marks': sheet.marks as Object
    };
    return JSON.stringify(root);
  }

  /** 解析整卷（脏数据容忍：字段缺失回默认、marks 长度对齐 items、无有效 id 返回 null）。 */
  static sheetFromJson(text: string): StoredSheet | null {
    let root: Object;
    try {
      root = JSON.parse(text);
    } catch (e) {
      return null;
    }
    const r: Record<string, Object> = SheetCodec.rec(root);
    const id: string = SheetCodec.str(r['id'], '');
    if (id === '') {
      return null;
    }
    const typeIds: string[] = [];
    for (const t of SheetCodec.arr(r['typeIds'])) {
      const s: string = SheetCodec.str(t, '');
      if (s !== '') {
        typeIds.push(s);
      }
    }
    const items: StoredItem[] = [];
    for (const el of SheetCodec.arr(r['items'])) {
      const ir: Record<string, Object> = SheetCodec.rec(el);
      const q: string = SheetCodec.str(ir['q'], '');
      const a: string = SheetCodec.str(ir['a'], '');
      const key: string = SheetCodec.str(ir['key'], '');
      if (q === '' || key === '') {
        continue;
      }
      items.push(new StoredItem(q, a, key, SheetCodec.str(ir['p'], '')));
    }
    const marks: number[] = [];
    const rawMarks: Object[] = SheetCodec.arr(r['marks']);
    for (let i = 0; i < items.length; i++) {
      const m: number = SheetCodec.num(i < rawMarks.length ? rawMarks[i] : undefined,
        SheetCodec.MARK_NONE);
      marks.push(m === SheetCodec.MARK_RIGHT || m === SheetCodec.MARK_WRONG ? m : SheetCodec.MARK_NONE);
    }
    return new StoredSheet(id, SheetCodec.num(r['createdAt'], 0),
      SheetCodec.str(r['title'], ''), SheetCodec.num(r['grade'], 0),
      typeIds, SheetCodec.num(r['count'], items.length), SheetCodec.num(r['columns'], 3),
      SheetCodec.bool(r['headerOn'], true), SheetCodec.bool(r['answerOn'], true),
      SheetCodec.num(r['seed'], 0), items, marks);
  }

  // ---------- 索引编解码（sheets/index.json，最新在前） ----------

  static metaListToJson(metas: StoredMeta[]): string {
    const arr: Object[] = [];
    for (const m of metas) {
      const o: Record<string, Object> = {
        'id': m.id,
        'createdAt': m.createdAt,
        'title': m.title,
        'grade': m.grade,
        'count': m.count,
        'gradedCount': m.gradedCount,
        'wrongCount': m.wrongCount
      };
      arr.push(o);
    }
    return JSON.stringify(arr);
  }

  static metaListFromJson(text: string): StoredMeta[] {
    let root: Object;
    try {
      root = JSON.parse(text);
    } catch (e) {
      return [];
    }
    const out: StoredMeta[] = [];
    for (const el of SheetCodec.arr(root)) {
      const r: Record<string, Object> = SheetCodec.rec(el);
      const id: string = SheetCodec.str(r['id'], '');
      if (id === '') {
        continue;
      }
      out.push(new StoredMeta(id, SheetCodec.num(r['createdAt'], 0),
        SheetCodec.str(r['title'], ''), SheetCodec.num(r['grade'], 0),
        SheetCodec.num(r['count'], 0), SheetCodec.num(r['gradedCount'], 0),
        SheetCodec.num(r['wrongCount'], 0)));
    }
    return out;
  }
}
