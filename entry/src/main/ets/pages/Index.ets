/**
 * 首页（计划 §5.1；M7 家庭成员档案 §5.3）：底部四页签（生成 / 卷库 / 错题本 / 设置）。
 *
 * 生成页围绕用户最高频路径设计：
 *  - 成员快捷条：本地多档切换（点击切换当前成员、新增入口，卷库/错题/打卡按成员隔离）；
 *  - 每日一练 Hero：记忆上次生成配置，一键"生成今天的题卡"+ 本地连续打卡（DailyStore 按成员分库）；
 *  - 表单：年级分段 → 题型家族多选 → 难度 → 题数 / 列数 → 高级（题头 / 答案页 / 多套同构卷）；
 *  - 主按钮"生成题卡"固定底部，携 PreviewParams 跳预览页（同参数同种子同卷）。
 * 卷库（M3）：物化卷列表（重开 / 批改 / 删除确认），生成即入库、回到页签自动刷新；
 * 错题本（M4）：错题列表 + 一键重练卷（原题:同类新题 = 1:2 混编入库）+ 清空确认；
 * 设置：家庭成员管理（新增 / 改名 / 删除确认）+ 显示 / 关于信息。
 * 首启引导：ensureDefault 建默认成员并迁移存量数据（卷库/错题 rename 移入、打卡整库搬迁）。
 */

import { i18n, resourceManager } from '@kit.LocalizationKit';
import { Context } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { GradePresets, PresetEntry } from '../core/GradePresets';
import { TypeFamilies, TypeFamily } from '../common/TypeFamilies';
import { DailyState, DailyStore } from '../common/DailyStore';
import { PreviewParams, GradeParams } from '../common/PreviewParams';
import { StoredMeta } from '../core/SheetCodec';
import { SheetStore } from '../core/SheetStore';
import { MistakeEntry } from '../core/MistakeCodec';
import { MistakeStore } from '../core/MistakeStore';
import { MistakeDrill } from '../core/MistakeDrill';
import { Profile, ProfileCodec, ProfileIndex } from '../core/ProfileCodec';
import { ProfileStore } from '../core/ProfileStore';
import { HeroCard } from '../components/HeroCard';
import { MemberChip, MemberRowModel, MemberDialogTexts, MemberBar, MemberManage, MemberEditDialog } from '../components/MemberWidgets';
import { LibraryPanel, MistakesPanel } from '../components/LibraryWidgets';
import { SectionLabel, OptionChip, Segmented, ToggleRow, TabBarItem, InfoRow, WIDE_CONTENT_MAX_VP } from '../components/UiKit';

