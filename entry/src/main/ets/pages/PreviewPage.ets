/**
 * 预览页（计划 §5.1/§6.3）：按路由参数确定性重建（同参数同种子 = 同卷），
 * 逐页位图渲染（drawing.Font 管线，思源黑体）+ Swiper 翻页 + 换一批（新种子）。
 * - 题目页黑色题面；答案页（开关开启时追加于后）红色完整式；
 * - 位图按需渲染 + 小缓存（远离当前页先驱逐，PixelMap 显式 release）；
 * - 可行域不足放行数 toast 说明（计划 §5.2 反馈约定）。
 * 导出（PDF/PNG）属 M3 批次，随 PdfCodec 移植接入。
 */

import { display } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { GradePresets, PresetEntry } from '../core/GradePresets';
import { SheetGen } from '../core/SheetGen';
import { SheetItem } from '../core/SheetModel';
import { LayoutResult, LayoutSpec, SheetLayout } from '../core/SheetLayout';
import { PageRenderRequest, SheetRenderer } from '../render/SheetRenderer';
import { PreviewParams } from '../common/PreviewParams';

/** 页面视图描述（ForEach 数据源，键含渲染态驱动位图到达后的重建）。 */
class PageViewData {
  idx: number = 0;
  bitmap: image.PixelMap | undefined = undefined;
  isAnswer: boolean = false;
}

@Entry
@Component
struct PreviewPage {
  @State current: number = 0;
  @State totalPages: number = 0;
  @State qPages: number = 0;
  @State sheetTitle: string = '';
  @State answerTitle: string = '';
  @State pageBitmaps: Array<image.PixelMap | undefined> = [];

