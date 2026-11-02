/**
 * M2 核心②：版面引擎（纯函数，计划 §6.3 关键技术点②）。
 *
 * 输入（题数 + LayoutSpec）→ 输出逐题 (页号, x, y) 坐标布局树：
 *  - A4 竖版 300dpi 基准（2480×3508px），列数 2/3/4，字号联动列数；
 *  - 列优先纵向流动（口算题卡惯例：填满一列再换列）；
 *  - 首页题头（标题 + 字段栏）占位，后续页无题头可容纳更多行；
 *  - 每页页脚页码占位；答案页复用同布局（渲染层以答案文本 + 红色呈现）。
 * 黄金用例直测：坐标快照断言（MathCore.test SheetLayout 段）。
 */

import { SheetItem } from './SheetModel';

/** 版面规格（可变部分；页面常量见 SheetLayout 静态字段）。 */
export class LayoutSpec {
  /** 列数（2/3/4）。 */
  columns: number;
  /** 题目字号 px（300dpi 基准；fontSizeForColumns 联动列数）。 */
  fontSize: number;
  /** 首页题头开关。 */
  headerEnabled: boolean;
  /** 题头标题文本（渲染层绘制，布局只占位）。 */
  title: string;

  constructor(columns: number, fontSize: number, headerEnabled: boolean, title: string) {
    this.columns = columns;
    this.fontSize = fontSize;
    this.headerEnabled = headerEnabled;
    this.title = title;
  }

  /** 字号联动列数：2→108 / 3→92 / 4→76（300dpi，约 26/22/18pt）。 */
  static fontSizeForColumns(columns: number): number {
    if (columns <= 2) {
      return 108;
    }
    return columns === 3 ? 92 : 76;
  }
}

/** 已放置题目：题目下标 + 文本基线坐标（px，300dpi 基准）+ 占用行数。 */
export class PlacedItem {
  index: number;
  x: number;
  y: number;
  /** 占用行数（1.0.1 M8 竖式 = 4；横式 = 1；行距同 rowHeight）。 */
  lines: number;

  constructor(index: number, x: number, y: number, lines: number = 1) {
    this.index = index;
    this.x = x;
    this.y = y;
    this.lines = lines;
  }
}

/** 单页布局：已放置题目 + 页号（1 起）+ 是否带题头。 */
export class PageLayout {
  items: PlacedItem[];
  number: number;
  hasHeader: boolean;

  constructor(items: PlacedItem[], number: number, hasHeader: boolean) {
    this.items = items;
    this.number = number;
    this.hasHeader = hasHeader;
  }
}

/** 布局结果：逐页布局 + 渲染层所需的派生几何。 */
export class LayoutResult {
  pages: PageLayout[];
  /** 列宽 px。 */
  columnWidth: number;
  /** 行高 px（基线间距）。 */
  rowHeight: number;
  /** 题头标题基线 Y。 */
  titleBaselineY: number;
  /** 题头字段行基线 Y。 */
  fieldsBaselineY: number;
  /** 页脚页码基线 Y。 */
  footerBaselineY: number;

  constructor(pages: PageLayout[], columnWidth: number, rowHeight: number,
              titleBaselineY: number, fieldsBaselineY: number, footerBaselineY: number) {
    this.pages = pages;
    this.columnWidth = columnWidth;
    this.rowHeight = rowHeight;
    this.titleBaselineY = titleBaselineY;
    this.fieldsBaselineY = fieldsBaselineY;
    this.footerBaselineY = footerBaselineY;
  }
}

export class SheetLayout {
  /** A4 竖版 300dpi 页面宽（px）。 */
  static readonly PAGE_W: number = 2480;
  /** A4 竖版 300dpi 页面高（px）。 */
  static readonly PAGE_H: number = 3508;
  /** 页边距（px）。 */
  static readonly MARGIN: number = 120;
  /** 题头区高度（px，首页内容顶 = MARGIN + HEADER_H）。 */
  static readonly HEADER_H: number = 380;
  /** 页脚区高度（px，题目区底 = PAGE_H − MARGIN − FOOTER_H）。 */
  static readonly FOOTER_H: number = 110;
  /** 列内左缩进（px）。 */
  static readonly COL_INSET: number = 24;
  /** 题头标题字号（px）。 */
  static readonly TITLE_FONT: number = 104;
  /** 题头字段行字号（px）。 */
  static readonly FIELDS_FONT: number = 64;
  /** 页脚页码字号（px）。 */
  static readonly FOOTER_FONT: number = 56;
  /** 行高 = 字号 × 行距系数。 */
  static readonly ROW_FACTOR: number = 1.8;
  /** 行内基线偏移 = 字号 × 基线系数。 */
  static readonly BASELINE_FACTOR: number = 1.3;

