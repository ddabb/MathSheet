/**
 * M2 测试套件（sheetM2Test）——渲染模型 / 版面引擎 / 多预设混编：
 *   - SheetModel 文本形态黄金断言（U+2212 印刷减号 / 键语义 / 填空回填）；
 *   - SheetLayout 黄金坐标快照（坐标即规格，改动即显性失败）；
 *   - SheetLayout 网格覆盖/边界/空卷/列数钳制性质；
 *   - buildMultiSheet 复现/换批/轮转交织/可行域放行/非法兜底；
 *   - 全链路：buildMultiSheet → SheetLayout 全放置。
 *
 * 运行协议（模拟器 class 过滤定向跑）：
 *   hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *     -s class sheetM2Test -s timeout 15000
 */
import { describe, it, expect } from '@ohos/hypium';
import { ProblemGen, Problem } from '../../../main/ets/core/ProblemGen';
import { MixedProblem } from '../../../main/ets/core/MixedGen';
import { BlankProblem } from '../../../main/ets/core/FillBlank';
import { SheetGen } from '../../../main/ets/core/SheetGen';
import { GradePresets, PresetEntry } from '../../../main/ets/core/GradePresets';
import { SheetItem } from '../../../main/ets/core/SheetModel';
import { SheetLayout, LayoutSpec, LayoutResult, PageLayout } from '../../../main/ets/core/SheetLayout';

