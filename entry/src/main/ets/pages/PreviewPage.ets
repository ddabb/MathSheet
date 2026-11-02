/**
 * 预览页（计划 §5.1/§6.2/§6.3）：双模式。
 *
 * - 新鲜模式（无 sheetId）：参数 + 种子确定性重建（同参数同种子 = 同卷）；
 *   生成即物化入库（buildMultiSheetTraced 携带题型溯源），换一批 = 删旧存新；
 * - 卷库模式（sheetId）：加载物化卷（不重生成、隐藏换一批），供卷库重开/导出；
 * - 导出（M3）：保存图片（长图 → 相册）/ 导出 PDF（300dpi 页图 → A4 容器 → 保存到文件/分享）；
 * - 位图按需渲染 + 小缓存（LRU 6 页）+ renderEpoch 竞态守卫（沿用 M2 验证过的管线）。
 */

import { display } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { image } from '@kit.ImageKit';
import { Context } from '@kit.AbilityKit';
import { print, BusinessError } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { GradePresets, PresetEntry } from '../core/GradePresets';
import { SheetGen } from '../core/SheetGen';
import { SheetItem } from '../core/SheetModel';
import { LayoutResult, LayoutSpec, SheetLayout } from '../core/SheetLayout';
import { PageRenderRequest, SheetRenderer } from '../render/SheetRenderer';
import { PreviewParams, QuizParams } from '../common/PreviewParams';
import { StoredItem, StoredSheet, SheetCodec } from '../core/SheetCodec';
import { SheetStore } from '../core/SheetStore';
import { MemberScope } from '../core/ProfileCodec';
import { ProfileStore } from '../core/ProfileStore';
import { ExportUtil, ExportOutcome } from '../common/ExportUtil';
import { WIDE_CONTENT_MAX_VP, Toolbar, GhostButton, PrimaryButton } from '../components/UiKit';

/** 单套卷数据（题目 + 版面 + 该套规格；A/B/C/D 共享参数不同种子）。 */
class SheetSetData {
  items: SheetItem[] = [];
  layout: LayoutResult = new LayoutResult([], 0, 0, 0, 0, 0);
  spec: LayoutSpec = new LayoutSpec(3, 92, true, '');
  answerSpec: LayoutSpec = new LayoutSpec(3, 92, true, '');
  qPages: number = 0;
}

/** 页面视图描述（ForEach 数据源，键含套号与渲染态驱动位图到达后的重建）。 */
class PageViewData {
  idx: number = 0;
  bitmap: image.PixelMap | undefined = undefined;
  isAnswer: boolean = false;
}

@Entry
@Component
struct PreviewPage {
  @State current: number = 0;
  @State currentSet: number = 0;
  @State setCount: number = 1;
  @State qPages: number = 0;
  @State totalPages: number = 0;
  @State pageBitmaps: Array<Array<image.PixelMap | undefined>> = [];
  @State exporting: number = 0;
  /** 当前套是否可在线作答（未批改）。 */
  @State quizReady: boolean = false;

  private params: PreviewParams | null = null;
  private setsData: SheetSetData[] = [];
  private fieldsText: string = '';
  private backLabelStr: string = '';
  private renderScale: number = 0.4;
  private inFlight: Set<string> = new Set<string>();
  private renderEpoch: number = 0;
  private swiperController: SwiperController = new SwiperController();
  private langZh: boolean = true;
  private storedMode: boolean = false;
  private storedSheetId: string = '';
  private savedIds: string[] = [];
  private answerOn: boolean = true;
  private sheetTitle: string = '';
  private answerTitle: string = '';
  /** 当前成员存储作用域（页面存活期间成员不变，进入时缓存）。 */
  private storeScope: MemberScope = new MemberScope('');

  aboutToAppear(): void {
    const raw: PreviewParams = this.getUIContext().getRouter().getParams() as PreviewParams;
    if (raw === undefined) {
      this.back();
      return;
    }
    this.langZh = i18n.System.getSimplifiedLanguage().indexOf('zh') === 0;
    this.setupScale();
    const ctx0: Context | undefined = this.ctx();
    if (ctx0 !== undefined) {
      this.storeScope = ProfileStore.scopeCurrent(ctx0);
    }
    if (raw.sheetId !== undefined && raw.sheetId !== '') {
      this.openStored(raw.sheetId);
      return;
    }
    if (raw.typeIds === undefined || raw.typeIds.length === 0) {
      this.back();
      return;
    }
    this.params = raw;
    this.rebuild(raw.seed);
  }

