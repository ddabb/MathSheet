/**
 * M3/M4 测试套件（sheetM34Test）——卷库物化 / 错题本 / 重练卷 / PDF 合成：
 *   - SheetCodec 黄金 JSON + 脏数据容忍 + 统计；
 *   - MistakeCodec 全字段往返 + wrongCount 钳制；
 *   - buildMultiSheetTraced 溯源轮转 + MistakeDrill 1:2 混编/复现/上限/空防御；
 *   - SheetStore 持久化全生命周期（save/load/update/remove/容量淘汰，真 Context I/O）；
 *   - MistakeStore commitSheet 幂等协议（改判不堆叠/跨卷合并/容量淘汰）；
 *   - PdfCodec A4 合成冒烟（PixelMap→PNG→PDF：%PDF- 头 + %%EOF 尾；
 *     x86 模拟器无 PDF Kit 时断言优雅降级——false/无产物/不崩）。
 *
 * 运行协议（模拟器 class 过滤定向跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class sheetM34Test -s timeout 30000
 */
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { StoredItem, StoredSheet, StoredMeta, SheetCodec } from '../../../main/ets/core/SheetCodec';
import { MistakeEntry, MistakeCodec } from '../../../main/ets/core/MistakeCodec';
import { MistakeDrill } from '../../../main/ets/core/MistakeDrill';
import { SheetStore } from '../../../main/ets/core/SheetStore';
import { MistakeStore } from '../../../main/ets/core/MistakeStore';
import { MemberScope } from '../../../main/ets/core/ProfileCodec';
import { PdfCodec } from '../../../main/ets/core/PdfCodec';
import { QuizJudge } from '../../../main/ets/core/QuizJudge';
import { pdfService } from '@kit.PDFKit';
import { SheetGen } from '../../../main/ets/core/SheetGen';
import { GradePresets, PresetEntry } from '../../../main/ets/core/GradePresets';

/** 测试用应用级 Context（entry_test 与主 ability 分区隔离，测试数据不污染真实卷库）。 */
function ctxOf(): Context {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
}

/** 构造测试 StoredSheet（固定 createdAt，字段可断言）。 */
function sheetOf(id: string, title: string, items: StoredItem[], marks: number[]): StoredSheet {
  return new StoredSheet(id, 1700000000000, title, 2, [], items.length, 3, true, true, 42, items, marks);
}

/** 构造测试 StoredItem（q/a/key/p 可预期）。 */
function itemOf(i: number): StoredItem {
  return new StoredItem(`q${i} =`, `q${i} = ${i}`, `k${i}`, 'pX');
}

/** 只统计本套件写入的条目（id 前缀过滤，防历史残留干扰计数）。 */
function countMine(metas: StoredMeta[], prefix: string): number {
  let n: number = 0;
  for (const m of metas) {
    if (m.id.indexOf(prefix) === 0) {
      n++;
    }
  }
  return n;
}