export default function sheetM2Test() {
  describe('sheetM2Test', () => {
    // ---- SheetModel 文本形态（黄金字符串） ----
    it('SheetModel_goldenText', 0, () => {
      const add: SheetItem = SheetItem.fromProblem(new Problem(23, 15, 'add', 38));
      expect(add.questionText).assertEqual('23 + 15 =');
      expect(add.answerText).assertEqual('23 + 15 = 38');
      expect(add.key).assertEqual('15+23');

      const sub: SheetItem = SheetItem.fromProblem(new Problem(10, 3, 'sub', 7));
      expect(sub.questionText).assertEqual('10 \u2212 3 =');
      expect(sub.answerText).assertEqual('10 \u2212 3 = 7');
      expect(sub.key).assertEqual('10-3');

      const mul: SheetItem = SheetItem.fromProblem(new Problem(6, 7, 'mul', 42));
      expect(mul.questionText).assertEqual('6 \u00d7 7 =');
      expect(mul.answerText).assertEqual('6 \u00d7 7 = 42');
      expect(mul.key).assertEqual('6\u00d77');

      const div: SheetItem = SheetItem.fromProblem(new Problem(56, 7, 'div', 8));
      expect(div.questionText).assertEqual('56 \u00f7 7 =');
      expect(div.answerText).assertEqual('56 \u00f7 7 = 8');
      expect(div.key).assertEqual('56\u00f77');

      const m: SheetItem = SheetItem.fromMixed(new MixedProblem(12, 8, 5, 'add', 'sub', false));
      expect(m.questionText).assertEqual('12 + 8 \u2212 5 =');
      expect(m.answerText).assertEqual('12 + 8 \u2212 5 = 15');
      expect(m.key).assertEqual('12+8-5');

      const br: SheetItem = SheetItem.fromMixed(new MixedProblem(15, 8, 3, 'add', 'mul', true));
      expect(br.questionText).assertEqual('(15 + 8) \u00d7 3 =');
      expect(br.answerText).assertEqual('(15 + 8) \u00d7 3 = 69');
      expect(br.key).assertEqual('(15+8)\u00d73');

      const mb: SheetItem = SheetItem.fromMixed(new MixedProblem(6, 7, 9, 'mul', 'add', false));
      expect(mb.questionText).assertEqual('6 \u00d7 7 + 9 =');
      expect(mb.answerText).assertEqual('6 \u00d7 7 + 9 = 51');

      const bB: SheetItem = SheetItem.fromBlank(new BlankProblem(new Problem(3, 4, 'add', 7), 'b'));
      expect(bB.questionText).assertEqual('3 + \u25a1 = 7');
      expect(bB.answerText).assertEqual('3 + 4 = 7');
      expect(bB.key).assertEqual('3+\u25a1=7');

      const bA: SheetItem = SheetItem.fromBlank(new BlankProblem(new Problem(3, 4, 'add', 7), 'a'));
      expect(bA.questionText).assertEqual('\u25a1 + 4 = 7');
      expect(bA.answerText).assertEqual('3 + 4 = 7');
      expect(bA.key).assertEqual('\u25a1+4=7');

      const bR: SheetItem = SheetItem.fromBlank(new BlankProblem(new Problem(10, 3, 'sub', 7), 'answer'));
      expect(bR.questionText).assertEqual('10 \u2212 3 = \u25a1');
      expect(bR.answerText).assertEqual('10 \u2212 3 = 7');
      expect(bR.key).assertEqual('10-3=\u25a1');

      expect(SheetItem.printSymbol('-')).assertEqual('\u2212');
      expect(SheetItem.printSymbol('+')).assertEqual('+');
    });

    // ---- SheetLayout 黄金坐标（3 列 92px 题头 100 题 → 48+52 两页） ----
    it('SheetLayout_goldenGrid', 0, () => {
      const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, 'T');
      expect(spec.fontSize).assertEqual(92);
      const r: LayoutResult = SheetLayout.layout(100, spec);
      expect(r.columnWidth).assertEqual(746);
      expect(r.rowHeight).assertEqual(166);
      expect(r.titleBaselineY).assertEqual(224);
      expect(r.fieldsBaselineY).assertEqual(352);
      expect(r.footerBaselineY).assertEqual(3358);
      expect(r.pages.length).assertEqual(2);
      expect(r.pages[0].number).assertEqual(1);
      expect(r.pages[1].number).assertEqual(2);
      expect(r.pages[0].hasHeader).assertTrue();
      expect(r.pages[1].hasHeader).assertFalse();
      expect(r.pages[0].items.length).assertEqual(48);
      expect(r.pages[1].items.length).assertEqual(52);
      expect(`${r.pages[0].items[0].index},${r.pages[0].items[0].x},${r.pages[0].items[0].y}`).assertEqual('0,144,620');
      expect(`${r.pages[0].items[1].index},${r.pages[0].items[1].x},${r.pages[0].items[1].y}`).assertEqual('1,144,786');
      expect(`${r.pages[0].items[16].index},${r.pages[0].items[16].x},${r.pages[0].items[16].y}`).assertEqual('16,890,620');
      expect(`${r.pages[0].items[47].index},${r.pages[0].items[47].x},${r.pages[0].items[47].y}`).assertEqual('47,1636,3110');
      expect(`${r.pages[1].items[0].index},${r.pages[1].items[0].x},${r.pages[1].items[0].y}`).assertEqual('48,144,240');
      expect(`${r.pages[1].items[51].index},${r.pages[1].items[51].x},${r.pages[1].items[51].y}`).assertEqual('99,1636,2398');
    });

    // ---- SheetLayout 网格/覆盖/边界性质 ----
    it('SheetLayout_properties', 0, () => {
      const spec4: LayoutSpec = new LayoutSpec(4, LayoutSpec.fontSizeForColumns(4), true, 'T');
      expect(spec4.fontSize).assertEqual(76);
      const r4: LayoutResult = SheetLayout.layout(200, spec4);
      expect(r4.columnWidth).assertEqual(560);
      expect(r4.rowHeight).assertEqual(137);
      expect(r4.pages.length).assertEqual(3);
      expect(r4.pages[0].items.length).assertEqual(80);
      expect(r4.pages[1].items.length).assertEqual(92);
      expect(r4.pages[2].items.length).assertEqual(28);

      let idx: number = 0;
      let onGrid: boolean = true;
      let inBounds: boolean = true;
      const bottomLimit: number = SheetLayout.PAGE_H - SheetLayout.MARGIN - SheetLayout.FOOTER_H;
      for (const page of r4.pages) {
        const top: number = page.hasHeader ? SheetLayout.MARGIN + SheetLayout.HEADER_H : SheetLayout.MARGIN;
        for (const it of page.items) {
          if (it.index !== idx) {
            onGrid = false;
          }
          idx++;
          if ((it.x - SheetLayout.MARGIN - SheetLayout.COL_INSET) % r4.columnWidth !== 0) {
            onGrid = false;
          }
          if (it.x < SheetLayout.MARGIN || it.x + 500 > SheetLayout.PAGE_W - SheetLayout.MARGIN) {
            inBounds = false;
          }
          if (it.y < top || it.y > bottomLimit) {
            inBounds = false;
          }
        }
      }
      expect(onGrid && idx === 200).assertTrue();
      expect(inBounds).assertTrue();

      const spec2: LayoutSpec = new LayoutSpec(2, LayoutSpec.fontSizeForColumns(2), false, '');
      expect(spec2.fontSize).assertEqual(108);
      const r2: LayoutResult = SheetLayout.layout(30, spec2);
      expect(r2.pages.length).assertEqual(1);
      expect(r2.columnWidth).assertEqual(1120);
      expect(r2.rowHeight).assertEqual(194);
      expect(r2.pages[0].hasHeader).assertFalse();
      expect(`${r2.pages[0].items[0].x},${r2.pages[0].items[0].y}`).assertEqual('144,260');
      expect(`${r2.pages[0].items[16].x},${r2.pages[0].items[16].y}`).assertEqual('1264,260');
      expect(`${r2.pages[0].items[29].x},${r2.pages[0].items[29].y}`).assertEqual('1264,2782');

      const empty: LayoutResult = SheetLayout.layout(0, new LayoutSpec(2, 108, true, 'T'));
      expect(empty.pages.length).assertEqual(1);
      expect(empty.pages[0].items.length).assertEqual(0);
      expect(empty.pages[0].hasHeader).assertTrue();
      expect(empty.pages[0].number).assertEqual(1);

      const clamped: LayoutResult = SheetLayout.layout(10, new LayoutSpec(99, 76, false, ''));
      expect(clamped.columnWidth).assertEqual(560);
      expect(clamped.pages.length).assertEqual(1);
    });

    // ---- buildMultiSheet 复现 / 换批 / 轮转交织 / 放行 ----
    it('buildMultiSheet_reproAndInterleave', 0, () => {
      const e1: PresetEntry | null = GradePresets.byId('g2_mul_table');
      const e2: PresetEntry | null = GradePresets.byId('g2_div_table');
      expect(e1 !== null && e2 !== null).assertTrue();
      if (e1 !== null && e2 !== null) {
        const a = SheetGen.buildMultiSheet([e1, e2], 4321, 40);
        const b = SheetGen.buildMultiSheet([e1, e2], 4321, 40);
        expect(a.items.length).assertEqual(40);
        expect(a.duplicates).assertEqual(b.duplicates);
        for (let i = 0; i < 40; i++) {
          expect(a.items[i].questionText).assertEqual(b.items[i].questionText);
        }
        const c = SheetGen.buildMultiSheet([e1, e2], 9999, 40);
        let diff: number = 0;
        for (let i = 0; i < 40; i++) {
          if (a.items[i].key !== c.items[i].key) {
            diff++;
          }
        }
        expect(diff > 0).assertTrue();
        for (const it of a.items) {
          expect(it.questionText.indexOf('=') >= 0).assertTrue();
          expect(it.answerText.length > it.questionText.length).assertTrue();
        }
        let mulCount: number = 0;
        for (const it of a.items) {
          if (it.questionText.indexOf('\u00d7') >= 0) {
            mulCount++;
          }
        }
        expect(mulCount >= 14 && mulCount <= 26).assertTrue();

        const g3a: PresetEntry | null = GradePresets.byId('g3_add_3d');
        const g3s: PresetEntry | null = GradePresets.byId('g3_sub_3d');
        expect(g3a !== null && g3s !== null).assertTrue();
        if (g3a !== null && g3s !== null) {
          const ss = SheetGen.buildMultiSheet([g3a, g3s], 555, 40);
          expect(ss.duplicates).assertEqual(0);
          let alt: boolean = true;
          const skeys: Set<string> = new Set<string>();
          for (let i = 0; i < 40; i++) {
            const it = ss.items[i];
            skeys.add(it.key);
            const isAdd: boolean = it.questionText.indexOf('+') >= 0;
            const isSub: boolean = it.questionText.indexOf('\u2212') >= 0;
            if (isAdd === isSub) {
              alt = false;
            }
            if (isAdd !== (i % 2 === 0)) {
              alt = false;
            }
          }
          expect(alt).assertTrue();
          expect(skeys.size).assertEqual(40);
        }
      }
    });

    // ---- buildMultiSheet 全年级混选 / 单预设退化 / 填空 / 兜底 ----
    it('buildMultiSheet_fullGradeAndFallback', 0, () => {
      const g2all: PresetEntry[] = GradePresets.forGrade(2);
      const all = SheetGen.buildMultiSheet(g2all, 2026, 60);
      const allAgain = SheetGen.buildMultiSheet(g2all, 2026, 60);
      expect(all.items.length).assertEqual(60);
      let allSame: boolean = true;
      const akeys: Set<string> = new Set<string>();
      for (let i = 0; i < 60; i++) {
        if (all.items[i].key !== allAgain.items[i].key) {
          allSame = false;
        }
        akeys.add(all.items[i].key);
        expect(all.items[i].questionText.indexOf('=') >= 0).assertTrue();
      }
      expect(allSame).assertTrue();
      expect(akeys.size >= 54).assertTrue();

      const e1: PresetEntry | null = GradePresets.byId('g2_mul_table');
      expect(e1 !== null).assertTrue();
      if (e1 !== null) {
        const single = SheetGen.buildMultiSheet([e1], 777, 30);
        expect(single.items.length).assertEqual(30);
        for (const it of single.items) {
          expect(it.questionText.indexOf('\u00d7') >= 0).assertTrue();
        }
        const big = SheetGen.buildMultiSheet([e1], 888, 100);
        expect(big.items.length).assertEqual(100);
        expect(big.duplicates > 0).assertTrue();
      }

      const g1f: PresetEntry | null = GradePresets.byId('g1_fill');
      expect(g1f !== null).assertTrue();
      if (g1f !== null) {
        const fs = SheetGen.buildMultiSheet([g1f], 321, 25);
        expect(fs.items.length).assertEqual(25);
        for (const it of fs.items) {
          expect(it.questionText.indexOf('\u25a1') >= 0).assertTrue();
          expect(it.answerText.indexOf('\u25a1') < 0).assertTrue();
        }
      }

      const bad: PresetEntry = new PresetEntry('bad', 9, '', '', 'single', null);
      const bs = SheetGen.buildMultiSheet([bad], 11, 10);
      expect(bs.items.length).assertEqual(10);
      for (const it of bs.items) {
        const parts: string[] = it.answerText.split('= ');
        expect(parts.length === 2).assertTrue();
        if (parts.length === 2) {
          const v: number = parseInt(parts[1], 10);
          expect(v >= 1 && v <= 10).assertTrue();
        }
      }
    });

    // ---- 全链路：buildMultiSheet → SheetLayout 全放置 ----
    it('pipeline_generateToLayout', 0, () => {
      const g3: PresetEntry[] = GradePresets.forGrade(3);
      const sheet = SheetGen.buildMultiSheet(g3, 20261019, 100);
      expect(sheet.items.length).assertEqual(100);
      const spec: LayoutSpec = new LayoutSpec(3, LayoutSpec.fontSizeForColumns(3), true, 'G3');
      const layout: LayoutResult = SheetLayout.layout(sheet.items.length, spec);
      expect(layout.pages.length).assertEqual(2);
      let placed: number = 0;
      for (const page of layout.pages) {
        placed += page.items.length;
      }
      expect(placed).assertEqual(100);
      expect(layout.pages[0].items[0].index).assertEqual(0);
      expect(layout.pages[1].items[51].index).assertEqual(99);
      const page0: PageLayout = layout.pages[0];
      expect(page0.items[0].y > layout.fieldsBaselineY).assertTrue();
    });
  });
}
