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

/** 已放置题目：题目下标 + 文本基线坐标（px，300dpi 基准）。 */
export class PlacedItem {
  index: number;
  x: number;
  y: number;

  constructor(index: number, x: number, y: number) {
    this.index = index;
    this.x = x;
    this.y = y;
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

  /** 布局主入口：题数 + 规格 → 逐页坐标（纯函数，同输入同输出）。 */
  static layout(itemCount: number, spec: LayoutSpec): LayoutResult {
    const columns: number = Math.max(1, Math.min(4, Math.floor(spec.columns)));
    const rowHeight: number = Math.round(spec.fontSize * SheetLayout.ROW_FACTOR);
    const baselineOffset: number = Math.round(spec.fontSize * SheetLayout.BASELINE_FACTOR);
    const columnWidth: number = Math.floor((SheetLayout.PAGE_W - 2 * SheetLayout.MARGIN) / columns);
    const firstTop: number = SheetLayout.MARGIN + (spec.headerEnabled ? SheetLayout.HEADER_H : 0);
    const laterTop: number = SheetLayout.MARGIN;
    const bottomLimit: number = SheetLayout.PAGE_H - SheetLayout.MARGIN - SheetLayout.FOOTER_H;
    const rowsFirst: number = Math.max(1, Math.floor((bottomLimit - firstTop) / rowHeight));
    const rowsLater: number = Math.max(1, Math.floor((bottomLimit - laterTop) / rowHeight));

    const pages: PageLayout[] = [];
    let index: number = 0;
    let pageNo: number = 0;
    while (index < itemCount) {
      const isFirst: boolean = pageNo === 0;
      const top: number = isFirst ? firstTop : laterTop;
      const rows: number = isFirst ? rowsFirst : rowsLater;
      const capacity: number = rows * columns;
      const n: number = Math.min(capacity, itemCount - index);
      const items: PlacedItem[] = [];
      for (let k = 0; k < n; k++) {
        const col: number = Math.floor(k / rows);
        const row: number = k % rows;
        items.push(new PlacedItem(index + k,
          SheetLayout.MARGIN + col * columnWidth + SheetLayout.COL_INSET,
          top + row * rowHeight + baselineOffset));
      }
      pages.push(new PageLayout(items, pageNo + 1, isFirst && spec.headerEnabled));
      index += n;
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