export default function sheetM34Test() {
  describe('sheetM34Test', () => {
    // ---- SheetCodec 黄金 JSON + 脏数据容忍 + 统计 ----
    it('SheetCodec_goldenAndDirty', 0, () => {
      const items: StoredItem[] = [
        new StoredItem('23 + 15 =', '23 + 15 = 38', '15+23', 'g2_add_100'),
        new StoredItem('6 \u00d7 7 =', '6 \u00d7 7 = 42', '6\u00d77', 'g2_mul_table')
      ];
      const sheet: StoredSheet = new StoredSheet('s1', 1700000000000, '二年级口算（A卷）', 2,
        ['g2_add_100', 'g2_mul_table'], 2, 3, true, true, 42, items, [1, 2]);
      const golden: string = '{"id":"s1","createdAt":1700000000000,"title":"二年级口算（A卷）","grade":2'
        + ',"typeIds":["g2_add_100","g2_mul_table"],"count":2,"columns":3,"headerOn":true,"answerOn":true'
        + ',"seed":42,"items":[{"q":"23 + 15 =","a":"23 + 15 = 38","key":"15+23","p":"g2_add_100"}'
        + ',{"q":"6 \u00d7 7 =","a":"6 \u00d7 7 = 42","key":"6\u00d77","p":"g2_mul_table"}],"marks":[1,2]}';
      expect(SheetCodec.sheetToJson(sheet)).assertEqual(golden);
      const back: StoredSheet | null = SheetCodec.sheetFromJson(golden);
      expect(back !== null).assertTrue();
      if (back !== null) {
        expect(back.id).assertEqual('s1');
        expect(back.title).assertEqual('二年级口算（A卷）');
        expect(back.items.length).assertEqual(2);
        expect(back.items[0].p).assertEqual('g2_add_100');
        expect(back.marks[0]).assertEqual(1);
        expect(back.marks[1]).assertEqual(2);
        expect(back.columns).assertEqual(3);
        expect(back.seed).assertEqual(42);
      }
      // 脏数据
      expect(SheetCodec.sheetFromJson('{oops') === null).assertTrue();
      expect(SheetCodec.sheetFromJson('{"title":"x"}') === null).assertTrue();
      const dirty: string = '{"id":"d1","items":[{"q":"1 + 1 =","key":"1+1"},{"q":"bad"},'
        + '{"q":"2 + 2 =","key":"2+2","a":"2 + 2 = 4"}],"marks":[7]}';
      const d: StoredSheet | null = SheetCodec.sheetFromJson(dirty);
      expect(d !== null).assertTrue();
      if (d !== null) {
        expect(d.items.length).assertEqual(2);
        expect(d.marks.length).assertEqual(2);
        expect(d.marks[0]).assertEqual(0);
        expect(d.marks[1]).assertEqual(0);
        expect(d.count).assertEqual(2);
        expect(d.headerOn).assertTrue();
      }
      // 统计 + 索引
      expect(SheetCodec.gradedCountOf(sheet)).assertEqual(2);
      expect(SheetCodec.wrongCountOf(sheet)).assertEqual(1);
      const meta: StoredMeta = SheetCodec.metaOf(sheet);
      expect(meta.gradedCount).assertEqual(2);
      expect(meta.wrongCount).assertEqual(1);
      const metas: StoredMeta[] = [meta, new StoredMeta('s2', 1, 'B', 1, 5, 0, 0)];
      const backList: StoredMeta[] = SheetCodec.metaListFromJson(SheetCodec.metaListToJson(metas));
      expect(backList.length).assertEqual(2);
      expect(backList[0].id).assertEqual('s1');
      expect(backList[1].title).assertEqual('B');
      expect(SheetCodec.metaListFromJson('nope').length).assertEqual(0);
      expect(SheetCodec.metaListFromJson('[{"title":"x"},{"id":"ok"}]').length).assertEqual(1);
    });

    // ---- durationSec 用时字段（0 省略保黄金兼容；>0 往返） ----
    it('SheetCodec_durationRoundTrip', 0, () => {
      const sheet: StoredSheet = sheetOf('m34d0', '用时卷', [itemOf(0)], [1]);
      // 默认 0：JSON 省略字段（旧黄金不变）
      const j0: string = SheetCodec.sheetToJson(sheet);
      expect(j0.indexOf('durationSec') < 0).assertTrue();
      const back0: StoredSheet | null = SheetCodec.sheetFromJson(j0);
      expect(back0 !== null).assertTrue();
      if (back0 !== null) {
        expect(back0.durationSec).assertEqual(0);
      }
      // 设置后整卷往返 + meta 传递
      sheet.durationSec = 300;
      const j1: string = SheetCodec.sheetToJson(sheet);
      expect(j1.indexOf('"durationSec":300') >= 0).assertTrue();
      const back1: StoredSheet | null = SheetCodec.sheetFromJson(j1);
      expect(back1 !== null).assertTrue();
      if (back1 !== null) {
        expect(back1.durationSec).assertEqual(300);
      }
      const meta: StoredMeta = SheetCodec.metaOf(sheet);
      expect(meta.durationSec).assertEqual(300);
      const metas: StoredMeta[] = SheetCodec.metaListFromJson(SheetCodec.metaListToJson([meta]));
      expect(metas.length).assertEqual(1);
      expect(metas[0].durationSec).assertEqual(300);
      // meta 0 不写字段；脏数据缺字段回 0
      const meta0: StoredMeta = SheetCodec.metaOf(sheetOf('m34d1', '零', [itemOf(1)], [0]));
      expect(SheetCodec.metaListToJson([meta0]).indexOf('durationSec') < 0).assertTrue();
      const dirty: StoredSheet | null =
        SheetCodec.sheetFromJson('{"id":"m34d2","items":[{"q":"1 =","key":"k"}]}');
      expect(dirty !== null).assertTrue();
      if (dirty !== null) {
        expect(dirty.durationSec).assertEqual(0);
      }
    });

    // ---- MistakeCodec 全字段往返 + 钳制 ----
    it('MistakeCodec_roundTrip', 0, () => {
      const es: MistakeEntry[] = [
        new MistakeEntry('15+23', '23 + 15 =', '23 + 15 = 38', 'g2_add_100',
          's1', '二年级口算（A卷）', 2, 1700000000123)
      ];
      const back: MistakeEntry[] = MistakeCodec.fromJson(MistakeCodec.toJson(es));
      expect(back.length).assertEqual(1);
      expect(back[0].key).assertEqual('15+23');
      expect(back[0].q).assertEqual('23 + 15 =');
      expect(back[0].a).assertEqual('23 + 15 = 38');
      expect(back[0].p).assertEqual('g2_add_100');
      expect(back[0].srcId).assertEqual('s1');
      expect(back[0].srcTitle).assertEqual('二年级口算（A卷）');
      expect(back[0].wrongCount).assertEqual(2);
      expect(back[0].lastWrongAt).assertEqual(1700000000123);
      expect(MistakeCodec.fromJson('[').length).assertEqual(0);
      const dirty: string = '[{"key":"k1","q":"q1","wrongCount":0},{"key":"","q":"x"},'
        + '{"q":"y"},{"key":"k2","q":"q2","wrongCount":5}]';
      const d: MistakeEntry[] = MistakeCodec.fromJson(dirty);
      expect(d.length).assertEqual(2);
      expect(d[0].wrongCount).assertEqual(1);
      expect(d[1].key).assertEqual('k2');
      expect(d[1].wrongCount).assertEqual(5);
    });

    // ---- TracedItem 溯源 + MistakeDrill 1:2 混编 ----
    it('TracedAndDrill_mix', 0, () => {
      const g3add: PresetEntry | null = GradePresets.byId('g3_add_3d');
      const g3sub: PresetEntry | null = GradePresets.byId('g3_sub_3d');
      expect(g3add !== null && g3sub !== null).assertTrue();
      if (g3add !== null && g3sub !== null) {
        const traced = SheetGen.buildMultiSheetTraced([g3add, g3sub], 555, 40);
        expect(traced.items.length).assertEqual(40);
        expect(traced.duplicates).assertEqual(0);
        expect(traced.items[0].presetId).assertEqual(g3add.id);
        expect(traced.items[1].presetId).assertEqual(g3sub.id);
        expect(traced.items[39].presetId).assertEqual(g3sub.id);
        // 双错题 → 6 题（原题+2 新题 × 2）
        const m1: MistakeEntry = new MistakeEntry(traced.items[0].item.key,
          traced.items[0].item.questionText, traced.items[0].item.answerText,
          traced.items[0].presetId, 's', 'T', 1, 1);
        const m2: MistakeEntry = new MistakeEntry(traced.items[1].item.key,
          traced.items[1].item.questionText, traced.items[1].item.answerText,
          traced.items[1].presetId, 's', 'T', 1, 2);
        const items: StoredItem[] = MistakeDrill.buildItems([m1, m2], 31337, 200);
        expect(items.length).assertEqual(6);
        expect(items[0].key).assertEqual(m1.key);
        expect(items[3].key).assertEqual(m2.key);
        expect(items[1].p).assertEqual(m1.p);
        expect(items[4].p).assertEqual(m2.p);
        const keys: Set<string> = new Set<string>();
        for (const it of items) {
          keys.add(it.key);
        }
        expect(keys.size).assertEqual(6);
        // 复现 + 换种子
        const again: StoredItem[] = MistakeDrill.buildItems([m1, m2], 31337, 200);
        expect(again[1].key).assertEqual(items[1].key);
        const reseeded: StoredItem[] = MistakeDrill.buildItems([m1], 778, 200);
        expect(reseeded.length).assertEqual(3);
        expect(reseeded[0].key).assertEqual(m1.key);
        // buildSheet 组装
        const sheet: StoredSheet | null = MistakeDrill.buildSheet('d1', 9, '错题重练卷', [m1], 777, 200);
        expect(sheet !== null).assertTrue();
        if (sheet !== null) {
          expect(sheet.items.length).assertEqual(3);
          expect(sheet.marks.length).assertEqual(3);
          expect(sheet.columns).assertEqual(3);
          expect(sheet.title).assertEqual('错题重练卷');
        }
        expect(MistakeDrill.buildSheet('d2', 0, 'T', [], 1, 200) === null).assertTrue();
      }
    });

    // ---- SheetStore 持久化全生命周期（真 Context 同步 I/O） ----
    it('SheetStore_persistence', 0, () => {
      const ctx: Context = ctxOf();
      const scope: MemberScope = new MemberScope(ctx.filesDir);
      const ids: string[] = ['m34t0', 'm34t1', 'm34t2', 'm34t3', 'm34t4'];
      SheetStore.removeSheets(scope, ids); // 前置清理（历史失败残留）
      let metas: StoredMeta[] = SheetStore.loadIndex(scope);
      expect(countMine(metas, 'm34t') === 0).assertTrue();

      // 入库 2 卷
      const s1: StoredSheet = sheetOf('m34t0', '卷一', [itemOf(0), itemOf(1)], [1, 2]);
      const s2: StoredSheet = sheetOf('m34t1', '卷二', [itemOf(2)], [0]);
      SheetStore.saveSheets(scope, [s1, s2]);
      metas = SheetStore.loadIndex(scope);
      expect(countMine(metas, 'm34t')).assertEqual(2);
      const idx0: number = metas.findIndex((m: StoredMeta) => m.id === 'm34t0');
      const idx1: number = metas.findIndex((m: StoredMeta) => m.id === 'm34t1');
      expect(idx0 >= 0 && idx1 >= 0).assertTrue();
      expect(idx0 < idx1).assertTrue(); // 保存顺序保持（最新在前）
      const meta0: StoredMeta = metas[idx0];
      expect(meta0.count).assertEqual(2);
      expect(meta0.gradedCount).assertEqual(2);
      expect(meta0.wrongCount).assertEqual(1);
      expect(meta0.title).assertEqual('卷一');

      // 整卷读取往返
      const loaded: StoredSheet | null = SheetStore.loadSheet(scope, 'm34t0');
      expect(loaded !== null).assertTrue();
      if (loaded !== null) {
        expect(loaded.title).assertEqual('卷一');
        expect(loaded.items.length).assertEqual(2);
        expect(loaded.items[0].q).assertEqual('q0 =');
        expect(loaded.items[1].a).assertEqual('q1 = 1');
        expect(loaded.items[1].p).assertEqual('pX');
        expect(loaded.marks[0]).assertEqual(1);
        expect(loaded.marks[1]).assertEqual(2);
        expect(loaded.seed).assertEqual(42);
      }
      expect(SheetStore.loadSheet(scope, 'no_such_sheet') === null).assertTrue();

      // 批改更新：整卷重写 + 索引统计刷新
      const s1b: StoredSheet = sheetOf('m34t0', '卷一改', [itemOf(0), itemOf(1)], [0, 0]);
      SheetStore.updateSheet(scope, s1b);
      metas = SheetStore.loadIndex(scope);
      const m0b: StoredMeta | undefined = metas.find((m: StoredMeta) => m.id === 'm34t0');
      expect(m0b !== undefined).assertTrue();
      if (m0b !== undefined) {
        expect(m0b.gradedCount).assertEqual(0);
        expect(m0b.title).assertEqual('卷一改');
      }
      const s1r: StoredSheet | null = SheetStore.loadSheet(scope, 'm34t0');
      expect(s1r !== null).assertTrue();
      if (s1r !== null) {
        expect(s1r.marks[0]).assertEqual(0);
        expect(s1r.title).assertEqual('卷一改');
      }

      // 容量淘汰：MAX=3 存 5 卷 → 索引 3、尾部 2 卷文件删除
      SheetStore.removeSheets(scope, ids);
      const sheets: StoredSheet[] = [];
      for (let i = 0; i < 5; i++) {
        sheets.push(sheetOf(ids[i], `容量卷${i}`, [itemOf(i)], [0]));
      }
      SheetStore.MAX_SHEETS = 3;
      SheetStore.saveSheets(scope, sheets);
      SheetStore.MAX_SHEETS = 500;
      metas = SheetStore.loadIndex(scope);
      expect(countMine(metas, 'm34t')).assertEqual(3);
      expect(SheetStore.loadSheet(scope, 'm34t0') !== null).assertTrue();
      expect(SheetStore.loadSheet(scope, 'm34t2') !== null).assertTrue();
      expect(SheetStore.loadSheet(scope, 'm34t3') === null).assertTrue();
      expect(SheetStore.loadSheet(scope, 'm34t4') === null).assertTrue();

      // 单卷删除：文件与索引同步
      SheetStore.removeSheets(scope, ['m34t0']);
      metas = SheetStore.loadIndex(scope);
      expect(countMine(metas, 'm34t')).assertEqual(2);
      expect(SheetStore.loadSheet(scope, 'm34t0') === null).assertTrue();

      // 清理
      SheetStore.removeSheets(scope, ids);
      metas = SheetStore.loadIndex(scope);
      expect(countMine(metas, 'm34t') === 0).assertTrue();
    });

    // ---- MistakeStore commitSheet 幂等协议 ----
    it('MistakeStore_commitLifecycle', 0, () => {
      const ctx: Context = ctxOf();
      const scope: MemberScope = new MemberScope(ctx.filesDir);
      MistakeStore.clearAll(scope);
      expect(MistakeStore.load(scope).length).assertEqual(0);

      // 首次批改：2 错入库
      const s1: StoredSheet = sheetOf('m34s1', '批改卷一',
        [itemOf(0), itemOf(1), itemOf(2), itemOf(3), itemOf(4)], [2, 1, 0, 2, 1]);
      expect(MistakeStore.commitSheet(scope, s1)).assertEqual(2);
      let list: MistakeEntry[] = MistakeStore.load(scope);
      expect(list.length).assertEqual(2);
      expect(list[0].key).assertEqual('k0');
      expect(list[1].key).assertEqual('k3');
      expect(list[0].srcId).assertEqual('m34s1');
      expect(list[0].srcTitle).assertEqual('批改卷一');
      expect(list[0].wrongCount).assertEqual(1);

      // 幂等：重复提交同卷不堆叠
      expect(MistakeStore.commitSheet(scope, s1)).assertEqual(2);
      list = MistakeStore.load(scope);
      expect(list.length).assertEqual(2);
      expect(list[0].wrongCount).assertEqual(1);

      // 改判：错题集变化 → 旧引用移除、新错题入库
      const s1b: StoredSheet = sheetOf('m34s1', '批改卷一',
        [itemOf(0), itemOf(1), itemOf(2), itemOf(3), itemOf(4)], [1, 2, 0, 1, 1]);
      expect(MistakeStore.commitSheet(scope, s1b)).assertEqual(1);
      list = MistakeStore.load(scope);
      expect(list.length).assertEqual(1);
      expect(list[0].key).assertEqual('k1');
      expect(list[0].wrongCount).assertEqual(1);

      // 跨卷同表达式合并：wrongCount+1、来源更新为本卷
      const s2: StoredSheet = sheetOf('m34s2', '批改卷二', [itemOf(1)], [2]);
      expect(MistakeStore.commitSheet(scope, s2)).assertEqual(1);
      list = MistakeStore.load(scope);
      expect(list.length).assertEqual(1);
      expect(list[0].key).assertEqual('k1');
      expect(list[0].wrongCount).assertEqual(2);
      expect(list[0].srcId).assertEqual('m34s2');
      expect(list[0].srcTitle).assertEqual('批改卷二');

      // 容量淘汰：MAX=3 单卷 5 错 → 保留最新 3 条
      MistakeStore.MAX_MISTAKES = 3;
      const s3: StoredSheet = sheetOf('m34s3', '容量卷',
        [itemOf(10), itemOf(11), itemOf(12), itemOf(13), itemOf(14)], [2, 2, 2, 2, 2]);
      expect(MistakeStore.commitSheet(scope, s3)).assertEqual(5);
      MistakeStore.MAX_MISTAKES = 1000;
      list = MistakeStore.load(scope);
      expect(list.length).assertEqual(3);
      expect(list[0].key).assertEqual('k12');
      expect(list[1].key).assertEqual('k13');
      expect(list[2].key).assertEqual('k14');

      // 清空
      MistakeStore.clearAll(scope);
      expect(MistakeStore.load(scope).length).assertEqual(0);
    });

    // ---- QuizJudge 在线作答判分（推导协议 + 判分 + 全题型覆盖） ----
    it('QuizJudge_expectedAndJudge', 0, () => {
      // 非填空：a = q + ' ' + 结果 → 取 q 后缀
      expect(QuizJudge.expectedAnswerOf('23 + 15 =', '23 + 15 = 38')).assertEqual('38');
      expect(QuizJudge.expectedAnswerOf('(15 + 8) × 3 =', '(15 + 8) × 3 = 69')).assertEqual('69');
      // 填空：□ 位扫描（挖操作数/挖结果/多位值）
      expect(QuizJudge.expectedAnswerOf('□ + 5 = 8', '3 + 5 = 8')).assertEqual('3');
      expect(QuizJudge.expectedAnswerOf('3 + □ = 8', '3 + 5 = 8')).assertEqual('5');
      expect(QuizJudge.expectedAnswerOf('3 + 5 = □', '3 + 5 = 8')).assertEqual('8');
      expect(QuizJudge.expectedAnswerOf('□ × 3 = 36', '12 × 3 = 36')).assertEqual('12');
      // 兜底：a 最后一个空格分隔 token
      expect(QuizJudge.expectedAnswerOf('x', 'a b 42')).assertEqual('42');
      // 判分：数值比较（容忍前导零）、空/非数字拒绝
      expect(QuizJudge.isCorrect('38', '38')).assertTrue();
      expect(QuizJudge.isCorrect('069', '69')).assertTrue();
      expect(QuizJudge.isCorrect('69', '68')).assertFalse();
      expect(QuizJudge.isCorrect('', '69')).assertFalse();
      expect(QuizJudge.isCorrect('6x', '69')).assertFalse();
      expect(QuizJudge.isCorrect('0', '0')).assertTrue();
    });

    // ---- QuizJudge 全预设覆盖（生成器全部题型可推导出非空数字答案） ----
    it('QuizJudge_coversAllPresets', 0, () => {
      // 数字文本（M8 起含一位小数答案，如 '6.3'；竖式仍为纯整数）
      const digitRe: RegExp = /^\d+(\.\d+)?$/;
      for (const e of GradePresets.ENTRIES) {
        const traced = SheetGen.buildMultiSheetTraced([e], 12345, 24);
        expect(traced.items.length > 0).assertTrue();
        for (const t of traced.items) {
          const exp: string = QuizJudge.expectedAnswerOf(t.item.questionText, t.item.answerText);
          expect(exp.length > 0).assertTrue();
          expect(digitRe.test(exp)).assertTrue();
        }
      }
    });

    // ---- PdfCodec A4 合成冒烟（PixelMap → PNG → PDF 字节校验） ----
    it('PdfCodec_a4Smoke', 0, async (): Promise<void> => {
      const ctx: Context = ctxOf();
      const dir: string = ctx.filesDir + '/pdfcodec_test';
      if (fs.accessSync(dir)) {
        for (const name of fs.listFileSync(dir)) {
          fs.unlinkSync(dir + '/' + name);
        }
        fs.rmdirSync(dir);
      }
      fs.mkdirSync(dir, true);
      // 64×64 白底 PNG
      const colors: ArrayBuffer = new ArrayBuffer(64 * 64 * 4);
      const bytes: Uint8Array = new Uint8Array(colors);
      for (let i = 0; i < bytes.length; i++) {
        bytes[i] = 0xFF;
      }
      const opts: image.InitializationOptions = {
        size: { width: 64, height: 64 },
        pixelFormat: image.PixelMapFormat.RGBA_8888
      };
      const pm: image.PixelMap = await image.createPixelMap(colors, opts);
      const packer: image.ImagePacker = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
      const png: ArrayBuffer = await packer.packing(pm, packOpts);
      const pngPath: string = dir + '/page0.png';
      const wf: fs.File = fs.openSync(pngPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(wf.fd, png);
      fs.closeSync(wf);
      expect(fs.accessSync(pngPath)).assertTrue();
      // 探测 PDF Kit 运行时（官方口径：x86 模拟器不支持，arm 模拟器/真机支持）
      let kitReady: boolean = false;
      try {
        const probe: pdfService.PdfDocument = new pdfService.PdfDocument();
        probe.releaseDocument();
        kitReady = true;
      } catch (e) {
        kitReady = false;
      }
      // 合成 A4 PDF
      const outPath: string = dir + '/out.pdf';
      const okPdf: boolean = await PdfCodec.composeA4([pngPath], outPath);
      if (kitReady) {
        expect(okPdf).assertTrue();
        expect(fs.accessSync(outPath)).assertTrue();
        // 字节校验：%PDF- 头 + %%EOF 尾 + 体积下限
        const rf: fs.File = fs.openSync(outPath, fs.OpenMode.READ_ONLY);
        const st: fs.Stat = fs.statSync(rf.fd);
        const buf: ArrayBuffer = new ArrayBuffer(st.size);
        fs.readSync(rf.fd, buf);
        fs.closeSync(rf);
        const u8: Uint8Array = new Uint8Array(buf);
        expect(st.size > 800).assertTrue();
        expect(u8[0] === 0x25 && u8[1] === 0x50 && u8[2] === 0x44
          && u8[3] === 0x46 && u8[4] === 0x2D).assertTrue(); // '%PDF-'
        let eof: boolean = false;
        const scanStart: number = u8.length - 32 > 0 ? u8.length - 32 : 0;
        for (let i = scanStart; i <= u8.length - 5; i++) {
          if (u8[i] === 0x25 && u8[i + 1] === 0x25 && u8[i + 2] === 0x45
            && u8[i + 3] === 0x4F && u8[i + 4] === 0x46) { // '%%EOF'
            eof = true;
            break;
          }
        }
        expect(eof).assertTrue();
      } else {
        // kit 缺失（x86 模拟器）：优雅降级——resolve(false)、不落产物、进程不崩
        expect(okPdf).assertFalse();
        expect(fs.accessSync(outPath)).assertFalse();
      }
      await pm.release();
      packer.release();
      // 清理
      if (fs.accessSync(outPath)) {
        fs.unlinkSync(outPath);
      }
      fs.unlinkSync(pngPath);
      fs.rmdirSync(dir);
    });
  });
}
