/**
 * M5 性能预算复核（计划 §6.5；模拟器 x86_64 实测口径，真机 M6 复测）：
 *   - 200 题生成（含去重） < 50ms —— buildMultiSheetTraced 5 轮取均值；
 *   - A4 300dpi 单页渲染 < 300ms —— scale=1（2480×3508）单页计时；
 *   - 卷库 500 卷索引加载 < 100ms —— 500 卷物化后 loadIndex 5 轮取均值。
 * 不在此测：10 页 PDF 合成 < 3s（x86 模拟器无 PDF Kit，真机口径）、
 *           预览翻页 < 16ms（UI 层 LRU 缓存，E2E/真机观察）。
 *
 * 运行协议：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class perfTest -s timeout 60000
 */
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Context } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { GradePresets, PresetEntry } from '../../../main/ets/core/GradePresets';
import { SheetGen } from '../../../main/ets/core/SheetGen';
import { SheetItem } from '../../../main/ets/core/SheetModel';
import { LayoutSpec, SheetLayout } from '../../../main/ets/core/SheetLayout';
import { PageRenderRequest, SheetRenderer } from '../../../main/ets/render/SheetRenderer';
import { StoredItem, StoredMeta, StoredSheet } from '../../../main/ets/core/SheetCodec';
import { SheetStore } from '../../../main/ets/core/SheetStore';
import { MemberScope } from '../../../main/ets/core/ProfileCodec';

export default function perfTest() {
  describe('perfTest', () => {
    // ---- 200 题生成（含去重）：< 50ms（预热后 5 轮均值） ----
    it('Perf_gen200', 0, () => {
      const pa: PresetEntry | null = GradePresets.byId('g3_add_3d');
      const pb: PresetEntry | null = GradePresets.byId('g3_sub_3d');
      expect(pa !== null && pb !== null).assertTrue();
      if (pa !== null && pb !== null) {
        const presets: PresetEntry[] = [pa, pb];
        SheetGen.buildMultiSheetTraced(presets, 1, 200); // 预热（jit/内联）
        const t0: number = Date.now();
        for (let round: number = 0; round < 5; round++) {
          const traced = SheetGen.buildMultiSheetTraced(presets, 1000 + round, 200);
          expect(traced.items.length).assertEqual(200);
        }
        const avg: number = (Date.now() - t0) / 5;
        console.info(`[perf] gen200 avg=${avg}ms`);
        expect(avg < 50).assertTrue();
      }
    });

    // ---- A4 300dpi 单页渲染：< 300ms（预热一次后 3 次取均值） ----
    it('Perf_renderA4', 0, async (): Promise<void> => {
      const pa: PresetEntry | null = GradePresets.byId('g2_add100_base');
      expect(pa !== null).assertTrue();
      if (pa !== null) {
        const traced = SheetGen.buildMultiSheetTraced([pa], 42, 200);
        const items: SheetItem[] = [];
        for (const t of traced.items) {
          items.push(new SheetItem(t.item.questionText, t.item.answerText, t.item.key));
        }
        const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, '性能卷');
        const layout = SheetLayout.layout(items.length, spec);
        const label: string = `第 1 / ${layout.pages.length} 页`;
        const req: PageRenderRequest = new PageRenderRequest(items, layout, spec, 0,
          label, '姓名：____ 日期：____', false, 1);
        const warm: image.PixelMap = await SheetRenderer.renderPage(req); // 预热（字体注册/首帧）
        await warm.release();
        const t0: number = Date.now();
        for (let round: number = 0; round < 3; round++) {
          const pm: image.PixelMap = await SheetRenderer.renderPage(req);
          await pm.release();
        }
        const avg: number = (Date.now() - t0) / 3;
        console.info(`[perf] renderA4 avg=${avg}ms`);
        expect(avg < 300).assertTrue();
      }
    });

    // ---- 卷库 500 卷索引加载：< 100ms（批量物化后 5 轮均值） ----
    it('Perf_store500Index', 0, () => {
      const ctx: Context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const scope: MemberScope = new MemberScope(ctx.filesDir);
      const ids: string[] = [];
      const sheets: StoredSheet[] = [];
      for (let i: number = 0; i < 500; i++) {
        const id: string = `perft${i}`;
        ids.push(id);
        sheets.push(new StoredSheet(id, 1700000000000 + i, `性能卷${i}`, 2, ['g2_add_100'], 1, 3,
          true, false, i, [new StoredItem('1 + 1 =', '1 + 1 = 2', '1+1', 'g2_add_100')], [0]));
      }
      SheetStore.removeSheets(scope, ids); // 历史残留清理
      SheetStore.saveSheets(scope, sheets); // 一次批量入库（500 文件 + 1 索引写）
      const warm: StoredMeta[] = SheetStore.loadIndex(scope);
      expect(warm.filter((m: StoredMeta) => m.id.indexOf('perft') === 0).length).assertEqual(500);
      const t0: number = Date.now();
      for (let round: number = 0; round < 5; round++) {
        SheetStore.loadIndex(scope);
      }
      const avg: number = (Date.now() - t0) / 5;
      console.info(`[perf] store500Index avg=${avg}ms`);
      expect(avg < 100).assertTrue();
      SheetStore.removeSheets(scope, ids); // 清理
      expect(SheetStore.loadIndex(scope).filter((m: StoredMeta) => m.id.indexOf('perft') === 0)
        .length).assertEqual(0);
    });
  });
}
