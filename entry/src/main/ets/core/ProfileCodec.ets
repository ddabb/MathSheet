/**
 * M7 家庭成员档案（计划 §5.3）：成员档案 / 索引 / 存储作用域（纯逻辑层）。
 *
 * - 本地档案非账号：Profile { id, name, grade, createdAt }，无登录无云端；
 * - ProfileCodec 纯函数：索引 JSON 编解码（脏容忍：非法条目剔除、currentId 失效回落首位）
 *   + 昵称钳制（≤ 6 Unicode 码点，代理对安全，emoji 记 1 码点）；
 * - MemberScope：存储作用域（baseDir 参数化）——SheetStore/MistakeStore/DailyStore
 *   按 scope 定位数据，成员间卷库/错题本物理隔离；
 * - 成员上限 MAX_MEMBERS = 6（6 × 9MB < 54MB，沙箱无压力）。
 */

/** 成员档案（昵称 + 年级锚点；表单默认值随成员）。 */
export class Profile {
  id: string;
  name: string;
  grade: number;
  createdAt: number;

  constructor(id: string, name: string, grade: number, createdAt: number) {
    this.id = id;
    this.name = name;
    this.grade = grade;
    this.createdAt = createdAt;
  }
}

/** 成员索引（currentId = 当前成员；解析层保证其恒指向有效成员）。 */
export class ProfileIndex {
  currentId: string;
  members: Profile[];

  constructor(currentId: string, members: Profile[]) {
    this.currentId = currentId;
    this.members = members;
  }
}

/** 存储作用域：成员数据根目录（卷库/错题本挂其下）。 */
export class MemberScope {
  baseDir: string;

  constructor(baseDir: string) {
    this.baseDir = baseDir;
  }
}

export class ProfileCodec {
  static readonly MAX_MEMBERS: number = 6;
  static readonly MAX_NAME_CP: number = 6;
  static readonly DEFAULT_ID: string = 'default';

  // ---------- 类型收窄辅助（避免散落的 as 断言） ----------

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

  // ---------- 昵称 / 年级钳制 ----------

  /** 截断到最多 6 个 Unicode 码点（代理对安全）。 */
  static cutName(raw: string): string {
    let out: string = '';
    let cp: number = 0;
    for (let i: number = 0; i < raw.length && cp < ProfileCodec.MAX_NAME_CP;) {
      const c: number | undefined = raw.codePointAt(i);
      if (c === undefined) {
        break;
      }
      out += String.fromCodePoint(c);
      i += c > 0xFFFF ? 2 : 1;
      cp++;
    }
    return out;
  }

  /** 昵称规整：去首尾空白 + 截断 6 码点。 */
  static clampName(raw: string): string {
    return ProfileCodec.cutName(raw.trim());
  }

  /** 年级钳制：非法值回 2（默认主场景）。 */
  static clampGrade(g: number): number {
    return g === 1 || g === 3 ? g : 2;
  }

  // ---------- 查找 ----------

  static findById(idx: ProfileIndex, id: string): Profile | null {
    for (const m of idx.members) {
      if (m.id === id) {
        return m;
      }
    }
    return null;
  }

  // ---------- 索引编解码（profiles.json） ----------

  static indexToJson(idx: ProfileIndex): string {
    const arr: Object[] = [];
    for (const m of idx.members) {
      const o: Record<string, Object> = {
        'id': m.id,
        'name': m.name,
        'grade': m.grade,
        'createdAt': m.createdAt
      };
      arr.push(o);
    }
    const root: Record<string, Object> = {
      'currentId': idx.currentId,
      'members': arr as Object
    };
    return JSON.stringify(root);
  }

  /** 解析索引（脏容忍：JSON 损坏/条目缺 id 或名剔除/重复 id 去重/currentId 失效回落首位）。 */
  static indexFromJson(text: string): ProfileIndex {
    let root: Object;
    try {
      root = JSON.parse(text);
    } catch (e) {
      return new ProfileIndex('', []);
    }
    const r: Record<string, Object> = ProfileCodec.rec(root);
    const members: Profile[] = [];
    const seen: Set<string> = new Set<string>();
    for (const el of ProfileCodec.arr(r['members'])) {
      const mr: Record<string, Object> = ProfileCodec.rec(el);
      const id: string = ProfileCodec.str(mr['id'], '');
      const name: string = ProfileCodec.clampName(ProfileCodec.str(mr['name'], ''));
      if (id === '' || name === '' || seen.has(id)) {
        continue;
      }
      seen.add(id);
      members.push(new Profile(id, name,
        ProfileCodec.clampGrade(ProfileCodec.num(mr['grade'], 2)),
        ProfileCodec.num(mr['createdAt'], 0)));
    }
    if (members.length === 0) {
      return new ProfileIndex('', []);
    }
    const cur: string = ProfileCodec.str(r['currentId'], '');
    let hit: boolean = false;
    for (const m of members) {
      if (m.id === cur) {
        hit = true;
        break;
      }
    }
    return new ProfileIndex(hit ? cur : members[0].id, members);
  }
}