  aboutToDisappear(): void {
    this.renderEpoch++;
    this.releaseAll();
  }

  /** 返回本页（在线作答完成/放弃后）刷新可作答态。 */
  onPageShow(): void {
    if (this.storedMode || this.savedIds.length > 0) {
      this.refreshQuizReady();
    }
  }

  /** 在线作答目标卷：卷库模式 = 本卷；新鲜模式 = 当前套物化卷。 */
  private currentQuizId(): string {
    if (this.storedMode) {
      return this.storedSheetId;
    }
    const id: string | undefined = this.savedIds[this.currentSet];
    return id !== undefined ? id : '';
  }

  private refreshQuizReady(): void {
    const id: string = this.currentQuizId();
    if (id === '') {
      this.quizReady = false;
      return;
    }
    const s: StoredSheet | null = SheetStore.loadSheet(this.storeScope, id);
    this.quizReady = s !== null && SheetCodec.gradedCountOf(s) === 0;
  }

  private startQuiz(): void {
    const id: string = this.currentQuizId();
    if (id === '') {
      return;
    }
    const params: QuizParams = { sheetId: id };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/QuizPage', params: params });
  }

  private setupScale(): void {
    const d: display.Display = display.getDefaultDisplaySync();
    const minDim: number = Math.min(d.width, d.height);
    this.renderScale = Math.min(0.5, Math.max(0.22, minDim * 0.94 / SheetLayout.PAGE_W));
  }

  private releaseAll(): void {
    for (const row of this.pageBitmaps) {
      for (const pm of row) {
        if (pm !== undefined) {
          pm.release();
        }
      }
    }
  }

  private ctx(): Context | undefined {
    return this.getUIContext().getHostContext();
  }

  private strOf(res: Resource): string {
    const rm = this.ctx()?.resourceManager;
    return rm === undefined ? '' : rm.getStringSync(res.id);
  }

  // ---------- 多套卷几何 ----------

  private setLetter(s: number): string {
    return String.fromCharCode(65 + s);
  }

  /** 套标题后缀（题头/答案页标题共用）。 */
  private setSuffix(s: number): string {
    const letter: string = this.setLetter(s);
    return this.langZh ? `（${letter}卷）` : ` · Sheet ${letter}`;
  }

  private totalPagesOfSet(s: number): number {
    const sd: SheetSetData | undefined = this.setsData[s];
    if (sd === undefined) {
      return 0;
    }
    return sd.qPages + (this.answerOn ? sd.qPages : 0);
  }

  // ---------- 模式一：新鲜生成（生成即入库） ----------

