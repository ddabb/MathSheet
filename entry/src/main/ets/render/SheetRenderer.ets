/**
 * M2 渲染管线（计划 §6.3）：布局坐标 + 题目文本 → 单页位图（PixelMap）。
 *
 * - drawing.Font 文本光栅（M0 查证项：setSize/measureText/TextBlob/drawTextBlob 均可用）；
 * - 白底不透明 RGBA_8888，题目黑色、答案页红色（#DC2626）；
 * - scale 缩放渲染（1 = A4 300dpi 全尺寸导出基准；预览 < 1 省内存）；
 * - 文本（题头字段/页码）由调用方本地化后传入，渲染器不持资源语义。
 */

import { common2D, drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { LayoutResult, LayoutSpec, PageLayout, PlacedItem, SheetLayout } from '../core/SheetLayout';
import { SheetItem } from '../core/SheetModel';

/** 单页渲染请求。 */
export class PageRenderRequest {
  /** 全卷题目（PlacedItem.index 为其下标）。 */
  items: SheetItem[];
  layout: LayoutResult;
  spec: LayoutSpec;
  /** 本卷内页下标（0 起）。 */
  pageIndex: number;
  /** 页脚页码文本（空串不绘制）。 */
  pageLabel: string;
  /** 题头字段行文本（空串不绘制，仅首页题头开启时生效）。 */
  fieldsText: string;
  /** 答案页模式：红色答案文本。 */
  showAnswers: boolean;
  /** 渲染缩放（1 = 300dpi 全尺寸）。 */
  scale: number;

  constructor(items: SheetItem[], layout: LayoutResult, spec: LayoutSpec, pageIndex: number,
              pageLabel: string, fieldsText: string, showAnswers: boolean, scale: number) {
    this.items = items;
    this.layout = layout;
    this.spec = spec;
    this.pageIndex = pageIndex;
    this.pageLabel = pageLabel;
    this.fieldsText = fieldsText;
    this.showAnswers = showAnswers;
    this.scale = scale;
  }
}

export class SheetRenderer {
  /** 答案页红色（#DC2626）。 */
  private static readonly ANSWER_RED: common2D.Color = { alpha: 255, red: 220, green: 38, blue: 38 };
  /** 答案页网格线浅灰（#D1D5DB）：衬红色答案，隔断相邻题答案防串行。 */
  private static readonly GRID_GRAY: common2D.Color = { alpha: 255, red: 209, green: 213, blue: 219 };
  /** 题目黑色。 */
  private static readonly TEXT_BLACK: common2D.Color = { alpha: 255, red: 33, green: 33, blue: 33 };
  /** 打印字体（Noto Sans SC = 思源黑体 Google 分发版，OFL；子集含数学符号 −×÷□，
   * 由 scripts/check_font_coverage.py 护栏保证字符覆盖；加载失败回退系统字体）。 */
  private static typeface: drawing.Typeface | null = null;
  private static typefaceTried: boolean = false;

  /** 加载打印字体（幂等；渲染前调用，UI 层与测试层共用）。 */
  static ensureTypeface(): void {
    if (SheetRenderer.typefaceTried) {
      return;
    }
    SheetRenderer.typefaceTried = true;
    try {
      SheetRenderer.typeface = drawing.Typeface.makeFromRawFile($rawfile('font/NotoSansSC-Regular.ttf'));
    } catch (e) {
      SheetRenderer.typeface = null;
    }
  }

  /** 构造带打印字体的 Font（未加载成功时回退系统字体）。 */
  private static makeFont(fontSize: number): drawing.Font {
    const font: drawing.Font = new drawing.Font();
    font.setSize(fontSize);
    SheetRenderer.ensureTypeface();
    if (SheetRenderer.typeface !== null) {
      font.setTypeface(SheetRenderer.typeface);
    }
    return font;
  }

  /** 渲染单页 → 白底 PixelMap（异步）。 */
  static async renderPage(req: PageRenderRequest): Promise<image.PixelMap> {
    const w: number = Math.max(1, Math.round(SheetLayout.PAGE_W * req.scale));
    const h: number = Math.max(1, Math.round(SheetLayout.PAGE_H * req.scale));
    const buffer: ArrayBuffer = new ArrayBuffer(w * h * 4);
    new Uint8Array(buffer).fill(255);
    const opts: image.InitializationOptions = {
      size: { width: w, height: h },
      pixelFormat: image.PixelMapFormat.RGBA_8888
    };
    const pm: image.PixelMap = await image.createPixelMap(buffer, opts);
    SheetRenderer.drawPage(new drawing.Canvas(pm), req, w, 0);
    return pm;
  }

  /**
   * 页面绘制（drawing.Canvas 目标，供离屏与上屏复用）。
   * offsetY：长图合成时逐页纵向偏移（M3 导出 PNG 长图用，单页渲染传 0）。
   */
  static drawPage(canvas: drawing.Canvas, req: PageRenderRequest, pageWidth: number, offsetY: number): void {
    const s: number = req.scale;
    const page: PageLayout = req.layout.pages[req.pageIndex];
    if (page.hasHeader) {
      SheetRenderer.drawCenteredText(canvas, req.spec.title,
        Math.round(SheetLayout.TITLE_FONT * s),
        pageWidth, Math.round(req.layout.titleBaselineY * s) + offsetY, SheetRenderer.TEXT_BLACK);
      if (req.fieldsText !== '') {
        SheetRenderer.drawText(canvas, req.fieldsText,
          Math.round(SheetLayout.FIELDS_FONT * s),
          Math.round(SheetLayout.MARGIN * s), Math.round(req.layout.fieldsBaselineY * s) + offsetY,
          SheetRenderer.TEXT_BLACK);
      }
    }
    const font: drawing.Font = SheetRenderer.makeFont(Math.round(req.spec.fontSize * s));
    if (req.showAnswers) {
      SheetRenderer.drawAnswerGrid(canvas, req, page, s, offsetY);
    }
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(req.showAnswers ? SheetRenderer.ANSWER_RED : SheetRenderer.TEXT_BLACK);
    canvas.attachBrush(brush);
    for (const placed of page.items) {
      const item: SheetItem = req.items[placed.index];
      const text: string = req.showAnswers ? item.answerText : item.questionText;
      if (text.indexOf('\n') >= 0) {
        // 多行题分支（模式无关判据 = 题面文本）：竖式（M8）题面以 '\n' 结尾 → 右对齐 + 横线；
        // 数形结合（v1.1 §17.3）题面末行为算式行（不以 '\n' 结尾）→ 逐行左对齐，点行缩排；
        // 面积模型（far 键，4 行）→ drawAreaModel 矢量分割矩形，解析失败退回逐行文本。
        const vertical: boolean = item.questionText.length > 0
          && item.questionText.charAt(item.questionText.length - 1) === '\n';
        canvas.detachBrush();
        if (vertical) {
          SheetRenderer.drawVertical(canvas, text, font, placed, req, s, offsetY);
        } else if (!SheetRenderer.drawAreaModel(canvas, text, item, placed, req, s, offsetY)
          && !SheetRenderer.drawFracArea(canvas, text, item, placed, req, s, offsetY)) {
          SheetRenderer.drawFigureLines(canvas, text, placed, req, s, offsetY);
        }
        canvas.attachBrush(brush);
        continue;
      }
      canvas.drawTextBlob(drawing.TextBlob.makeFromString(text, font),
        Math.round(placed.x * s), Math.round(placed.y * s) + offsetY);
    }
    canvas.detachBrush();
    if (req.pageLabel !== '') {
      SheetRenderer.drawCenteredText(canvas, req.pageLabel,
        Math.round(SheetLayout.FOOTER_FONT * s),
        pageWidth, Math.round(req.layout.footerBaselineY * s) + offsetY, SheetRenderer.TEXT_BLACK);
    }
  }

  /**
   * 答案页网格线：内容区画行列网格（行距 = rowHeight、列距 = columnWidth，与布局引擎同源），
   * 每题答案落在独立格内，避免相邻题答案串行误读；题页不画（留白供作答）。
   */
  private static drawAnswerGrid(canvas: drawing.Canvas, req: PageRenderRequest,
                                page: PageLayout, s: number, offsetY: number): void {
    const top: number = Math.round((SheetLayout.MARGIN
      + (page.hasHeader ? SheetLayout.HEADER_H : 0)) * s) + offsetY;
    const bottom: number = Math.round((SheetLayout.PAGE_H
      - SheetLayout.MARGIN - SheetLayout.FOOTER_H) * s) + offsetY;
    const left: number = Math.round(SheetLayout.MARGIN * s);
    const columns: number = Math.max(1, Math.min(4, Math.floor(req.spec.columns)));
    const colW: number = req.layout.columnWidth * s;
    const right: number = Math.round(left + columns * colW);
    const rowH: number = req.layout.rowHeight * s;
    const pen: drawing.Pen = new drawing.Pen();
    pen.setColor(SheetRenderer.GRID_GRAY);
    pen.setStrokeWidth(Math.max(1, Math.round(1.5 * s)));
    canvas.attachPen(pen);
    canvas.drawLine(left, top, right, top);
    canvas.drawLine(left, bottom, right, bottom);
    canvas.drawLine(left, top, left, bottom);
    canvas.drawLine(right, top, right, bottom);
    for (let y: number = top + rowH; y < bottom - 1; y += rowH) {
      const yy: number = Math.round(y);
      canvas.drawLine(left, yy, right, yy);
    }
    for (let c: number = 1; c < columns; c++) {
      const xx: number = Math.round(left + c * colW);
      canvas.drawLine(xx, top, xx, bottom);
    }
    canvas.detachPen();
  }

  /**
   * 竖式题绘制（1.0.1 M8）：行基线 = y0 + i×rowHeight（i=0 上行 / 1 运算符+下行 / 3 结果行），
   * 逐行右对齐（列右缘 = 列宽 − COL_INSET），第 2 行位画横线（运算符与结果之间的等号线）。
   * 题面模式第 3 行为空（学生作答位）；答案模式为红色结果。
   */
  private static drawVertical(canvas: drawing.Canvas, text: string, font: drawing.Font,
                              placed: PlacedItem, req: PageRenderRequest,
                              s: number, offsetY: number): void {
    const lines: string[] = text.split('\n');
    const rowH: number = req.layout.rowHeight * s;
    const fontSize: number = Math.round(req.spec.fontSize * s);
    const y0: number = placed.y * s + offsetY;
    const rightX: number =
      (placed.x - SheetLayout.COL_INSET + req.layout.columnWidth - SheetLayout.COL_INSET) * s;
    const color: common2D.Color = req.showAnswers ? SheetRenderer.ANSWER_RED : SheetRenderer.TEXT_BLACK;
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line === '') {
        continue;
      }
      const w: number = font.measureText(line, drawing.TextEncoding.TEXT_ENCODING_UTF8);
      SheetRenderer.drawText(canvas, line, fontSize,
        Math.round(rightX - w), Math.round(y0 + i * rowH), color);
    }
    // 横线：第 2 行（空行）区内，运算行基线与结果行基线之间
    const ruleY: number = Math.round(y0 + 2 * rowH - req.spec.fontSize * 0.9 * s);
    const pen: drawing.Pen = new drawing.Pen();
    pen.setColor(color);
    pen.setStrokeWidth(Math.max(3, Math.round(4 * s)));
    canvas.attachPen(pen);
    canvas.drawLine(Math.round(placed.x * s), ruleY, Math.round(rightX), ruleY);
    canvas.detachPen();
  }

  /** 点行缩放系数：●/○ 全角 1em，0.55 倍字号后 4 列版心（6.737em）可容 12 点 / 9 列点阵。 */
  private static readonly DOT_LINE_SCALE: number = 0.55;

  /** 行是否为点行（仅 ●/○/空格组成；渲染层按 DOT_LINE_SCALE 缩排以贴合 4 列版心宽度）。 */
  private static isDotLine(line: string): boolean {
    if (line.length === 0) {
      return false;
    }
    for (let i: number = 0; i < line.length; i++) {
      const ch: string = line.charAt(i);
      if (ch !== '\u25cf' && ch !== '\u25cb' && ch !== ' ') {
        return false;
      }
    }
    return true;
  }

  /**
   * 数形结合多行题绘制（v1.1 §17.3）：逐行左对齐，行基线 = y0 + i×rowHeight；
   * 点行（看图列式 / 点阵乘法的 ●○ 行）按 0.55 倍字号缩排，其余行（算式/数轴）原字号。
   */
  private static drawFigureLines(canvas: drawing.Canvas, text: string,
                                 placed: PlacedItem, req: PageRenderRequest,
                                 s: number, offsetY: number): void {
    const lines: string[] = text.split('\n');
    const rowH: number = req.layout.rowHeight * s;
    const fontSize: number = Math.round(req.spec.fontSize * s);
    const dotFont: number = Math.max(8, Math.round(fontSize * SheetRenderer.DOT_LINE_SCALE));
    const y0: number = placed.y * s + offsetY;
    const color: common2D.Color = req.showAnswers ? SheetRenderer.ANSWER_RED : SheetRenderer.TEXT_BLACK;
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line === '') {
        continue;
      }
      const fs: number = SheetRenderer.isDotLine(line) ? dotFont : fontSize;
      SheetRenderer.drawText(canvas, line, fs, Math.round(placed.x * s),
        Math.round(y0 + i * rowH), color);
    }
  }

  /**
   * 面积模型拆分绘制（v1.1 §17.3，far/fdr 键 4 行协议）：
   * 行1 "m × c =" 算式 + 行2-3 矢量分割矩形（5 条 drawLine：外框 4 + 竖中缝 1，
   * m 按块 50/50 视觉分割）+ 顶部块宽标签 + 矩形外左侧乘数 + 行4 作答位。
   * far（四年级）：m 两位数，整十 t | 个位 u 分割，子块积 t×c / u×c。
   * fdr（五年级）：m 一位小数（w.d），整数 w | 十分位 0.d 分割，子块积 w×c / 0.d×c。
   * 题面模式子块留白；答案模式子块积红色分解展示（连接竖式部分积概念）。
   * 返回 false = 键前缀/行1 解析不符 → 调用方退回 drawFigureLines 逐行文本兜底。
   */
  private static drawAreaModel(canvas: drawing.Canvas, text: string, item: SheetItem,
                               placed: PlacedItem, req: PageRenderRequest,
                               s: number, offsetY: number): boolean {
    const isFar: boolean = item.key.indexOf('far') === 0;
    const isFdr: boolean = item.key.indexOf('fdr') === 0;
    if (!isFar && !isFdr) {
      return false;
    }
    const lines: string[] = text.split('\n');
    if (lines.length < 4) {
      return false;
    }
    const seg: string[] = lines[0].split(' ');
    if (seg.length !== 4 || seg[1] !== '\u00d7' || seg[3] !== '=') {
      return false;
    }
    let topL: string = '';
    let topR: string = '';
    let side: string = '';
    let innerL: string = '';
    let innerR: string = '';
    if (isFar) {
      const m: number = Number(seg[0]);
      const c: number = Number(seg[2]);
      if (!(m >= 11 && m <= 49) || !(c >= 2 && c <= 99)) {
        return false; // Number 解析失败（NaN）同样落入区间外
      }
      const t: number = Math.floor(m / 10) * 10;
      const u: number = m - t;
      topL = String(t);
      topR = String(u);
      side = String(c);
      innerL = String(t * c);
      innerR = String(u * c);
    } else {
      const dotIdx: number = seg[0].indexOf('.');
      if (dotIdx < 0) {
        return false;
      }
      const w: number = Number(seg[0].substring(0, dotIdx));
      const d: number = Number(seg[0].substring(dotIdx + 1));
      const c: number = Number(seg[2]);
      if (!(w >= 1 && w <= 9) || !(d >= 1 && d <= 9) || !(c >= 2 && c <= 9)) {
        return false;
      }
      topL = String(w);
      topR = `0.${d}`;
      side = String(c);
      innerL = String(w * c);
      innerR = `${Math.floor(d * c / 10)}.${d * c % 10}`; // 0.d×c 一位小数（含补零 2.0）
    }
    const rowH: number = req.layout.rowHeight * s;
    const fontSize: number = Math.round(req.spec.fontSize * s);
    const y0: number = placed.y * s + offsetY;
    const rightX: number =
      (placed.x - SheetLayout.COL_INSET + req.layout.columnWidth - SheetLayout.COL_INSET) * s;
    const color: common2D.Color = req.showAnswers ? SheetRenderer.ANSWER_RED : SheetRenderer.TEXT_BLACK;
    SheetRenderer.drawText(canvas, lines[0], fontSize, Math.round(placed.x * s), Math.round(y0), color);
    SheetRenderer.drawText(canvas, lines[3], fontSize, Math.round(placed.x * s),
      Math.round(y0 + 3 * rowH), color);
    const rectTop: number = Math.round(y0 + rowH * 1.25);
    const rectBottom: number = Math.round(y0 + rowH * 2.35);
    const rectLeft: number = Math.round(placed.x * s + fontSize * 1.25);
    const rectRight: number = Math.round(rightX);
    const midX: number = Math.round((rectLeft + rectRight) / 2);
    const midY: number = Math.round((rectTop + rectBottom) / 2);
    const pen: drawing.Pen = new drawing.Pen();
    pen.setColor(color);
    pen.setStrokeWidth(Math.max(3, Math.round(3.5 * s)));
    canvas.attachPen(pen);
    canvas.drawLine(rectLeft, rectTop, rectRight, rectTop);
    canvas.drawLine(rectLeft, rectBottom, rectRight, rectBottom);
    canvas.drawLine(rectLeft, rectTop, rectLeft, rectBottom);
    canvas.drawLine(rectRight, rectTop, rectRight, rectBottom);
    canvas.drawLine(midX, rectTop, midX, rectBottom);
    canvas.detachPen();
    SheetRenderer.drawCenteredAt(canvas, topL, fontSize,
      Math.round((rectLeft + midX) / 2), Math.round(rectTop - fontSize * 0.35), color);
    SheetRenderer.drawCenteredAt(canvas, topR, fontSize,
      Math.round((midX + rectRight) / 2), Math.round(rectTop - fontSize * 0.35), color);
    const cFont: drawing.Font = SheetRenderer.makeFont(fontSize);
    const cW: number = cFont.measureText(side, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    SheetRenderer.drawText(canvas, side, fontSize,
      Math.round(rectLeft - fontSize * 0.15 - cW), Math.round(midY + fontSize * 0.35), color);
    if (req.showAnswers) {
      SheetRenderer.drawCenteredAt(canvas, innerL, fontSize,
        Math.round((rectLeft + midX) / 2), Math.round(midY + fontSize * 0.35), color);
      SheetRenderer.drawCenteredAt(canvas, innerR, fontSize,
        Math.round((midX + rectRight) / 2), Math.round(midY + fontSize * 0.35), color);
    }
    return true;
  }

  /** 指定中心 x 居中绘制（基线；供面积模型块心标签用）。 */
  private static drawCenteredAt(canvas: drawing.Canvas, text: string, fontSize: number,
                                centerX: number, baselineY: number, color: common2D.Color): void {
    const font: drawing.Font = SheetRenderer.makeFont(fontSize);
    const width: number = font.measureText(text, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    SheetRenderer.drawText(canvas, text, fontSize, Math.round(centerX - width / 2), baselineY, color);
  }

  /**
   * 分数乘整数面积模型绘制（v1.1 §17.3 第四批，ffr 键 4 行协议）：
   * 行1 "a/b × c =" 算式 + 行2-3 矢量条带（c = k·b：外框 4 线 + b−1 条组分割线，
   * 前 a 组画竖向阴影线表示 a/b）+ 顶部阴影区 a/b 标签 + 矩形外左侧 c + 行4 作答位。
   * 题面模式阴影区留白；答案模式阴影区心积红色 k·a。
   * 返回 false = 键前缀/行1 解析不符 → 调用方退回 drawFigureLines 逐行文本兜底。
   */
  private static drawFracArea(canvas: drawing.Canvas, text: string, item: SheetItem,
                              placed: PlacedItem, req: PageRenderRequest,
                              s: number, offsetY: number): boolean {
    if (item.key.indexOf('ffr') !== 0) {
      return false;
    }
    const lines: string[] = text.split('\n');
    if (lines.length < 4) {
      return false;
    }
    const seg: string[] = lines[0].split(' ');
    if (seg.length !== 4 || seg[1] !== '\u00d7' || seg[3] !== '=') {
      return false;
    }
    const slashIdx: number = seg[0].indexOf('/');
    if (slashIdx < 0) {
      return false;
    }
    const a: number = Number(seg[0].substring(0, slashIdx));
    const b: number = Number(seg[0].substring(slashIdx + 1));
    const c: number = Number(seg[2]);
    if (!(a >= 1 && a <= 5) || !(b >= 2 && b <= 6) || !(c >= 2 && c <= 24)) {
      return false; // Number 解析失败（NaN）同样落入区间外
    }
    const k: number = Math.round(c / b);
    if (k < 1 || k > 4 || k * b !== c) {
      return false;
    }
    const rowH: number = req.layout.rowHeight * s;
    const fontSize: number = Math.round(req.spec.fontSize * s);
    const y0: number = placed.y * s + offsetY;
    const rightX: number =
      (placed.x - SheetLayout.COL_INSET + req.layout.columnWidth - SheetLayout.COL_INSET) * s;
    const color: common2D.Color = req.showAnswers ? SheetRenderer.ANSWER_RED : SheetRenderer.TEXT_BLACK;
    SheetRenderer.drawText(canvas, lines[0], fontSize, Math.round(placed.x * s), Math.round(y0), color);
    SheetRenderer.drawText(canvas, lines[3], fontSize, Math.round(placed.x * s),
      Math.round(y0 + 3 * rowH), color);
    const rectTop: number = Math.round(y0 + rowH * 1.25);
    const rectBottom: number = Math.round(y0 + rowH * 2.35);
    const rectLeft: number = Math.round(placed.x * s + fontSize * 1.25);
    const rectRight: number = Math.round(rightX);
    const midY: number = Math.round((rectTop + rectBottom) / 2);
    const groupW: number = (rectRight - rectLeft) / b;
    const shadeRight: number = Math.round(rectLeft + a * groupW);
    const pen: drawing.Pen = new drawing.Pen();
    pen.setColor(color);
    pen.setStrokeWidth(Math.max(3, Math.round(3.5 * s)));
    canvas.attachPen(pen);
    canvas.drawLine(rectLeft, rectTop, rectRight, rectTop);
    canvas.drawLine(rectLeft, rectBottom, rectRight, rectBottom);
    canvas.drawLine(rectLeft, rectTop, rectLeft, rectBottom);
    canvas.drawLine(rectRight, rectTop, rectRight, rectBottom);
    for (let g: number = 1; g < b; g++) {
      const gx: number = Math.round(rectLeft + g * groupW);
      canvas.drawLine(gx, rectTop, gx, rectBottom);
    }
    canvas.detachPen();
    // 前 a 组竖向阴影线（a/b 的直观呈现；细于外框）
    const hatchPen: drawing.Pen = new drawing.Pen();
    hatchPen.setColor(color);
    hatchPen.setStrokeWidth(Math.max(2, Math.round(2 * s)));
    canvas.attachPen(hatchPen);
    const hatchStep: number = Math.max(3, Math.round(fontSize * 0.22));
    for (let g: number = 0; g < a; g++) {
      const gx0: number = Math.round(rectLeft + g * groupW);
      const gx1: number = Math.round(rectLeft + (g + 1) * groupW);
      for (let hx: number = gx0 + hatchStep; hx < gx1 - 1; hx += hatchStep) {
        canvas.drawLine(hx, rectTop + 1, hx, rectBottom - 1);
      }
    }
    canvas.detachPen();
    SheetRenderer.drawCenteredAt(canvas, `${a}/${b}`, fontSize,
      Math.round((rectLeft + shadeRight) / 2), Math.round(rectTop - fontSize * 0.35), color);
    const cFont: drawing.Font = SheetRenderer.makeFont(fontSize);
    const cW: number = cFont.measureText(String(c), drawing.TextEncoding.TEXT_ENCODING_UTF8);
    SheetRenderer.drawText(canvas, String(c), fontSize,
      Math.round(rectLeft - fontSize * 0.15 - cW), Math.round(midY + fontSize * 0.35), color);
    if (req.showAnswers) {
      SheetRenderer.drawCenteredAt(canvas, String(k * a), fontSize,
        Math.round((rectLeft + shadeRight) / 2), Math.round(midY + fontSize * 0.35), color);
    }
    return true;
  }

  /** 左定位绘制（基线）。 */
  private static drawText(canvas: drawing.Canvas, text: string, fontSize: number,
                          x: number, y: number, color: common2D.Color): void {
    const font: drawing.Font = SheetRenderer.makeFont(fontSize);
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(color);
    canvas.attachBrush(brush);
    canvas.drawTextBlob(drawing.TextBlob.makeFromString(text, font), x, y);
    canvas.detachBrush();
  }

  /** 页宽居中绘制（基线）。 */
  private static drawCenteredText(canvas: drawing.Canvas, text: string, fontSize: number,
                                  pageWidth: number, y: number, color: common2D.Color): void {
    const font: drawing.Font = SheetRenderer.makeFont(fontSize);
    const width: number = font.measureText(text, drawing.TextEncoding.TEXT_ENCODING_UTF8);
    SheetRenderer.drawText(canvas, text, fontSize, Math.round((pageWidth - width) / 2), y, color);
  }
}
