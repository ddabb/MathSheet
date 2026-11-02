/**
 * 在线作答页（计划 §5.5；1.0.1 M3 限时挑战/停留时长/小数负号键盘）：
 * 设备上直接作答，替代"必须打印"的前置。
 *
 * - 三模式：练习（逐题即时判分，答错看正确答案，停留时长可选）/
 *   测验（全部作答完统一判分）/ 限时挑战（倒计时，归零未答记错自动交卷）；
 * - 应用内数字键盘（0-9/./−/⌫/✓），不拉起系统输入法（覆盖小数/负数题型）；
 * - 判分：QuizJudge 从物化题面/答案文本推导期望答案（历史卷免迁移）；
 * - 收尾一次性落库：marks + 用时（秒）整卷写入 + 错题本 commitSheet（幂等）；
 *   中途退出弹确认，放弃即丢弃（不落半程进度）；
 * - 结果页：对/错统计 + 用时 + 错题清单 + 一键错题重练（DrillFlow）。
 */

import { Context } from '@kit.AbilityKit';
import { StoredItem, StoredSheet } from '../core/SheetCodec';
import { SheetStore } from '../core/SheetStore';
import { MistakeEntry } from '../core/MistakeCodec';
import { MistakeStore } from '../core/MistakeStore';
import { MemberScope } from '../core/ProfileCodec';
import { ProfileStore } from '../core/ProfileStore';
import { QuizJudge } from '../core/QuizJudge';
import { QuizParams, PreviewParams } from '../common/PreviewParams';
import { DrillFlow } from '../common/DrillFlow';
import { Segmented, WIDE_CONTENT_MAX_VP } from '../components/UiKit';

/** 限时挑战配额（秒/题，1.0.1 M3）。 */
const TIMED_SEC_PER_ITEM: number = 6;
/** 练习模式错题停留时长选项（毫秒；0 = 手动点"下一题"，1.0.1 M3）。 */
const WRONG_STAY_OPTIONS: number[] = [0, 3000, 5000];

@Entry
@Component
struct QuizPage {
  /** 0=模式选择 1=作答中 2=练习答错反馈 3=结果页。 */
  @State phase: number = 0;
  /** 0=练习 1=测验 2=限时挑战（1.0.1 M3）。 */
  @State mode: number = 0;
  /** 练习模式错题停留时长（毫秒；0 = 手动，1.0.1 M3）。 */
  @State wrongStayMs: number = 0;
  /** 限时挑战剩余秒数（1.0.1 M3）。 */
  @State remainingSec: number = 0;
  @State idx: number = 0;
  @State input: string = '';
  /** 练习模式答对瞬间的绿色反馈（自动进入下一题）。 */
  @State flashOk: boolean = false;
  @State rightTotal: number = 0;
  @State wrongTotal: number = 0;
  private sheet: StoredSheet | null = null;
  private expected: string[] = [];
  private marks: number[] = [];
  private startedAt: number = 0;
  private elapsedSec: number = 0;
  private storeScope: MemberScope = new MemberScope('');
  private backLabelStr: string = '';
  private advanceTimer: number = -1;
  /** 限时挑战倒计时 interval 句柄。 */
  private countdownTimer: number = -1;
  /** 练习模式错题自动前进 timer 句柄。 */
  private wrongStayTimer: number = -1;