const COUNT_OPTIONS: number[] = [20, 50, 100, 200];
const COLUMN_OPTIONS: number[] = [2, 3, 4];
const SET_OPTIONS: number[] = [1, 2, 4];
const GRADES: number[] = [1, 2, 3];
const DIALOG_MAX_WIDTH_VP: number = 420;

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State grade: number = 2;
  @State diffPlus: boolean = true;
  @State selectedFamilies: string[] = ['f2_100', 'f2_mul', 'f2_div'];
  @State problemCount: number = 50;
  @State columns: number = 3;
  @State headerOn: boolean = true;
  @State answerOn: boolean = true;
  @State sets: number = 1;
  @State daily: DailyState = new DailyState();
  @State heroDate: string = '';
  @State libraryMetas: StoredMeta[] = [];
  @State mistakes: MistakeEntry[] = [];
  @State members: Profile[] = [];
  @State currentMemberId: string = '';
  private langZh: boolean = true;
  private dialogId: number = -1;
  /** 成员编辑弹窗目标（'' = 新增模式）。 */
  private dialogRenameId: string = '';
  private dialogTexts: MemberDialogTexts = new MemberDialogTexts();
  private dialogInitName: string = '';
  private dialogInitGrade: number = 2;

  aboutToAppear(): void {
    this.langZh = i18n.System.getSimplifiedLanguage().indexOf('zh') === 0;
    this.heroDate = this.heroDateText();
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    // 首启引导：建默认成员 + 存量迁移（文件 rename 移入）；打卡整库搬迁完成后
    // 再刷新首页状态（loadDaily 读新库，须晚于 migrate 拷贝，否则竞态读到空库）。
    ProfileStore.ensureDefault(ctx, this.strOf($r('app.string.member_default_name')));
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    if (ProfileCodec.findById(idx, ProfileCodec.DEFAULT_ID) !== null) {
      DailyStore.migrate(ctx, ProfileStore.LEGACY_DAILY,
        ProfileStore.dailyNameOf(ProfileCodec.DEFAULT_ID)).then(() => {
        this.refreshFromIndex();
      }).catch(() => {
        this.refreshFromIndex();
      });
    } else {
      this.refreshFromIndex();
    }
  }

  /** 回到首页（预览/批改返回）刷新卷库与错题本。 */
  onPageShow(): void {
    this.reloadLibrary();
    this.reloadMistakes();
  }

  // ---------- 成员（M7） ----------

  private profileById(id: string): Profile | null {
    for (const m of this.members) {
      if (m.id === id) {
        return m;
      }
    }
    return null;
  }

  /** 从索引同步成员相关状态（启动 / 切换 / 增删改后调用）。 */
  private refreshFromIndex(): void {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const idx: ProfileIndex = ProfileStore.loadIndex(ctx);
    this.members = idx.members;
    this.currentMemberId = idx.currentId;
    const cur: Profile | null = ProfileCodec.findById(idx, idx.currentId);
    if (cur !== null) {
      this.grade = cur.grade;
      this.selectedFamilies = TypeFamilies.defaultsForGrade(cur.grade);
    }
    this.loadDaily();
    this.reloadLibrary();
    this.reloadMistakes();
  }

  private applyMember(id: string): void {
    if (id === this.currentMemberId) {
      return;
    }
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined || !ProfileStore.setCurrent(ctx, id)) {
      return;
    }
    this.refreshFromIndex();
  }

  private openAddMember(): void {
    this.showMemberDialog('', this.grade, '');
  }

  private openRenameMember(id: string): void {
    const p: Profile | null = this.profileById(id);
    if (p === null) {
      return;
    }
    this.showMemberDialog(p.name, p.grade, id);
  }

  /** 弹窗宽度：窗口 86% 但宽屏封顶（86% 在平板/2in1 上过宽）。 */
  private dialogWidthVp(): number {
    const d: display.Display = display.getDefaultDisplaySync();
    const winVp: number = d.width / d.densityPixels;
    const w: number = Math.round(winVp * 0.86);
    return w > DIALOG_MAX_WIDTH_VP ? DIALOG_MAX_WIDTH_VP : w;
  }

  /** 打开成员编辑弹窗（renameId = '' 表示新增）：数据预置后 openCustomDialog。 */
  private showMemberDialog(name: string, grade: number, renameId: string): void {
    const t: MemberDialogTexts = new MemberDialogTexts();
    t.title = this.strOf(renameId === ''
      ? $r('app.string.member_add') : $r('app.string.member_rename'));
    t.nameHint = this.strOf($r('app.string.member_name_hint'));
    t.gradeLabel = this.strOf($r('app.string.grade_label'));
    t.grades = [this.gradeLabel(1), this.gradeLabel(2), this.gradeLabel(3)];
    t.cancel = this.strOf($r('app.string.dialog_cancel'));
    t.confirm = this.strOf($r('app.string.member_confirm'));
    t.nameEmptyToast = this.strOf($r('app.string.member_name_empty_toast'));
    this.dialogTexts = t;
    this.dialogInitName = name;
    this.dialogInitGrade = grade;
    this.dialogRenameId = renameId;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: (): void => {
        this.memberEditBuilder();
      },
      autoCancel: true,
      alignment: DialogAlignment.Center,
      width: this.dialogWidthVp(),
      onDidDisappear: (): void => {
        this.dialogId = -1;
      }
    }).then((id: number) => {
      this.dialogId = id;
    }).catch(() => {
    });
  }

  private closeMemberDialog(): void {
    if (this.dialogId < 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().closeCustomDialog(this.dialogId);
    } catch (e) {
      // 已随遮罩关闭（autoCancel 竞态）时忽略
    }
  }

  @Builder
  memberEditBuilder() {
    MemberEditDialog({
      texts: this.dialogTexts,
      initialName: this.dialogInitName,
      initialGrade: this.dialogInitGrade,
      onConfirm: (n: string, g: number) => this.confirmMember(n, g),
      onRequestClose: () => this.closeMemberDialog()
    })
  }

  /** 弹窗确认：新增（自动切换到新成员）或改名（表单随成员年级联动）。 */
  private confirmMember(name: string, grade: number): void {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    if (this.dialogRenameId === '') {
      const p: Profile | null = ProfileStore.add(ctx, name, grade);
      if (p === null) {
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.member_limit_toast'), duration: 2500 });
        return;
      }
      ProfileStore.setCurrent(ctx, p.id);
      this.refreshFromIndex();
      return;
    }
    if (ProfileStore.rename(ctx, this.dialogRenameId, name, grade)) {
      this.refreshFromIndex();
    }
  }

  private confirmDeleteMember(id: string): void {
    const p: Profile | null = this.profileById(id);
    if (p === null) {
      return;
    }
    const param: AlertDialogParamWithButtons = {
      title: $r('app.string.member_delete_title'),
      message: this.strOf($r('app.string.member_delete_msg')).replace('%s', p.name),
      autoCancel: false,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.library_delete_ok'),
        action: () => {
          const ctx: Context | undefined = this.getUIContext().getHostContext();
          if (ctx !== undefined) {
            ProfileStore.remove(ctx, id);
          }
          this.refreshFromIndex();
        }
      }
    };
    this.getUIContext().showAlertDialog(param);
  }

  /** 生成页成员快捷条数据。 */
  private memberChips(): MemberChip[] {
    const out: MemberChip[] = [];
    for (const m of this.members) {
      const c: MemberChip = new MemberChip();
      c.id = m.id;
      c.name = m.name;
      c.isCurrent = m.id === this.currentMemberId;
      out.push(c);
    }
    return out;
  }

  /** 设置页成员管理行数据（canDelete = 非最后一名）。 */
  private memberRows(): MemberRowModel[] {
    const out: MemberRowModel[] = [];
    for (const m of this.members) {
      const r: MemberRowModel = new MemberRowModel();
      r.id = m.id;
      r.name = m.name;
      const tag: string = m.id === this.currentMemberId
        ? this.strOf($r('app.string.member_current_tag')) : '';
      const gradeText: string = this.gradeLabel(m.grade);
      r.subText = tag === '' ? gradeText : `${gradeText} · ${tag}`;
      r.canDelete = this.members.length > 1;
      out.push(r);
    }
    return out;
  }

  // ---------- 数据加载 ----------

  private dailyStoreName(): string {
    const id: string = this.currentMemberId !== '' ? this.currentMemberId : ProfileCodec.DEFAULT_ID;
    return ProfileStore.dailyNameOf(id);
  }

  private loadDaily(): void {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    DailyStore.load(ctx, this.dailyStoreName()).then((s: DailyState) => {
      this.daily = s;
    });
  }

  private reloadLibrary(): void {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    this.libraryMetas = SheetStore.loadIndex(ProfileStore.scopeCurrent(ctx));
  }

  private reloadMistakes(): void {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    this.mistakes = MistakeStore.load(ProfileStore.scopeCurrent(ctx));
  }

  // ---------- 文案辅助 ----------

  private rm(): resourceManager.ResourceManager | undefined {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    return ctx === undefined ? undefined : ctx.resourceManager;
  }

  private strOf(res: Resource): string {
    const rm: resourceManager.ResourceManager | undefined = this.rm();
    return rm === undefined ? '' : rm.getStringSync(res.id);
  }

  private heroDateText(): string {
    const d: Date = new Date();
    if (this.langZh) {
      return `${d.getMonth() + 1}月${d.getDate()}日`;
    }
    const months: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return `${months[d.getMonth()]} ${d.getDate()}`;
  }

  private streakText(): string {
    const rm: resourceManager.ResourceManager | undefined = this.rm();
    if (rm === undefined) {
      return '';
    }
    if (this.daily.streak <= 0) {
      return rm.getStringSync($r('app.string.daily_streak_zero').id);
    }
    const res: Resource = this.daily.lastDate === DailyStore.fmtDay(Date.now())
      ? $r('app.string.daily_streak_done') : $r('app.string.daily_streak_pending');
    return rm.getStringSync(res.id, this.daily.streak);
  }

  private cfgSummaryText(): string {
    const rm: resourceManager.ResourceManager | undefined = this.rm();
    if (rm === undefined || this.daily.typeIds.length === 0) {
      return '';
    }
    const first: PresetEntry | null = GradePresets.byId(this.daily.typeIds[0]);
    const g: number = first !== null ? first.grade : this.grade;
    return rm.getStringSync($r('app.string.daily_cfg_summary').id, g, this.daily.count, this.daily.columns);
  }

  private gradeLabel(g: number): string {
    const res: Resource = g === 1 ? $r('app.string.grade_g1')
      : g === 3 ? $r('app.string.grade_g3') : $r('app.string.grade_g2');
    return this.strOf(res);
  }

  private familyLabel(f: TypeFamily): string {
    return this.langZh ? f.labelZh : f.labelEn;
  }

  private setLabel(n: number): string {
    const res: Resource = n === 1 ? $r('app.string.sets_one')
      : n === 2 ? $r('app.string.sets_two') : $r('app.string.sets_four');
    return this.strOf(res);
  }

  // ---------- 交互：生成 ----------

  private pickGrade(g: number): void {
    if (this.grade === g) {
      return;
    }
    this.grade = g;
    this.selectedFamilies = TypeFamilies.defaultsForGrade(g);
    // 年级随表单写回成员档案（成员 = 孩子的年级真相）
    const cur: Profile | null = this.profileById(this.currentMemberId);
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (cur === null || ctx === undefined) {
      return;
    }
    if (ProfileStore.rename(ctx, cur.id, cur.name, g)) {
      this.members = ProfileStore.loadIndex(ctx).members;
    }
  }

  private toggleFamily(id: string): void {
    const next: string[] = this.selectedFamilies.slice();
    const pos: number = next.indexOf(id);
    if (pos >= 0) {
      next.splice(pos, 1);
    } else {
      next.push(id);
    }
    this.selectedFamilies = next;
  }

  /** 表单生成：家族 × 难度 → 预设 id → 跳预览。 */
  private generate(): void {
    const typeIds: string[] = TypeFamilies.resolvePresetIds(this.selectedFamilies, this.diffPlus);
    if (typeIds.length === 0) {
      this.getUIContext().getPromptAction()
        .showToast({ message: $r('app.string.pick_type_first'), duration: 2500 });
      return;
    }
    this.launchPreview(typeIds, this.problemCount, this.columns, this.headerOn, this.answerOn, this.sets);
  }

  /** 每日一练一键生成：优先用记忆配置，无记忆时退化为当前表单。 */
  private generateToday(): void {
    if (this.daily.hasConfig && this.daily.typeIds.length > 0) {
      this.launchPreview(this.daily.typeIds.slice(), this.daily.count, this.daily.columns,
        this.daily.headerOn, this.daily.answerOn, this.daily.sets);
      return;
    }
    this.generate();
  }

  /** 统一生成入口：记录每日一练（记忆配置 + 打卡）后跳预览页。 */
  private launchPreview(typeIds: string[], count: number, columns: number,
                        headerOn: boolean, answerOn: boolean, sets: number): void {
    const params: PreviewParams = {
      typeIds: typeIds,
      seed: Math.floor(Math.random() * 2147483647),
      count: count,
      columns: columns,
      headerOn: headerOn,
      answerOn: answerOn,
      sets: sets
    };
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      DailyStore.record(ctx, this.dailyStoreName(), typeIds, count, columns, headerOn, answerOn, sets)
        .then((s: DailyState) => {
          this.daily = s;
        });
    }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PreviewPage', params: params });
  }

  // ---------- 交互：卷库 / 错题本 ----------

  /** 卷库重开（物化卷模式，其余字段为占位）。 */
  private openLibrarySheet(id: string): void {
    const params: PreviewParams = {
      typeIds: [],
      seed: 0,
      count: 0,
      columns: 3,
      headerOn: true,
      answerOn: true,
      sets: 1,
      sheetId: id
    };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PreviewPage', params: params });
  }

  private gradeLibrarySheet(id: string): void {
    const params: GradeParams = { sheetId: id };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/GradePage', params: params });
  }

  private confirmDeleteSheet(m: StoredMeta): void {
    const param: AlertDialogParamWithButtons = {
      title: $r('app.string.library_delete_title'),
      message: $r('app.string.library_delete_msg'),
      autoCancel: false,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.library_delete_ok'),
        action: () => {
          const ctx: Context | undefined = this.getUIContext().getHostContext();
          if (ctx !== undefined) {
            SheetStore.removeSheets(ProfileStore.scopeCurrent(ctx), [m.id]);
          }
          this.reloadLibrary();
        }
      }
    };
    this.getUIContext().showAlertDialog(param);
  }

  private confirmClearMistakes(): void {
    const param: AlertDialogParamWithButtons = {
      title: $r('app.string.mistakes_clear_title'),
      message: this.mistakes.length > 0
        ? this.strOf($r('app.string.mistakes_clear_msg')).replace('%d', `${this.mistakes.length}`) : '',
      autoCancel: false,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.mistakes_clear_ok'),
        action: () => {
          const ctx: Context | undefined = this.getUIContext().getHostContext();
          if (ctx !== undefined) {
            MistakeStore.clearAll(ProfileStore.scopeCurrent(ctx));
          }
          this.reloadMistakes();
        }
      }
    };
    this.getUIContext().showAlertDialog(param);
  }

  /** 一键重练卷：错题 1:2 混编 → 物化入库 → 跳预览（卷库模式）。 */
  private buildDrill(): void {
    if (this.mistakes.length === 0) {
      return;
    }
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const rm = ctx.resourceManager;
    const id: string = SheetStore.newId();
    const title: string = rm.getStringSync($r('app.string.mistakes_drill_title').id);
    const sheet = MistakeDrill.buildSheet(id, Date.now(), title, this.mistakes,
      Math.floor(Math.random() * 2147483647), 200);
    if (sheet === null) {
      return;
    }
    SheetStore.saveSheet(ProfileStore.scopeCurrent(ctx), sheet);
    this.getUIContext().getPromptAction()
      .showToast({ message: $r('app.string.mistakes_drill_toast'), duration: 2000 });
    this.openLibrarySheet(id);
  }

  // ---------- 生成页 ----------

  @Builder
  GeneratorTab() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 品牌行
          Row() {
            Text($r('app.string.app_name'))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Blank()
            Text($r('app.string.offline_note'))
              .fontSize(10)
              .fontColor($r('app.color.hint_text'))
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(9)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          }
          .width('100%')

          // 家庭成员快捷条（M7）
          MemberBar({
            chips: this.memberChips(),
            currentTag: this.strOf($r('app.string.member_current_tag')),
            addLabel: this.strOf($r('app.string.member_add')),
            onPick: (id: string) => this.applyMember(id),
            onAdd: () => this.openAddMember()
          })

          // 每日一练 Hero
          HeroCard({
            dateText: this.heroDate,
            streakText: this.streakText(),
            cfgText: this.cfgSummaryText(),
            hasConfig: this.daily.hasConfig,
            onToday: () => this.generateToday()
          })

          // 表单卡
          Column({ space: 12 }) {
            SectionLabel({ text: this.strOf($r('app.string.grade_label')) })
            Segmented({
              labels: [this.gradeLabel(1), this.gradeLabel(2), this.gradeLabel(3)],
              selected: this.grade - 1,
              onPick: (i: number) => this.pickGrade(GRADES[i])
            })

            Divider().color($r('app.color.border_color'))
            SectionLabel({ text: this.strOf($r('app.string.type_label')) })
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(TypeFamilies.forGrade(this.grade), (f: TypeFamily) => {
                Text(this.familyLabel(f))
                  .fontSize(13)
                  .fontWeight(this.selectedFamilies.indexOf(f.id) >= 0 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.selectedFamilies.indexOf(f.id) >= 0 ? $r('app.color.on_accent_text')
                    : $r('app.color.chip_text'))
                  .backgroundColor(this.selectedFamilies.indexOf(f.id) >= 0 ? $r('app.color.brand')
                    : $r('app.color.chip_bg'))
                  .borderRadius(14)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => this.toggleFamily(f.id))
              }, (f: TypeFamily) => f.id)
            }

            Divider().color($r('app.color.border_color'))
            SectionLabel({ text: this.strOf($r('app.string.difficulty_label')) })
            Segmented({
              labels: [this.strOf($r('app.string.difficulty_base')), this.strOf($r('app.string.difficulty_plus'))],
              selected: this.diffPlus ? 1 : 0,
              onPick: (i: number) => {
                this.diffPlus = i === 1;
              }
            })

            Divider().color($r('app.color.border_color'))
            SectionLabel({ text: this.strOf($r('app.string.count_label')) })
            Row({ space: 8 }) {
              ForEach(COUNT_OPTIONS, (n: number) => {
                OptionChip({
                  label: n.toString(),
                  selected: this.problemCount === n,
                  onTap: () => {
                    this.problemCount = n;
                  }
                })
              }, (n: number) => 'c' + n.toString())
            }

            SectionLabel({ text: this.strOf($r('app.string.columns_label')) })
            Row({ space: 8 }) {
              ForEach(COLUMN_OPTIONS, (n: number) => {
                OptionChip({
                  label: n.toString(),
                  selected: this.columns === n,
                  onTap: () => {
                    this.columns = n;
                  }
                })
              }, (n: number) => 'k' + n.toString())
            }

            Divider().color($r('app.color.border_color'))
            SectionLabel({ text: this.strOf($r('app.string.advanced_label')) })
            ToggleRow({
              label: this.strOf($r('app.string.header_toggle_label')),
              isOn: this.headerOn,
              onFlip: (v: boolean) => {
                this.headerOn = v;
              }
            })
            ToggleRow({
              label: this.strOf($r('app.string.answer_page_toggle_label')),
              isOn: this.answerOn,
              onFlip: (v: boolean) => {
                this.answerOn = v;
              }
            })

            Row() {
              Text($r('app.string.sets_label'))
                .fontSize(14)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Row({ space: 8 }) {
                ForEach(SET_OPTIONS, (n: number) => {
                  OptionChip({
                    label: this.setLabel(n),
                    selected: this.sets === n,
                    onTap: () => {
                      this.sets = n;
                    }
                  })
                }, (n: number) => 's' + n.toString())
              }
            }
            Text($r('app.string.sets_hint'))
              .fontSize(11)
              .fontColor($r('app.color.hint_text'))
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Start)
      .edgeEffect(EdgeEffect.Spring)

      // 固定底部主按钮
      Button($r('app.string.generate_button'))
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .backgroundColor($r('app.color.brand'))
        .borderRadius(24)
        .margin({ left: 16, right: 16, top: 8 })
        .onClick(() => this.generate())
    }
    .width('100%')
    .height('100%')
  }

  // ---------- 卷库页 ----------

  @Builder
  LibraryTab() {
    LibraryPanel({
      metas: this.libraryMetas,
      titleLabel: this.strOf($r('app.string.tab_library')),
      emptyTitle: this.strOf($r('app.string.library_empty_title')),
      emptyDesc: this.strOf($r('app.string.library_empty_desc')),
      goLabel: this.strOf($r('app.string.go_generate')),
      openLabel: this.strOf($r('app.string.library_open')),
      gradeLabel: this.strOf($r('app.string.library_grade')),
      deleteLabel: this.strOf($r('app.string.library_delete')),
      onOpen: (id: string) => this.openLibrarySheet(id),
      onGrade: (id: string) => this.gradeLibrarySheet(id),
      onDelete: (m: StoredMeta) => this.confirmDeleteSheet(m),
      onGo: () => {
        this.currentTab = 0;
      }
    })
  }

  // ---------- 错题本页 ----------

  @Builder
  MistakesTab() {
    MistakesPanel({
      mistakes: this.mistakes,
      titleLabel: this.strOf($r('app.string.tab_mistakes')),
      clearButton: this.strOf($r('app.string.mistakes_clear_button')),
      emptyTitle: this.strOf($r('app.string.mistakes_empty_title')),
      emptyDesc: this.strOf($r('app.string.mistakes_empty_desc')),
      goLabel: this.strOf($r('app.string.go_generate')),
      drillTitle: this.strOf($r('app.string.mistakes_drill_title')),
      drillButton: this.strOf($r('app.string.mistakes_drill_button')),
      onClear: () => this.confirmClearMistakes(),
      onDrill: () => this.buildDrill(),
      onGo: () => {
        this.currentTab = 0;
      }
    })
  }

  // ---------- 设置页 ----------

  @Builder
  SettingsTab() {
    Scroll() {
      Column({ space: 12 }) {
        // 家庭成员（M7）
        MemberManage({
          rows: this.memberRows(),
          sectionLabel: this.strOf($r('app.string.member_section')),
          renameLabel: this.strOf($r('app.string.member_rename')),
          deleteLabel: this.strOf($r('app.string.library_delete')),
          addLabel: this.strOf($r('app.string.member_add')),
          onPick: (id: string) => this.applyMember(id),
          onRename: (id: string) => this.openRenameMember(id),
          onDelete: (id: string) => this.confirmDeleteMember(id),
          onAdd: () => this.openAddMember()
        })

        Column({ space: 12 }) {
          SectionLabel({ text: this.strOf($r('app.string.settings_display')) })
          InfoRow({
            label: this.strOf($r('app.string.settings_dark_mode')),
            value: this.strOf($r('app.string.settings_dark_value'))
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 12 }) {
          SectionLabel({ text: this.strOf($r('app.string.settings_about')) })
          InfoRow({
            label: this.strOf($r('app.string.buyout_note')),
            value: this.strOf($r('app.string.settings_restore_note'))
          })
          InfoRow({
            label: this.strOf($r('app.string.offline_note')),
            value: this.strOf($r('app.string.settings_privacy_note'))
          })
          Divider().color($r('app.color.border_color'))
          InfoRow({
            label: this.strOf($r('app.string.version_label')),
            value: this.strOf($r('app.string.version_value'))
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() {
          this.GeneratorTab()
        }
        .tabBar(TabBarItem({
          label: this.strOf($r('app.string.tab_generate')),
          selected: this.currentTab === 0
        }))
        TabContent() {
          this.LibraryTab()
        }
        .tabBar(TabBarItem({
          label: this.strOf($r('app.string.tab_library')),
          selected: this.currentTab === 1
        }))
        TabContent() {
          this.MistakesTab()
        }
        .tabBar(TabBarItem({
          label: this.strOf($r('app.string.tab_mistakes')),
          selected: this.currentTab === 2
        }))
        TabContent() {
          this.SettingsTab()
        }
        .tabBar(TabBarItem({
          label: this.strOf($r('app.string.tab_settings')),
          selected: this.currentTab === 3
        }))
      }
      .scrollable(false)
      .barHeight(54)
      .layoutWeight(1)
      .width('100%')
      .constraintSize({ maxWidth: WIDE_CONTENT_MAX_VP })
      .onChange((i: number) => {
        this.currentTab = i;
        if (i === 1) {
          this.reloadLibrary();
        } else if (i === 2) {
          this.reloadMistakes();
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
