/**
 * M4 批改页（计划 §4.1 / §5.1）：大字逐题对照 → ✓/✗ 圆钮标记。
 *
 * - 数据流：卷库卡片（sheetId）→ SheetStore 物化卷 → 逐题批改；
 * - 每次标记即持久化（SheetStore.updateSheet），中途退出进度保留、可续批；
 * - 全部批完自动提交错题本（MistakeStore.commitSheet，幂等）并展示小结；
 * - 未批完退出需确认（进度已保存提示）；
 * - 快速批改：对照纸质答案页速录——点选做错的题，其余自动记对；
 * - 小结：批改用时速记（durationSec，入库随卷持久化）+ 本卷错题一键重练。
 */

import { Context } from '@kit.AbilityKit';
import { StoredItem, StoredSheet } from '../core/SheetCodec';
import { SheetStore } from '../core/SheetStore';
import { MistakeStore } from '../core/MistakeStore';
import { MistakeEntry } from '../core/MistakeCodec';
import { MemberScope } from '../core/ProfileCodec';
import { ProfileStore } from '../core/ProfileStore';
import { GradeParams, PreviewParams } from '../common/PreviewParams';
import { DrillFlow } from '../common/DrillFlow';
import { WIDE_CONTENT_MAX_VP } from '../components/UiKit';

/** 用时速记档位（秒；0 = 不记录）。 */
const DURATION_OPTIONS: number[] = [0, 120, 180, 240, 300, 480, 600, 900];

@Entry
@Component
struct GradePage {
  @State sheet: StoredSheet | null = null;
  @State marks: number[] = [];
  @State idx: number = 0;
  @State done: boolean = false;
  @State rightTotal: number = 0;
  @State wrongTotal: number = 0;
  @State quickMode: boolean = false;
  @State quickWrong: boolean[] = [];
  @State durationSec: number = 0;
  private sheetId: string = '';
  private backLabelStr: string = '';
  /** 当前成员存储作用域（页面存活期间成员不变，进入时缓存）。 */
  private storeScope: MemberScope = new MemberScope('');