  aboutToAppear(): void {
    const raw: QuizParams = this.getUIContext().getRouter().getParams() as QuizParams;
    if (raw === undefined) {
      this.back();
      return;
    }
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      this.back();
      return;
    }
    this.storeScope = ProfileStore.scopeCurrent(ctx);
    const s: StoredSheet | null = SheetStore.loadSheet(this.storeScope, raw.sheetId);
    if (s === null || s.items.length === 0) {
      this.back();
      return;
    }
    let graded: number = 0;
    for (const m of s.marks) {
      if (m !== 0) {
        graded++;
      }
    }
    if (graded > 0) {
      this.getUIContext().getPromptAction()
        .showToast({ message: $r('app.string.quiz_already_graded_toast'), duration: 2000 });
      this.back();
      return;
    }
    this.backLabelStr = ctx.resourceManager.getStringSync($r('app.string.back_label').id);
    this.sheet = s;
    const exp: string[] = [];
    const marks: number[] = [];
    for (const it of s.items) {
      exp.push(QuizJudge.expectedAnswerOf(it.q, it.a));
      marks.push(0);
    }
    this.expected = exp;
    this.marks = marks;
    this.idx = 0;
  }

  aboutToDisappear(): void {
    this.clearAdvanceTimer();
    this.clearCountdownTimer();
    this.clearWrongStayTimer();
  }

  // ---------- 作答交互 ----------

  private clearAdvanceTimer(): void {
    if (this.advanceTimer >= 0) {
      clearTimeout(this.advanceTimer);
      this.advanceTimer = -1;
    }
  }

  private clearCountdownTimer(): void {
    if (this.countdownTimer >= 0) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private clearWrongStayTimer(): void {
    if (this.wrongStayTimer >= 0) {
      clearTimeout(this.wrongStayTimer);
      this.wrongStayTimer = -1;
    }
  }

  private start(): void {
    this.startedAt = Date.now();
    this.idx = 0;
    this.input = '';
    this.phase = 1;
    if (this.mode === 2) {
      this.beginCountdown();
    }
  }

  /** 限时挑战倒计时（1.0.1 M3）：题数 × 6 秒，归零未答记错并自动交卷。 */
  private beginCountdown(): void {
    this.clearCountdownTimer();
    const s: StoredSheet | null = this.sheet;
    const limitSec: number = s === null ? 0 : Math.max(30, s.items.length * TIMED_SEC_PER_ITEM);
    this.remainingSec = limitSec;
    this.countdownTimer = setInterval(() => {
      this.remainingSec--;
      if (this.remainingSec <= 0) {
        this.clearCountdownTimer();
        this.timeUp();
      }
    }, 1000);
  }

  /** 时间到：未答题记错 → 提示 → 直接交卷（已答保留判分结果）。 */
  private timeUp(): void {
    if (this.phase !== 1 && this.phase !== 2) {
      return;
    }
    for (let i: number = 0; i < this.marks.length; i++) {
      if (this.marks[i] === 0) {
        this.marks[i] = 2;
      }
    }
    this.recount();
    this.getUIContext().getPromptAction()
      .showToast({ message: $r('app.string.quiz_timed_up_toast'), duration: 2000 });
    this.finish();
  }

  private digit(d: string): void {
    if (this.phase !== 1 || this.flashOk || this.input.length >= QuizJudge.MAX_INPUT_LEN) {
      return;
    }
    // 小数点/负号约束（1.0.1 M3）：'.' 至多一个且前有数字；'−' 仅能开头
    if (d === '.') {
      if (this.input.length === 0 || this.input.indexOf('.') >= 0 || this.input === '−') {
        return;
      }
    } else if (d === '−') {
      if (this.input.length > 0) {
        return;
      }
    }
    this.input += d;
  }

  private backspace(): void {
    if (this.phase !== 1 || this.flashOk || this.input.length === 0) {
      return;
    }
    this.input = this.input.substring(0, this.input.length - 1);
  }

  private submit(): void {
    if (this.phase !== 1 || this.flashOk || this.sheet === null) {
      return;
    }
    if (this.input.length === 0) {
      this.getUIContext().getPromptAction()
        .showToast({ message: $r('app.string.quiz_input_empty_toast'), duration: 1500 });
      return;
    }
    const i: number = this.idx;
    const ok: boolean = QuizJudge.isCorrect(this.input, this.expected[i]);
    this.marks[i] = ok ? 1 : 2;
    this.recount();
    if (this.mode === 1 || this.mode === 2) {
      // 测验/限时挑战：不反馈，直接下一题
      this.advance();
      return;
    }
    // 练习：答对闪绿自动前进；答错停板看正确答案（停留时长可选，1.0.1 M3）
    if (ok) {
      this.flashOk = true;
      this.clearAdvanceTimer();
      this.advanceTimer = setTimeout(() => {
        this.advanceTimer = -1;
        this.advance();
      }, 650);
    } else {
      this.phase = 2;
      if (this.wrongStayMs > 0) {
        this.clearWrongStayTimer();
        this.wrongStayTimer = setTimeout(() => {
          this.wrongStayTimer = -1;
          this.advance();
        }, this.wrongStayMs);
      }
    }
  }

  private advance(): void {
    if (this.sheet === null) {
      return;
    }
    this.clearWrongStayTimer();
    this.flashOk = false;
    this.input = '';
    this.phase = 1; // 答错反馈页“下一题”需返回作答态（测验/闪绿路径本身已是 1，重复赋值无副作用）
    if (this.idx + 1 >= this.sheet.items.length) {
      this.finish();
      return;
    }
    this.idx++;
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

  // ---------- 收尾：一次性落库 ----------

  /** 全部作答完：marks + 用时（秒）整卷写回 + 错题本提交（幂等）。 */
  private finish(): void {
    const s: StoredSheet | null = this.sheet;
    if (s === null) {
      return;
    }
    this.clearCountdownTimer();
    this.clearWrongStayTimer();
    this.elapsedSec = Math.max(1, Math.round((Date.now() - this.startedAt) / 1000));
    s.marks = this.marks.slice();
    s.durationSec = this.elapsedSec;
    SheetStore.updateSheet(this.storeScope, s);
    MistakeStore.commitSheet(this.storeScope, s);
    this.phase = 3;
  }

  /** 结果页一键错题重练：本卷错题 1:2 混编 → 入库 → 跳预览。 */
  private drillFromResult(): void {
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

  private back(): void {
    this.getUIContext().getRouter().back();
  }

  /** 作答中拦截返回：确认后放弃（不落半程进度）。 */
  onBackPress(): boolean {
    if (this.phase !== 1 && this.phase !== 2) {
      return false;
    }
    const param: AlertDialogParamWithButtons = {
      title: $r('app.string.quiz_exit_title'),
      message: $r('app.string.quiz_exit_msg'),
      autoCancel: false,
      primaryButton: {
        value: $r('app.string.quiz_exit_keep'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.quiz_exit_leave'),
        action: () => {
          this.clearAdvanceTimer();
          this.clearCountdownTimer();
          this.clearWrongStayTimer();
          this.back();
        }
      }
    };
    this.getUIContext().showAlertDialog(param);
    return true;
  }

  // ---------- 文案辅助 ----------

  private answered(): number {
    return this.rightTotal + this.wrongTotal;
  }

  private progressText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || this.sheet === null) {
      return '';
    }
    return ctx.resourceManager.getStringSync($r('app.string.quiz_progress_answered').id,
      this.answered(), this.sheet.items.length);
  }

  private countText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || this.sheet === null) {
      return '';
    }
    return ctx.resourceManager.getStringSync($r('app.string.quiz_question_count').id,
      this.sheet.items.length);
  }

  private modeDescText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    const res: Resource = this.mode === 0 ? $r('app.string.quiz_mode_practice_desc')
      : this.mode === 1 ? $r('app.string.quiz_mode_test_desc')
        : $r('app.string.quiz_mode_timed_desc');
    return ctx.resourceManager.getStringSync(res.id);
  }

  private modeLabel(m: number): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    const res: Resource = m === 0 ? $r('app.string.quiz_mode_practice')
      : m === 1 ? $r('app.string.quiz_mode_test')
        : $r('app.string.quiz_mode_timed');
    return ctx.resourceManager.getStringSync(res.id);
  }

  /** 限时挑战剩余时间（mm:ss，1.0.1 M3）。 */
  private timeLeftText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    const sec: number = Math.max(0, this.remainingSec);
    const mm: number = Math.floor(sec / 60);
    const ss: number = sec % 60;
    const mmS: string = mm < 10 ? `0${mm}` : `${mm}`;
    const ssS: string = ss < 10 ? `0${ss}` : `${ss}`;
    return ctx.resourceManager.getStringSync($r('app.string.quiz_time_left').id, `${mmS}:${ssS}`);
  }

  /** 练习模式错题停留时长选项文案（1.0.1 M3）。 */
  private wrongStayLabel(ms: number): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    if (ms === 0) {
      return ctx.resourceManager.getStringSync($r('app.string.quiz_wrong_stay_manual').id);
    }
    return ctx.resourceManager.getStringSync($r('app.string.quiz_wrong_stay_sec').id, ms / 1000);
  }

  private summaryText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || this.sheet === null) {
      return '';
    }
    return ctx.resourceManager.getStringSync($r('app.string.quiz_done_summary').id,
      this.sheet.items.length, this.rightTotal, this.wrongTotal);
  }

  /** 用时展示：<60 秒 → "X 秒"；整分 → "X 分"；否则 → "X 分 Y 秒"。 */
  private durationText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    const rm = ctx.resourceManager;
    const sec: number = this.elapsedSec;
    if (sec < 60) {
      return rm.getStringSync($r('app.string.quiz_duration_sec').id, sec);
    }
    if (sec % 60 === 0) {
      return rm.getStringSync($r('app.string.grade_duration_min').id, sec / 60);
    }
    return rm.getStringSync($r('app.string.grade_duration_ms').id,
      Math.floor(sec / 60), sec % 60);
  }

  private durationLabelText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    return ctx.resourceManager.getStringSync($r('app.string.quiz_duration_used').id,
      this.durationText());
  }

  private yourAnswerText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    return ctx === undefined ? ''
      : ctx.resourceManager.getStringSync($r('app.string.quiz_your_answer').id, this.input);
  }

  private correctAnswerText(): string {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    const exp: string = this.expected[this.idx] !== undefined ? this.expected[this.idx] : '';
    return ctx === undefined ? ''
      : ctx.resourceManager.getStringSync($r('app.string.quiz_correct_answer').id, exp);
  }

  private wrongIndexes(): number[] {
    const out: number[] = [];
    const s: StoredSheet | null = this.sheet;
    if (s === null) {
      return out;
    }
    for (let i: number = 0; i < s.items.length && i < this.marks.length; i++) {
      if (this.marks[i] === 2) {
        out.push(i);
      }
    }
    return out;
  }

  // ---------- 构建辅助 ----------

  @Builder
  DigitKey(label: string) {
    Text(label)
      .fontSize(26)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.primary_text'))
      .backgroundColor($r('app.color.card_background'))
      .height(54)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .borderRadius($r('app.float.radius_lg'))
      .border({ width: 1, color: $r('app.color.border_color') })
      .shadow({
        radius: $r('app.float.shadow_card_radius'),
        offsetY: $r('app.float.shadow_card_offset_y'),
        color: $r('app.color.shadow_color')
      })
      .onClick(() => this.digit(label))
  }

  @Builder
  ActionKey(label: string, filled: boolean, onTap: () => void) {
    Text(label)
      .fontSize(26)
      .fontWeight(FontWeight.Bold)
      .fontColor(filled ? $r('app.color.on_accent_text') : $r('app.color.primary_text'))
      .backgroundColor(filled ? $r('app.color.brand') : $r('app.color.card_background'))
      .height(54)
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .borderRadius($r('app.float.radius_lg'))
      .border({ width: 1, color: $r('app.color.border_color') })
      .shadow({
        radius: $r('app.float.shadow_card_radius'),
        offsetY: $r('app.float.shadow_card_offset_y'),
        color: $r('app.color.shadow_color')
      })
      .onClick(() => onTap())
  }

  @Builder
  KeyPad() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        this.DigitKey('1')
        this.DigitKey('2')
        this.DigitKey('3')
      }
      .width('100%')
      Row({ space: 10 }) {
        this.DigitKey('4')
        this.DigitKey('5')
        this.DigitKey('6')
      }
      .width('100%')
      Row({ space: 10 }) {
        this.DigitKey('7')
        this.DigitKey('8')
        this.DigitKey('9')
      }
      .width('100%')
      // 1.0.1 M3：小数点 + 负号（覆盖小数/负数题型）
      Row({ space: 10 }) {
        this.DigitKey('.')
        this.DigitKey('0')
        this.DigitKey('−')
      }
      .width('100%')
      Row({ space: 10 }) {
        this.ActionKey('⌫', false, (): void => this.backspace())
        this.ActionKey('✓', true, (): void => this.submit())
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: 420 })
  }

  @Builder
  TopBar() {
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
        if (this.phase === 1 || this.phase === 2) {
          Text(this.progressText())
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
        }
      }
      .alignItems(HorizontalAlign.Center)
      .constraintSize({ maxWidth: '60%' })
      Blank()
    }
    .width('100%')
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  StartScreen() {
    Column({ space: 14 }) {
      Blank()
      Text(this.sheet === null ? '' : this.sheet.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
      Text(this.countText())
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Segmented({
        labels: [this.modeLabel(0), this.modeLabel(1), this.modeLabel(2)],
        selected: this.mode,
        onPick: (i: number) => {
          this.mode = i;
        }
      })
      Text(this.modeDescText())
        .fontSize(12)
        .fontColor($r('app.color.hint_text'))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      // 练习模式：错题停留时长可选（1.0.1 M3）
      if (this.mode === 0) {
        Row({ space: 8 }) {
          Text($r('app.string.quiz_wrong_stay_label'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
          ForEach(WRONG_STAY_OPTIONS, (ms: number) => {
            Text(this.wrongStayLabel(ms))
              .fontSize(13)
              .fontWeight(this.wrongStayMs === ms ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.wrongStayMs === ms ? $r('app.color.on_accent_text')
                : $r('app.color.chip_text'))
              .backgroundColor(this.wrongStayMs === ms ? $r('app.color.brand')
                : $r('app.color.chip_bg'))
              .borderRadius(14)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.wrongStayMs = ms;
              })
          }, (ms: number) => `${ms}-${this.wrongStayMs === ms}`)
        }
      }
      Button($r('app.string.quiz_start'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.brand'))
        .borderRadius(22)
        .padding({ left: 42, right: 42, top: 12, bottom: 12 })
        .margin({ top: 10 })
        .onClick(() => this.start())
      Blank()
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
  }

  @Builder
  QuestionScreen() {
    Column({ space: 10 }) {
      Blank()
      Text(`${this.idx + 1} / ${this.sheet === null ? 0 : this.sheet.items.length}`)
        .fontSize(13)
        .fontColor($r('app.color.hint_text'))
      // 限时挑战倒计时（1.0.1 M3；末 10 秒红色警示）
      if (this.mode === 2) {
        Text(this.timeLeftText())
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.remainingSec <= 10 ? $r('app.color.danger_red') : $r('app.color.brand'))
          .backgroundColor($r('app.color.brand_tint'))
          .borderRadius(13)
          .padding({ left: 14, right: 14, top: 4, bottom: 4 })
      }
      Text(this.sheet === null ? '' : this.sheet.items[this.idx].q)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 16, right: 16 })
      if (this.flashOk) {
        Column({ space: 8 }) {
          Text('✓')
            .fontSize(46)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.success_green'))
          Text($r('app.string.quiz_correct_feedback'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.success_green'))
        }
        .alignItems(HorizontalAlign.Center)
      } else {
        Text(this.input.length === 0 ? '？' : this.input)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.input.length === 0 ? $r('app.color.hint_text')
            : $r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
          .width(200)
          .height(72)
          .borderRadius(14)
          .backgroundColor($r('app.color.card_background'))
      }
      Blank()
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })

    // 底部：进度条 + 数字键盘
    Column({ space: 14 }) {
      Progress({ value: this.answered(),
        total: this.sheet === null ? 1 : this.sheet.items.length, type: ProgressType.Linear })
        .color($r('app.color.brand'))
        .backgroundColor($r('app.color.chip_bg'))
        .height(4)
        .borderRadius(2)
      this.KeyPad()
    }
    .width('100%')
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
    .padding({ left: 20, right: 20, top: 10, bottom: 28 })
  }

  @Builder
  WrongScreen() {
    Column({ space: 12 }) {
      Blank()
      Text(`${this.idx + 1} / ${this.sheet === null ? 0 : this.sheet.items.length}`)
        .fontSize(13)
        .fontColor($r('app.color.hint_text'))
      Text(this.sheet === null ? '' : this.sheet.items[this.idx].q)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 16, right: 16 })
      Text('✗')
        .fontSize(46)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.danger_red'))
      Text($r('app.string.quiz_wrong_feedback'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.danger_red'))
      Text(this.yourAnswerText())
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(this.correctAnswerText())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.brand'))
      Blank()
      Button($r('app.string.quiz_next'))
        .width('72%')
        .height(46)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.brand'))
        .borderRadius(23)
        .margin({ bottom: 30 })
        .onClick(() => this.advance())
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
  }

  @Builder
  WrongRow(i: number) {
    Row({ space: 10 }) {
      Text(this.sheet === null ? '' : this.sheet.items[i].q)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.sheet === null ? '' : this.sheet.items[i].a)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .constraintSize({ maxWidth: '46%' })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
  }

  @Builder
  ResultScreen() {
    Scroll() {
      Column({ space: 14 }) {
        Blank().height(18)
        Text('✓')
          .fontSize(52)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.success_green'))
        Text($r('app.string.quiz_done_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text(this.summaryText())
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
        Text(this.durationLabelText())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_tint'))
          .borderRadius(13)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        if (this.wrongTotal > 0) {
          Text($r('app.string.quiz_wrong_list_header'))
            .fontSize(13)
            .fontColor($r('app.color.hint_text'))
            .margin({ top: 6 })
          ForEach(this.wrongIndexes(), (i: number) => {
            this.WrongRow(i)
          }, (i: number) => `${i}`)
          Button($r('app.string.grade_summary_drill'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_accent_text'))
            .backgroundColor($r('app.color.brand'))
            .borderRadius(22)
            .padding({ left: 30, right: 30, top: 10, bottom: 10 })
            .margin({ top: 4 })
            .onClick(() => this.drillFromResult())
        }
        Button($r('app.string.back_label'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.wrongTotal > 0 ? $r('app.color.brand') : $r('app.color.on_accent_text'))
          .backgroundColor(this.wrongTotal > 0 ? $r('app.color.brand_tint') : $r('app.color.brand'))
          .borderRadius(22)
          .padding({ left: 30, right: 30, top: 10, bottom: 10 })
          .margin({ top: 8, bottom: 26 })
          .onClick(() => this.back())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Start)
    .edgeEffect(EdgeEffect.Spring)
  }

  build() {
    Column() {
      this.TopBar()
      if (this.phase === 0) {
        this.StartScreen()
      } else if (this.phase === 1) {
        this.QuestionScreen()
      } else if (this.phase === 2) {
        this.WrongScreen()
      } else {
        this.ResultScreen()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
