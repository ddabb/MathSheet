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
import { LayoutResult, LayoutSpec, PageLayout, SheetLayout } from '../core/SheetLayout';
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
  /** 题目黑色。 */
  private static readonly TEXT_BLACK: common2D.Color = { alpha: 255, red: 33, green: 33, blue: 33 };
  /** 打印字体（思源黑体，rawfile 加载一次缓存；失败回退系统字体）。 */
  private static typeface: drawing.Typeface | null = null;
  private static typefaceTried: boolean = false;

  /** 加载打印字体（幂等；渲染前调用，UI 层与测试层共用）。 */
  static ensureTypeface(): void {
    if (SheetRenderer.typefaceTried) {
      return;
    }
    SheetRenderer.typefaceTried = true;
    try {
      SheetRenderer.typeface = drawing.Typeface.makeFromRawFile($rawfile('font/SourceHanSansSC-Regular.ttf'));
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
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(req.showAnswers ? SheetRenderer.ANSWER_RED : SheetRenderer.TEXT_BLACK);
    canvas.attachBrush(brush);
    for (const placed of page.items) {
      const item: SheetItem = req.items[placed.index];
      const text: string = req.showAnswers ? item.answerText : item.questionText;
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