  aboutToAppear(): void {
    const raw: GradeParams = this.getUIContext().getRouter().getParams() as GradeParams;
    if (raw === undefined || raw.sheetId === undefined || raw.sheetId === '') {
      this.back();
      return;
    }
    this.sheetId = raw.sheetId;
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.back();
      return;
    }
    this.storeScope = ProfileStore.scopeCurrent(ctx);
    const s: StoredSheet | null = SheetStore.loadSheet(this.storeScope, this.sheetId);
    if (s === null || s.items.length === 0) {
      this.back();
      return;
    }
    const rm = ctx.resourceManager;
    this.backLabelStr = rm.getStringSync($r('app.string.back_label').id);
    this.sheet = s;
    this.marks = s.marks.slice();
    this.durationSec = s.durationSec;
    this.recount();
    this.done = this.graded() >= s.items.length;
    this.idx = this.nextUnmarked(0);
  }

  // ---------- 统计与推进 ----------

  private graded(): number {
    let n: number = 0;
    for (const m of this.marks) {
      if (m !== 0) {
        n++;
      }
    }
    return n;
  }

  private recount(): void {
    let right: number = 0;
    let wrong: number = 0;
    for (const m of this.marks) {
      if (m === 1) {
        right++;
      } else if (m === 2) {
        wrong++;
      }
    }
    this.rightTotal = right;
    this.wrongTotal = wrong;
  }

  /** 自 from 起环形寻找首个未批题（无则 -1）。 */
  private nextUnmarked(from: number): number {
    const n: number = this.marks.length;
    for (let k: number = 0; k < n; k++) {
      const i: number = (from + k) % n;
      if (this.marks[i] === 0) {
        return i;
      }
    }
    return -1;
  }

  // ---------- 交互：逐题批改 ----------

  private mark(v: number): void {
    const s: StoredSheet | null = this.sheet;
    if (this.done || s === null || this.idx >= this.marks.length) {
      return;
    }
    this.marks[this.idx] = v;
    this.marks = this.marks.slice();
    s.marks = this.marks.slice();
    this.recount();
    SheetStore.updateSheet(this.storeScope, s);
    const next: number = this.nextUnmarked(this.idx + 1);
    if (next < 0) {
      this.finish(s);
      return;
    }
    this.idx = next;
  }

  // ---------- 交互：快速批改（对照答案页速录错题） ----------

  private toggleQuick(): void {
    if (this.quickMode) {
      this.quickMode = false;
      return;
    }
    const s: StoredSheet | null = this.sheet;
    if (s === null) {
      return;
    }
    const qw: boolean[] = [];
    for (let i: number = 0; i < s.items.length; i++) {
      qw.push(this.marks[i] === 2);
    }
    this.quickWrong = qw;
    this.quickMode = true;
  }

  private toggleQuickWrong(i: number): void {
    if (i < 0 || i >= this.quickWrong.length) {
      return;
    }
    const qw: boolean[] = this.quickWrong.slice();
    qw[i] = !qw[i];
    this.quickWrong = qw;
  }

  /** 点选错题 → 未选自动记对 → 整卷落库并收尾。 */
  private applyQuick(): void {
    const s: StoredSheet | null = this.sheet;
    if (s === null || this.done || this.quickWrong.length !== s.items.length) {
      return;
    }
    const marks: number[] = [];
    for (let i: number = 0; i < s.items.length; i++) {
      marks.push(this.quickWrong[i] ? 2 : 1);
    }
    this.marks = marks;
    s.marks = marks.slice();
    this.recount();
    SheetStore.updateSheet(this.storeScope, s);
    this.quickMode = false;
    this.finish(s);
  }

  // ---------- 交互：小结（用时速记 / 错题重练） ----------

  private pickDuration(sec: number): void {
    const s: StoredSheet | null = this.sheet;
    if (s === null || this.durationSec === sec) {
      return;
    }
    this.durationSec = sec;
    s.durationSec = sec;
    SheetStore.updateSheet(this.storeScope, s);
  }

  private durationChipLabel(sec: number): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    const rm = ctx.resourceManager;
    if (sec === 0) {
      return rm.getStringSync($r('app.string.grade_duration_none').id);
    }
    if (sec % 60 === 0) {
      return rm.getStringSync($r('app.string.grade_duration_min').id, sec / 60);
    }
    return rm.getStringSync($r('app.string.grade_duration_ms').id,
      Math.floor(sec / 60), sec % 60);
  }

  /** 本卷错题 1:2 混编重练卷：入库 → 提示 → 跳预览（卷库模式）。 */
  private drillFromSummary(): void {
    const s: StoredSheet | null = this.sheet;
    if (s === null || this.wrongTotal === 0) {
      return;
    }
    const now: number = Date.now();
    const mistakes: MistakeEntry[] = [];
    for (let i: number = 0; i < s.items.length && i < s.marks.length; i++) {
      if (s.marks[i] === 2) {
        const it: StoredItem = s.items[i];
        mistakes.push(new MistakeEntry(it.key, it.q, it.a, it.p, s.id, s.title, 1, now));
      }
    }
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || mistakes.length === 0) {
      return;
    }
    const title: string = ctx.resourceManager.getStringSync($r('app.string.mistakes_drill_title').id);
    const drill: StoredSheet | null = DrillFlow.buildDrillSheet(this.storeScope, mistakes, title);
    if (drill === null) {
      return;
    }
    this.getUIContext().getPromptAction()
      .showToast({ message: $r('app.string.mistakes_drill_toast'), duration: 2000 });
    const params: PreviewParams = {
      typeIds: [],
      seed: 0,
      count: 0,
      columns: 3,
      headerOn: true,
      answerOn: true,
      sets: 1,
      sheetId: drill.id
    };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PreviewPage', params: params });
  }

  // ---------- 收尾 ----------

  /** 全部批完：提交错题本（幂等）+ 小结。 */
  private finish(s: StoredSheet): void {
    this.done = true;
    MistakeStore.commitSheet(this.storeScope, s);
    const res: Resource = this.wrongTotal > 0
      ? $r('app.string.grade_commit_toast') : $r('app.string.grade_all_correct_toast');
    this.getUIContext().getPromptAction().showToast({ message: res, duration: 2000 });
  }

  private back(): void {
    this.getUIContext().getRouter().back();
  }

  /** 未批完且已有进度时拦截返回，弹确认（进度已自动保存）。 */
  onBackPress(): boolean {
    if (this.done || this.graded() === 0) {
      return false;
    }
    const param: AlertDialogParamWithButtons = {
      title: $r('app.string.grade_exit_title'),
      message: $r('app.string.grade_exit_msg'),
      autoCancel: false,
      primaryButton: {
        value: $r('app.string.grade_exit_keep'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.grade_exit_leave'),
        action: () => {
          this.back();
        }
      }
    };
    this.getUIContext().showAlertDialog(param);
    return true;
  }

  // ---------- 构建辅助 ----------

  private summaryText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || this.sheet === null) {
      return '';
    }
    return ctx.resourceManager.getStringSync($r('app.string.grade_done_summary').id,
      this.sheet.items.length, this.rightTotal, this.wrongTotal);
  }

  private progressText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || this.sheet === null) {
      return '';
    }
    return ctx.resourceManager.getStringSync($r('app.string.grade_progress').id,
      this.graded(), this.sheet.items.length);
  }

  @Builder
  MarkButton(symbol: string, label: Resource, filled: Resource, onTap: () => void) {
    Column({ space: 6 }) {
      Text(symbol)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor(filled)
        .width(64)
        .height(64)
        .borderRadius(32)
        .textAlign(TextAlign.Center)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
    }
    .alignItems(HorizontalAlign.Center)
    .onClick(() => onTap())
  }

  build() {
    Column() {
      // 顶栏：返回 │ 标题 + 进度 │ 批改模式切换
      Row() {
        Text(`‹ ${this.backLabelStr}`)
          .fontSize(15)
          .fontColor($r('app.color.brand'))
          .onClick(() => this.back())
        Blank()
        Column({ space: 3 }) {
          Text(this.sheet === null ? '' : this.sheet.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.progressText())
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
        }
        .alignItems(HorizontalAlign.Center)
        .constraintSize({ maxWidth: '56%' })
        Blank()
        if (this.sheet !== null && !this.done) {
          Text(this.quickMode ? $r('app.string.grade_step_mode') : $r('app.string.grade_quick_mode'))
            .fontSize(13)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.brand_tint'))
            .borderRadius(13)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => this.toggleQuick())
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      if (this.sheet !== null && this.done) {
        // 批改小结
        Column({ space: 14 }) {
          Blank()
          Text('✓')
            .fontSize(52)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.success_green'))
          Text($r('app.string.grade_done_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text(this.summaryText())
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
          // 用时速记（随卷持久化，卷库列表可见）
          Column({ space: 8 }) {
            Text($r('app.string.grade_duration_label'))
              .fontSize(12)
              .fontColor($r('app.color.hint_text'))
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap,
              justifyContent: FlexAlign.Center }) {
              ForEach(DURATION_OPTIONS, (sec: number) => {
                Text(this.durationChipLabel(sec))
                  .fontSize(13)
                  .fontWeight(this.durationSec === sec ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.durationSec === sec ? $r('app.color.on_accent_text')
                    : $r('app.color.chip_text'))
                  .backgroundColor(this.durationSec === sec ? $r('app.color.brand')
                    : $r('app.color.chip_bg'))
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => this.pickDuration(sec))
              }, (sec: number) => `${sec}-${this.durationSec === sec}`)
            }
            .constraintSize({ maxWidth: '88%' })
          }
          .alignItems(HorizontalAlign.Center)
          // 本卷错题一键重练
          if (this.wrongTotal > 0) {
            Button($r('app.string.grade_summary_drill'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.brand'))
              .borderRadius(22)
              .padding({ left: 30, right: 30, top: 10, bottom: 10 })
              .margin({ top: 4 })
              .onClick(() => this.drillFromSummary())
          }
          Blank()
          Button($r('app.string.back_label'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.wrongTotal > 0 ? $r('app.color.brand') : $r('app.color.on_accent_text'))
            .backgroundColor(this.wrongTotal > 0 ? $r('app.color.brand_tint') : $r('app.color.brand'))
            .borderRadius(22)
            .padding({ left: 30, right: 30, top: 10, bottom: 10 })
            .margin({ bottom: 28 })
            .onClick(() => this.back())
        }
        .width('100%')
        .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      } else if (this.sheet !== null && this.quickMode) {
        // 快速批改：点选做错的题，其余自动记对
        Column({ space: 12 }) {
          Text($r('app.string.grade_quick_hint'))
            .fontSize(12)
            .fontColor($r('app.color.hint_text'))
            .textAlign(TextAlign.Center)
            .padding({ left: 16, right: 16 })
          Scroll() {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(this.sheet.items, (it: StoredItem, i: number) => {
                Text(it.q)
                  .fontSize(14)
                  .fontWeight(this.quickWrong[i] ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.quickWrong[i] ? $r('app.color.on_accent_text')
                    : $r('app.color.chip_text'))
                  .backgroundColor(this.quickWrong[i] ? $r('app.color.danger_red')
                    : $r('app.color.chip_bg'))
                  .borderRadius(10)
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => this.toggleQuickWrong(i))
              }, (it: StoredItem, i: number) => `${i}-${it.key}-${this.quickWrong[i]}`)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .align(Alignment.Start)
          .edgeEffect(EdgeEffect.Spring)

          Button($r('app.string.grade_quick_done'))
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_accent_text'))
            .backgroundColor($r('app.color.brand'))
            .borderRadius(24)
            .margin({ bottom: 30 })
            .onClick(() => this.applyQuick())
        }
        .width('100%')
        .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 6 })
      } else if (this.sheet !== null) {
        // 逐题对照
        Column({ space: 10 }) {
          Blank()
          Text(`${this.idx + 1} / ${this.sheet.items.length}`)
            .fontSize(13)
            .fontColor($r('app.color.hint_text'))
          Text(this.sheet.items[this.idx].q)
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
            .padding({ left: 16, right: 16 })
          Text(this.sheet.items[this.idx].a)
            .fontSize(22)
            .fontColor($r('app.color.brand'))
            .textAlign(TextAlign.Center)
          Blank()
        }
        .width('100%')
        .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        // 底栏：进度条 + ✗/✓ 圆钮
        Column({ space: 16 }) {
          Progress({ value: this.graded(), total: this.sheet.items.length, type: ProgressType.Linear })
            .color($r('app.color.brand'))
            .backgroundColor($r('app.color.chip_bg'))
            .height(4)
            .borderRadius(2)
          Row({ space: 56 }) {
            this.MarkButton('✗', $r('app.string.grade_wrong_label'),
              $r('app.color.danger_red'), () => this.mark(2))
            this.MarkButton('✓', $r('app.string.grade_right_label'),
              $r('app.color.success_green'), () => this.mark(1))
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
        .padding({ left: 24, right: 24, top: 10, bottom: 30 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