  private params: PreviewParams | null = null;
  private items: SheetItem[] = [];
  private layout: LayoutResult = new LayoutResult([], 0, 0, 0, 0, 0);
  private spec: LayoutSpec = new LayoutSpec(3, 92, true, '');
  private answerSpec: LayoutSpec = new LayoutSpec(3, 92, true, '');
  private fieldsText: string = '';
  private backLabelStr: string = '';
  private renderScale: number = 0.4;
  private inFlight: Set<number> = new Set<number>();
  private renderEpoch: number = 0;
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    const raw: PreviewParams = this.getUIContext().getRouter().getParams() as PreviewParams;
    if (raw === undefined || raw.typeIds === undefined || raw.typeIds.length === 0) {
      this.back();
      return;
    }
    this.params = raw;
    this.setupScale();
    this.rebuild(raw.seed);
  }

  aboutToDisappear(): void {
    this.renderEpoch++;
    for (const pm of this.pageBitmaps) {
      if (pm !== undefined) {
        pm.release();
      }
    }
  }

  private setupScale(): void {
    const d: display.Display = display.getDefaultDisplaySync();
    const minDim: number = Math.min(d.width, d.height);
    this.renderScale = Math.min(0.5, Math.max(0.22, minDim * 0.94 / SheetLayout.PAGE_W));
  }

  /** 按种子重建整卷（生成 → 版面 → 重置位图 → 渲染首页）。 */
  private rebuild(seed: number): void {
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
    const ctx = this.getUIContext().getHostContext();
    const rm = ctx !== undefined ? ctx.resourceManager : undefined;
    this.sheetTitle = grade === 1 ? (rm !== undefined ? rm.getStringSync($r('app.string.sheet_title_g1').id) : '')
      : grade === 3 ? (rm !== undefined ? rm.getStringSync($r('app.string.sheet_title_g3').id) : '')
        : (rm !== undefined ? rm.getStringSync($r('app.string.sheet_title_g2').id) : '');
    this.answerTitle = rm !== undefined ? rm.getStringSync($r('app.string.answer_sheet_title').id) : '';
    this.fieldsText = rm !== undefined ? rm.getStringSync($r('app.string.header_fields').id) : '';
    this.backLabelStr = rm !== undefined ? rm.getStringSync($r('app.string.back_label').id) : '';
    const collected = SheetGen.buildMultiSheet(entries, seed, this.params.count);
    this.items = collected.items;
    const fontSize: number = LayoutSpec.fontSizeForColumns(this.params.columns);
    this.spec = new LayoutSpec(this.params.columns, fontSize, this.params.headerOn, this.sheetTitle);
    this.answerSpec = new LayoutSpec(this.params.columns, fontSize, this.params.headerOn, this.answerTitle);
    this.layout = SheetLayout.layout(this.items.length, this.spec);
    this.qPages = this.layout.pages.length;
    this.totalPages = this.qPages + (this.params.answerOn ? this.qPages : 0);

    this.renderEpoch++;
    for (const pm of this.pageBitmaps) {
      if (pm !== undefined) {
        pm.release();
      }
    }
    const arr: Array<image.PixelMap | undefined> = [];
    for (let i = 0; i < this.totalPages; i++) {
      arr.push(undefined);
    }
    this.pageBitmaps = arr;
    this.inFlight.clear();
    this.current = 0;
    this.ensureAround(0);
    if (collected.duplicates > 0) {
      const msg: string = rm !== undefined
        ? rm.getStringSync($r('app.string.released_toast').id, collected.duplicates)
        : `${collected.duplicates}`;
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2500 });
    }
  }

  /** 渲染当前页 ± 1（翻页预载）。 */
  private ensureAround(center: number): void {
    this.ensurePage(center - 1);
    this.ensurePage(center);
    this.ensurePage(center + 1);
  }

  private ensurePage(idx: number): void {
    if (idx < 0 || idx >= this.totalPages) {
      return;
    }
    if (this.pageBitmaps[idx] !== undefined || this.inFlight.has(idx)) {
      return;
    }
    this.inFlight.add(idx);
    const epoch: number = this.renderEpoch;
    const isAnswer: boolean = idx >= this.qPages;
    const inSheet: number = isAnswer ? idx - this.qPages : idx;
    const pageLabel: string = this.fmtPageLabel(idx + 1, this.totalPages);
    const fields: string = isAnswer ? '' : this.fieldsText;
    const req: PageRenderRequest = new PageRenderRequest(this.items, this.layout,
      isAnswer ? this.answerSpec : this.spec, inSheet, pageLabel, fields, isAnswer, this.renderScale);
    SheetRenderer.renderPage(req).then((pm: image.PixelMap) => {
      this.inFlight.delete(idx);
      if (epoch !== this.renderEpoch) {
        pm.release();
        return;
      }
      const arr: Array<image.PixelMap | undefined> = this.pageBitmaps.slice();
      arr[idx] = pm;
      this.pageBitmaps = arr;
      this.trimCache();
    }).catch(() => {
      this.inFlight.delete(idx);
    });
  }

  /** 位图缓存上限：超过 6 页驱逐离当前页最远者（显式 release）。 */
  private trimCache(): void {
    let held: number[] = [];
    for (let i = 0; i < this.pageBitmaps.length; i++) {
      if (this.pageBitmaps[i] !== undefined) {
        held.push(i);
      }
    }
    while (held.length > 6) {
      let far: number = held[0];
      let farDist: number = Math.abs(far - this.current);
      for (const i of held) {
        const d: number = Math.abs(i - this.current);
        if (d > farDist) {
          far = i;
          farDist = d;
        }
      }
      const pm: image.PixelMap | undefined = this.pageBitmaps[far];
      if (pm !== undefined) {
        pm.release();
      }
      const arr: Array<image.PixelMap | undefined> = this.pageBitmaps.slice();
      arr[far] = undefined;
      this.pageBitmaps = arr;
      held = held.filter((v: number) => v !== far);
    }
  }

  private fmtPageLabel(pageNo: number, total: number): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return `${pageNo} / ${total}`;
    }
    return ctx.resourceManager.getStringSync($r('app.string.page_label').id, pageNo, total);
  }

  private isAnswerPage(): boolean {
    return this.current >= this.qPages;
  }

  private changeBatch(): void {
    if (this.params === null) {
      return;
    }
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
    for (let i = 0; i < this.totalPages; i++) {
      const v: PageViewData = new PageViewData();
      v.idx = i;
      v.bitmap = this.pageBitmaps[i];
      v.isAnswer = i >= this.qPages;
      out.push(v);
    }
    return out;
  }

  build() {
    Column() {
      // 顶栏：返回 │ 标题（当前页为答案页时切换） │ 换一批
      Row({ space: 12 }) {
        Text(`‹ ${this.backLabelStr}`)
          .fontSize(15)
          .fontColor($r('app.color.brand'))
          .onClick(() => this.back())
        Blank()
        Row({ space: 6 }) {
          Text(this.isAnswerPage() ? this.answerTitle : this.sheetTitle)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isAnswerPage() ? $r('app.color.danger_red') : $r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Blank()
        Text($r('app.string.change_batch'))
          .fontSize(15)
          .fontColor($r('app.color.brand'))
          .onClick(() => this.changeBatch())
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
        }, (v: PageViewData) => `${v.idx}-${v.bitmap !== undefined}`)
      }
      .index(this.current)
      .indicator(false)
      .loop(false)
      .layoutWeight(1)
      .width('100%')
      .onChange((idx: number) => {
        this.current = idx;
        this.ensureAround(idx);
      })

      // 底栏：页码指示
      Row({ space: 8 }) {
        Text(`${this.current + 1} / ${this.totalPages}`)
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .height(42)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