  /** 按基础种子重建全部套：traced 生成 → 版面 → 物化入库 → 重置位图。 */
  private rebuild(baseSeed: number): void {
    if (this.params === null) {
      return;
    }
    const entries: PresetEntry[] = [];
    for (const id of this.params.typeIds) {
      const e: PresetEntry | null = GradePresets.byId(id);
      if (e !== null) {
        entries.push(e);
      }
    }
    if (entries.length === 0) {
      this.back();
      return;
    }
    const grade: number = entries[0].grade;
    const ctx: Context | undefined = this.ctx();
    const rm = ctx !== undefined ? ctx.resourceManager : undefined;
    const titleRes: Resource = grade === 1 ? $r('app.string.sheet_title_g1')
      : grade === 2 ? $r('app.string.sheet_title_g2')
      : grade === 3 ? $r('app.string.sheet_title_g3')
      : grade === 4 ? $r('app.string.sheet_title_g4')
      : grade === 5 ? $r('app.string.sheet_title_g5')
      : $r('app.string.sheet_title_g2');
    this.sheetTitle = rm !== undefined ? rm.getStringSync(titleRes.id) : '';
    this.answerTitle = rm !== undefined ? rm.getStringSync($r('app.string.answer_sheet_title').id) : '';
    this.fieldsText = rm !== undefined ? rm.getStringSync($r('app.string.header_fields').id) : '';
    this.backLabelStr = rm !== undefined ? rm.getStringSync($r('app.string.back_label').id) : '';

    const sets: number = Math.max(1, Math.min(4, this.params.sets));
    const fontSize: number = LayoutSpec.fontSizeForColumns(this.params.columns);
    const now: number = Date.now();
    const data: SheetSetData[] = [];
    const sheets: StoredSheet[] = [];
    let duplicatesTotal: number = 0;
    for (let s = 0; s < sets; s++) {
      const collected = SheetGen.buildMultiSheetTraced(entries, baseSeed + s, this.params.count);
      duplicatesTotal += collected.duplicates;
      const sd: SheetSetData = new SheetSetData();
      const items: SheetItem[] = [];
      const storedItems: StoredItem[] = [];
      for (const t of collected.items) {
        items.push(t.item);
        storedItems.push(new StoredItem(t.item.questionText, t.item.answerText, t.item.key, t.presetId));
      }
      sd.items = items;
      const suffix: string = sets > 1 ? this.setSuffix(s) : '';
      sd.spec = new LayoutSpec(this.params.columns, fontSize, this.params.headerOn,
        this.sheetTitle + suffix);
      sd.answerSpec = new LayoutSpec(this.params.columns, fontSize, this.params.headerOn,
        this.answerTitle + suffix);
      sd.layout = SheetLayout.layout(sd.items.length, sd.spec, SheetLayout.lineCountsOf(sd.items));
      sd.qPages = sd.layout.pages.length;
      data.push(sd);
      const marks: number[] = [];
      for (let k = 0; k < storedItems.length; k++) {
        marks.push(0);
      }
      sheets.push(new StoredSheet(SheetStore.newId(), now, this.sheetTitle + suffix, grade,
        this.params.typeIds.slice(), storedItems.length, this.params.columns,
        this.params.headerOn, this.params.answerOn, baseSeed + s, storedItems, marks));
    }
    this.setsData = data;
    this.setCount = sets;
    this.answerOn = this.params.answerOn;
    this.storedMode = false;
    if (ctx !== undefined) {
      SheetStore.saveSheets(this.storeScope, sheets);
      const ids: string[] = [];
      for (const sh of sheets) {
        ids.push(sh.id);
      }
      this.savedIds = ids;
    }
    this.quizReady = true;
    this.resetView();
    if (rm !== undefined && duplicatesTotal === 0) {
      this.getUIContext().getPromptAction()
        .showToast({ message: rm.getStringSync($r('app.string.saved_to_library_toast').id), duration: 2000 });
    }
    if (duplicatesTotal > 0) {
      const msg: string = rm !== undefined
        ? rm.getStringSync($r('app.string.released_toast').id, duplicatesTotal)
        : `${duplicatesTotal}`;
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2500 });
    }
  }

  // ---------- 模式二：卷库重开（物化卷，不重生成） ----------

  private openStored(sheetId: string): void {
    const ctx: Context | undefined = this.ctx();
    if (ctx === undefined) {
      this.back();
      return;
    }
    const s: StoredSheet | null = SheetStore.loadSheet(this.storeScope, sheetId);
    if (s === null || s.items.length === 0) {
      this.back();
      return;
    }
    const rm = ctx.resourceManager;
    this.backLabelStr = rm.getStringSync($r('app.string.back_label').id);
    this.answerTitle = rm.getStringSync($r('app.string.answer_sheet_title').id);
    this.fieldsText = rm.getStringSync($r('app.string.header_fields').id);
    this.sheetTitle = s.title;
    this.storedMode = true;
    this.storedSheetId = s.id;
    this.answerOn = s.answerOn;
    const fontSize: number = LayoutSpec.fontSizeForColumns(s.columns);
    const sd: SheetSetData = new SheetSetData();
    const items: SheetItem[] = [];
    for (const it of s.items) {
      items.push(new SheetItem(it.q, it.a, it.key));
    }
    sd.items = items;
    sd.spec = new LayoutSpec(s.columns, fontSize, s.headerOn, s.title);
    sd.answerSpec = new LayoutSpec(s.columns, fontSize, s.headerOn, this.answerTitle);
    sd.layout = SheetLayout.layout(items.length, sd.spec, SheetLayout.lineCountsOf(items));
    sd.qPages = sd.layout.pages.length;
    this.setsData = [sd];
    this.setCount = 1;
    this.refreshQuizReady();
    this.resetView();
  }

  // ---------- 视图重置与渲染缓存 ----------

  private resetView(): void {
    this.renderEpoch++;
    this.releaseAll();
    const grid: Array<Array<image.PixelMap | undefined>> = [];
    for (let s = 0; s < this.setCount; s++) {
      const row: Array<image.PixelMap | undefined> = [];
      const total: number = this.totalPagesOfSet(s);
      for (let p = 0; p < total; p++) {
        row.push(undefined);
      }
      grid.push(row);
    }
    this.pageBitmaps = grid;
    this.inFlight.clear();
    this.currentSet = 0;
    this.current = 0;
    this.qPages = this.setsData[0].qPages;
    this.totalPages = this.totalPagesOfSet(0);
    this.ensureAround(0, 0);
  }

  /** 渲染当前页 ± 1（翻页预载）。 */
  private ensureAround(s: number, center: number): void {
    this.ensurePage(s, center - 1);
    this.ensurePage(s, center);
    this.ensurePage(s, center + 1);
  }

  private ensurePage(s: number, p: number): void {
    const total: number = this.totalPagesOfSet(s);
    if (p < 0 || p >= total) {
      return;
    }
    const row: Array<image.PixelMap | undefined> | undefined = this.pageBitmaps[s];
    if (row === undefined) {
      return;
    }
    if (row[p] !== undefined) {
      return;
    }
    const key: string = `${s}-${p}`;
    if (this.inFlight.has(key)) {
      return;
    }
    const sd: SheetSetData | undefined = this.setsData[s];
    if (sd === undefined) {
      return;
    }
    this.inFlight.add(key);
    const epoch: number = this.renderEpoch;
    const isAnswer: boolean = p >= sd.qPages;
    const inSheet: number = isAnswer ? p - sd.qPages : p;
    const req: PageRenderRequest = new PageRenderRequest(sd.items, sd.layout,
      isAnswer ? sd.answerSpec : sd.spec, inSheet, this.fmtPageLabel(s, p + 1, total),
      isAnswer ? '' : this.fieldsText, isAnswer, this.renderScale);
    SheetRenderer.renderPage(req).then((pm: image.PixelMap) => {
      this.inFlight.delete(key);
      if (epoch !== this.renderEpoch) {
        pm.release();
        return;
      }
      const grid: Array<Array<image.PixelMap | undefined>> = this.pageBitmaps.slice();
      const rowOld: Array<image.PixelMap | undefined> | undefined = grid[s];
      if (rowOld === undefined) {
        pm.release();
        return;
      }
      const rowNew: Array<image.PixelMap | undefined> = rowOld.slice();
      rowNew[p] = pm;
      grid[s] = rowNew;
      this.pageBitmaps = grid;
      this.trimCache();
    }).catch(() => {
      this.inFlight.delete(key);
    });
  }

  /** 位图缓存上限：超过 6 页按（套距 ×10000 + 页距）驱逐最远者（显式 release）。 */
  private trimCache(): void {
    const heldS: number[] = [];
    const heldP: number[] = [];
    for (let s = 0; s < this.pageBitmaps.length; s++) {
      const row: Array<image.PixelMap | undefined> | undefined = this.pageBitmaps[s];
      if (row === undefined) {
        continue;
      }
      for (let p = 0; p < row.length; p++) {
        if (row[p] !== undefined) {
          heldS.push(s);
          heldP.push(p);
        }
      }
    }
    while (heldS.length > 6) {
      let farIdx: number = 0;
      let farDist: number = -1;
      for (let k = 0; k < heldS.length; k++) {
        const dist: number = Math.abs(heldS[k] - this.currentSet) * 10000 + Math.abs(heldP[k] - this.current);
        if (dist > farDist) {
          farDist = dist;
          farIdx = k;
        }
      }
      const fs: number = heldS[farIdx];
      const fp: number = heldP[farIdx];
      heldS.splice(farIdx, 1);
      heldP.splice(farIdx, 1);
      const grid: Array<Array<image.PixelMap | undefined>> = this.pageBitmaps.slice();
      const rowOld: Array<image.PixelMap | undefined> | undefined = grid[fs];
      if (rowOld === undefined) {
        continue;
      }
      const rowNew: Array<image.PixelMap | undefined> = rowOld.slice();
      const pm: image.PixelMap | undefined = rowNew[fp];
      if (pm !== undefined) {
        pm.release();
      }
      rowNew[fp] = undefined;
      grid[fs] = rowNew;
      this.pageBitmaps = grid;
    }
  }

  // ---------- 导出（M3） ----------

  private exportBaseName(): string {
    if (this.storedMode) {
      return `sheet_${this.storedSheetId}`;
    }
    const id: string | undefined = this.savedIds[this.currentSet];
    return id !== undefined ? `sheet_${id}` : `sheet_${Date.now().toString(36)}`;
  }

  /** 当前套全部页请求（题页 + 答案页，顺序与预览一致）。 */
  private exportRequests(): PageRenderRequest[] {
    const sd: SheetSetData | undefined = this.setsData[this.currentSet];
    if (sd === undefined) {
      return [];
    }
    const total: number = this.totalPagesOfSet(this.currentSet);
    const reqs: PageRenderRequest[] = [];
    for (let g = 0; g < total; g++) {
      const isAnswer: boolean = g >= sd.qPages;
      const inSheet: number = isAnswer ? g - sd.qPages : g;
      reqs.push(new PageRenderRequest(sd.items, sd.layout,
        isAnswer ? sd.answerSpec : sd.spec, inSheet,
        this.fmtPageLabel(this.currentSet, g + 1, total),
        isAnswer ? '' : this.fieldsText, isAnswer, this.renderScale));
    }
    return reqs;
  }

  private exportFileName(): string {
    return this.titleText().replace('/', '_');
  }

  private exportPdf(): void {
    if (this.exporting !== 0) {
      return;
    }
    const ctx: Context | undefined = this.ctx();
    const reqs: PageRenderRequest[] = this.exportRequests();
    if (ctx === undefined || reqs.length === 0) {
      return;
    }
    this.exporting = 1;
    ExportUtil.composePdf(ctx, reqs, this.exportBaseName()).then((pdfPath: string | null) => {
      this.exporting = 0;
      if (pdfPath === null) {
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.export_pdf_fail'), duration: 2500 });
        return;
      }
      const prompt = this.getUIContext().getPromptAction();
      prompt.showActionMenu({
        title: $r('app.string.export_pdf_done'),
        buttons: [
          { text: $r('app.string.save_to_files'), color: $r('app.color.primary_text') },
          { text: $r('app.string.share'), color: $r('app.color.primary_text') }
        ]
      }).then((data) => {
        if (data.index === 0) {
          this.savePdf(pdfPath);
        } else if (data.index === 1) {
          this.sharePdf(pdfPath);
        }
      }).catch(() => {
      });
    });
  }

  private savePdf(pdfPath: string): void {
    const ui = this.getUIContext();
    ExportUtil.saveToDocument(ui, pdfPath, this.exportFileName(), '.pdf')
      .then((outcome: number) => {
        const res: Resource = outcome === ExportOutcome.SAVED ? $r('app.string.saved_toast')
          : outcome === ExportOutcome.CANCEL ? $r('app.string.export_cancel_toast')
            : $r('app.string.export_pdf_fail');
        ui.getPromptAction().showToast({ message: res, duration: 2000 });
      });
  }

  private sharePdf(pdfPath: string): void {
    ExportUtil.shareFile(this.getUIContext(), pdfPath, '.pdf');
  }

  // ---------- 打印直连（1.0.1 M4） ----------

  /**
   * 当前预览卷打印直连：沙箱合成 PDF → fileUri 拉起系统打印预览，
   * 跳过「存 PDF」中间步；失败降级提示走「导出 PDF」（并存保留）。
   * 多套卷（M5）：当前套送印，提示切换套号逐套打印。
   */
  private printSheet(): void {
    if (this.exporting !== 0) {
      return;
    }
    const ctx: Context | undefined = this.ctx();
    const reqs: PageRenderRequest[] = this.exportRequests();
    if (ctx === undefined || reqs.length === 0) {
      return;
    }
    this.exporting = 1;
    if (this.setCount > 1) {
      this.getUIContext().getPromptAction().showToast({
        message: this.strOf($r('app.string.print_sets_hint'))
          .replace('%s', this.setLetter(this.currentSet)),
        duration: 3000
      });
    }
    ExportUtil.composePdf(ctx, reqs, this.exportBaseName()).then((pdfPath: string | null) => {
      if (pdfPath === null) {
        this.exporting = 0;
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.export_pdf_fail'), duration: 2500 });
        return;
      }
      print.print([fileUri.getUriFromPath(pdfPath)], ctx)
        .then((task: print.PrintTask) => {
          this.exporting = 0;
          task.on('fail', (): void => {
            this.getUIContext().getPromptAction()
              .showToast({ message: $r('app.string.print_fail'), duration: 2500 });
          });
        })
        .catch((_err: BusinessError) => {
          this.exporting = 0;
          this.getUIContext().getPromptAction()
            .showToast({ message: $r('app.string.print_fail'), duration: 2500 });
        });
    }).catch(() => {
      this.exporting = 0;
      this.getUIContext().getPromptAction()
        .showToast({ message: $r('app.string.export_pdf_fail'), duration: 2500 });
    });
  }

  private saveImage(): void {
    if (this.exporting !== 0) {
      return;
    }
    const ctx: Context | undefined = this.ctx();
    const reqs: PageRenderRequest[] = this.exportRequests();
    if (ctx === undefined || reqs.length === 0) {
      return;
    }
    this.exporting = 2;
    ExportUtil.composeLongPng(ctx, reqs, this.exportBaseName()).then((pngPath: string | null) => {
      this.exporting = 0;
      if (pngPath === null) {
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.save_image_fail'), duration: 2500 });
        return;
      }
      const ui = this.getUIContext();
      ExportUtil.saveImageToAlbum(ui, pngPath, this.exportFileName())
        .then((outcome: number) => {
          const res: Resource = outcome === ExportOutcome.SAVED ? $r('app.string.save_image_done')
            : outcome === ExportOutcome.CANCEL ? $r('app.string.export_cancel_toast')
              : $r('app.string.save_image_fail');
          ui.getPromptAction().showToast({ message: res, duration: 2000 });
        });
    });
  }

  // ---------- 标签与文案 ----------

  private fmtPageLabel(s: number, pageNo: number, total: number): string {
    const ctx: Context | undefined = this.ctx();
    if (ctx === undefined) {
      return `${pageNo} / ${total}`;
    }
    if (this.setCount > 1) {
      return ctx.resourceManager.getStringSync($r('app.string.page_label_set').id,
        this.setLetter(s), pageNo, total);
    }
    return ctx.resourceManager.getStringSync($r('app.string.page_label').id, pageNo, total);
  }

  private titleText(): string {
    const sd: SheetSetData | undefined = this.setsData[this.currentSet];
    if (sd === undefined) {
      return this.sheetTitle;
    }
    if (this.storedMode) {
      return sd.spec.title;
    }
    return this.setCount > 1 ? this.sheetTitle + this.setSuffix(this.currentSet) : this.sheetTitle;
  }

  private isAnswerPage(): boolean {
    return this.current >= this.qPages;
  }

  // ---------- 交互 ----------

  private switchSet(s: number): void {
    if (s === this.currentSet || s < 0 || s >= this.setCount) {
      return;
    }
    this.currentSet = s;
    this.current = 0;
    this.qPages = this.setsData[s].qPages;
    this.totalPages = this.totalPagesOfSet(s);
    this.ensureAround(s, 0);
    this.refreshQuizReady();
    this.swiperController.changeIndex(0, false);
  }

  /** 换一批（新鲜模式）：删本会话旧卷 → 新种子重建（重建再入库）。 */
  private changeBatch(): void {
    if (this.storedMode || this.params === null) {
      return;
    }
    const ctx: Context | undefined = this.ctx();
    if (ctx !== undefined && this.savedIds.length > 0) {
      SheetStore.removeSheets(this.storeScope, this.savedIds);
    }
    this.savedIds = [];
    const newSeed: number = Math.floor(Math.random() * 2147483647);
    this.params.seed = newSeed;
    this.rebuild(newSeed);
    this.swiperController.changeIndex(0, false);
  }

  private back(): void {
    this.getUIContext().getRouter().back();
  }

  private pageViews(): PageViewData[] {
    const out: PageViewData[] = [];
    const row: Array<image.PixelMap | undefined> | undefined = this.pageBitmaps[this.currentSet];
    for (let i = 0; i < this.totalPages; i++) {
      const v: PageViewData = new PageViewData();
      v.idx = i;
      v.bitmap = row !== undefined ? row[i] : undefined;
      v.isAnswer = i >= this.qPages;
      out.push(v);
    }
    return out;
  }

  private setChips(): string[] {
    const out: string[] = [];
    for (let s = 0; s < this.setCount; s++) {
      out.push(this.setLetter(s));
    }
    return out;
  }

  @Builder
  pageStatusLeading() {
    Text(`${this.current + 1} / ${this.totalPages}`)
      .fontSize(13)
      .fontColor($r('app.color.secondary_text'))
  }

  @Builder
  actionsTrailing() {
    Row({ space: 10 }) {
      if (!this.storedMode) {
        GhostButton({
          label: this.strOf($r('app.string.change_batch')),
          icon: '🔄',
          onTap: () => this.changeBatch()
        })
      }
      GhostButton({
        label: this.strOf($r('app.string.save_image_button')),
        icon: '🖼️',
        onTap: () => this.saveImage()
      })
      PrimaryButton({
        label: this.strOf($r('app.string.export_pdf_button')),
        icon: '📄',
        onTap: () => this.exportPdf()
      })
    }
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack() {
      Column() {
        // 顶栏：返回 │ 标题（答案页红色角标）│ A/B/C/D 套切换
        Row() {
          Text(`‹ ${this.backLabelStr}`)
            .fontSize(15)
            .fontColor($r('app.color.brand'))
            .onClick(() => this.back())
          Blank()
          Column({ space: 3 }) {
            Text(this.titleText())
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.isAnswerPage()) {
              Text(this.answerTitle)
                .fontSize(10)
                .fontColor($r('app.color.danger_red'))
                .backgroundColor($r('app.color.answer_tint'))
                .borderRadius(7)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            }
          }
          .alignItems(HorizontalAlign.Center)
          .constraintSize({ maxWidth: '58%' })
          Blank()
          if (this.setCount > 1) {
            Row({ space: 6 }) {
              ForEach(this.setChips(), (letter: string, i: number) => {
                Text(letter)
                  .fontSize(12)
                  .fontWeight(i === this.currentSet ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(i === this.currentSet ? $r('app.color.on_accent_text')
                    : $r('app.color.secondary_text'))
                  .backgroundColor(i === this.currentSet ? $r('app.color.brand')
                    : $r('app.color.card_background'))
                  .width(26)
                  .height(26)
                  .borderRadius(13)
                  .textAlign(TextAlign.Center)
                  .onClick(() => this.switchSet(i))
              }, (letter: string) => letter)
            }
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // 页区：Swiper 逐页位图
        Swiper(this.swiperController) {
          ForEach(this.pageViews(), (v: PageViewData) => {
            if (v.bitmap !== undefined) {
              Image(v.bitmap)
                .width('94%')
                .height('94%')
                .objectFit(ImageFit.Contain)
                .borderRadius(6)
            } else {
              Column({ space: 12 }) {
                LoadingProgress()
                  .width(40)
                  .height(40)
                Text(`${v.idx + 1} / ${this.totalPages}`)
                  .fontSize(13)
                  .fontColor($r('app.color.hint_text'))
              }
              .justifyContent(FlexAlign.Center)
            }
          }, (v: PageViewData) => `${this.currentSet}-${v.idx}-${v.bitmap !== undefined}`)
        }
        .index(this.current)
        .indicator(false)
        .loop(false)
        .layoutWeight(1)
        .width('100%')
        .onChange((idx: number) => {
          this.current = idx;
          this.ensureAround(this.currentSet, idx);
        })

        // 底部固定区（1.0.1 M4）：在线作答（未批改卷展示）+ 打印直连主操作
        Row({ space: 12 }) {
          if (this.quizReady) {
            PrimaryButton({
              label: this.strOf($r('app.string.quiz_entry_button')),
              icon: '✍️',
              onTap: () => this.startQuiz()
            })
            .layoutWeight(1)
          }
          PrimaryButton({
            label: this.strOf($r('app.string.print_button')),
            icon: '🖨️',
            onTap: () => this.printSheet()
          })
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })

        // 底栏：左侧页码状态 + 右侧操作（换一批/存图 幽灵，导出 PDF 主操作）
        Toolbar({
          leading: (): void => {
            this.pageStatusLeading();
          },
          trailing: (): void => {
            this.actionsTrailing();
          }
        })
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })

      // 导出遮罩（居中圆角卡片，配色与 Token 一致）
      if (this.exporting !== 0) {
        Column() {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(42)
              .height(42)
              .color(Color.White)
            Text(this.exporting === 1 ? $r('app.string.export_pdf_composing')
              : $r('app.string.save_image_composing'))
              .fontSize(14)
              .fontColor(Color.White)
          }
          .padding(24)
          .backgroundColor('#CC1A1D29')
          .borderRadius($r('app.float.radius_xl'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