  /** 从物化题目推导逐题行数（竖式 4 行，横式 1 行；行数驱动面积判据）。 */
  static lineCountsOf(items: SheetItem[]): number[] {
    const out: number[] = [];
    for (const it of items) {
      out.push(it.questionText.split('\n').length);
    }
    return out;
  }

  /**
   * 布局主入口：题数 + 规格（+ 可选逐题行数）→ 逐页坐标（纯函数，同输入同输出）。
   * lineCounts 缺省（全 1 行）时与旧版行列算法逐坐标等价（黄金兼容）；
   * 竖式等多行题按"整块放下才放置"面积判据逐列流动（yCursor + L×rowHeight ≤ bottomLimit）。
   */
  static layout(itemCount: number, spec: LayoutSpec,
                lineCounts: number[] | null = null): LayoutResult {
    const columns: number = Math.max(1, Math.min(4, Math.floor(spec.columns)));
    const rowHeight: number = Math.round(spec.fontSize * SheetLayout.ROW_FACTOR);
    const baselineOffset: number = Math.round(spec.fontSize * SheetLayout.BASELINE_FACTOR);
    const columnWidth: number = Math.floor((SheetLayout.PAGE_W - 2 * SheetLayout.MARGIN) / columns);
    const firstTop: number = SheetLayout.MARGIN + (spec.headerEnabled ? SheetLayout.HEADER_H : 0);
    const laterTop: number = SheetLayout.MARGIN;
    const bottomLimit: number = SheetLayout.PAGE_H - SheetLayout.MARGIN - SheetLayout.FOOTER_H;

    const linesOf = (i: number): number => {
      if (lineCounts !== null && i < lineCounts.length) {
        return Math.max(1, Math.round(lineCounts[i]));
      }
      return 1;
    };

    const pages: PageLayout[] = [];
    let index: number = 0;
    let pageNo: number = 0;
    while (index < itemCount) {
      const isFirst: boolean = pageNo === 0;
      const top: number = isFirst ? firstTop : laterTop;
      const items: PlacedItem[] = [];
      for (let col = 0; col < columns && index < itemCount; col++) {
        let yCursor: number = top;
        while (index < itemCount) {
          const lines: number = linesOf(index);
          if (yCursor + lines * rowHeight > bottomLimit) {
            break;
          }
          items.push(new PlacedItem(index,
            SheetLayout.MARGIN + col * columnWidth + SheetLayout.COL_INSET,
            yCursor + baselineOffset, lines));
          yCursor += lines * rowHeight;
          index++;
        }
      }
      // 极端兜底：单行块都放不下（行高 > 可用高）时每列强放 1 题，防 0 放置死循环
      if (items.length === 0) {
        for (let col = 0; col < columns && index < itemCount; col++) {
          items.push(new PlacedItem(index,
            SheetLayout.MARGIN + col * columnWidth + SheetLayout.COL_INSET,
            top + baselineOffset, linesOf(index)));
          index++;
        }
      }
      pages.push(new PageLayout(items, pageNo + 1, isFirst && spec.headerEnabled));
      pageNo++;
    }
    if (pages.length === 0) {
      pages.push(new PageLayout([], 1, spec.headerEnabled));
    }
    return new LayoutResult(pages, columnWidth, rowHeight,
      SheetLayout.MARGIN + SheetLayout.TITLE_FONT,
      SheetLayout.MARGIN + SheetLayout.TITLE_FONT + Math.round(SheetLayout.FIELDS_FONT * 2),
      SheetLayout.PAGE_H - SheetLayout.MARGIN - 30);
  }
}
