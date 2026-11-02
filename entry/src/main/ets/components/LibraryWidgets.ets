/**
 * 卷库页签 + 错题本页签（M7 从 Index 抽取，控单文件 ≤ 900 行）。
 *
 * 数据（metas / mistakes）由 Index 以 @Prop 注入（父侧状态变化即刷新）；
 * 交互（打开 / 批改 / 删除确认 / 清空 / 重练 / 去生成）以回调上抛。
 */

import { StoredMeta } from '../core/SheetCodec';
import { MistakeEntry } from '../core/MistakeCodec';
import { EmptyState, PrimaryButton, Segmented, OptionChip } from './UiKit';

@Component
export struct LibraryPanel {
  @Prop metas: StoredMeta[] = [];
  private titleLabel: string = '';
  private emptyTitle: string = '';
  private emptyDesc: string = '';
  private goLabel: string = '';
  private openLabel: string = '';
  private gradeLabel: string = '';
  private quizLabel: string = '';
  private deleteLabel: string = '';
  private onOpen: (id: string) => void = (_id: string): void => {
  };
  private onGrade: (id: string) => void = (_id: string): void => {
  };
  private onQuiz: (id: string) => void = (_id: string): void => {
  };
  private onDelete: (m: StoredMeta) => void = (_m: StoredMeta): void => {
  };
  private onGo: () => void = (): void => {
  };

  private fmtShortDate(ts: number): string {
    const d: Date = new Date(ts);
    const mo: number = d.getMonth() + 1;
    const da: number = d.getDate();
    const moS: string = mo < 10 ? `0${mo}` : `${mo}`;
    const daS: string = da < 10 ? `0${da}` : `${da}`;
    return `${moS}-${daS}`;
  }

  /** 用时展示文案（120 → “2 分”；125 → “2 分 5 秒”）。 */
  private durationText(sec: number): string {
    const rm = this.getUIContext().getHostContext()?.resourceManager;
    if (rm === undefined) {
      return '';
    }
    if (sec % 60 === 0) {
      return rm.getStringSync($r('app.string.grade_duration_min').id, sec / 60);
    }
    return rm.getStringSync($r('app.string.grade_duration_ms').id,
      Math.floor(sec / 60), sec % 60);
  }

  private metaText(m: StoredMeta): string {
    const rm = this.getUIContext().getHostContext()?.resourceManager;
    if (rm === undefined) {
      return '';
    }
    const base: string = rm.getStringSync($r('app.string.library_count_date').id,
      m.count, this.fmtShortDate(m.createdAt));
    const statusRes: Resource = m.gradedCount > 0
      ? $r('app.string.library_meta_graded') : $r('app.string.library_meta_ungraded');
    const statusText: string = m.gradedCount > 0
      ? rm.getStringSync(statusRes.id, m.gradedCount, m.count, m.wrongCount)
      : rm.getStringSync(statusRes.id);
    let text: string = `${base} · ${statusText}`;
    if (m.durationSec > 0) {
      text = `${text} · ${this.durationText(m.durationSec)}`;
    }
    return text;
  }

  @Builder
  Card(m: StoredMeta) {
    Row({ space: 12 }) {
      // 缩略图占位（卷图标块）
      Column() {
        Text('📄')
          .fontSize(22)
      }
      .width(44)
      .height(44)
      .borderRadius($r('app.float.radius_md'))
      .backgroundColor($r('app.color.brand_tint'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 8 }) {
        Row() {
          Text(m.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 6 }) {
            Text(m.gradedCount > 0 ? '已批改' : '待批改')
              .fontSize(11)
              .fontColor(m.gradedCount > 0 ? $r('app.color.success_green') : $r('app.color.accent'))
              .backgroundColor(m.gradedCount > 0 ? $r('app.color.brand_tint') : $r('app.color.chip_bg'))
              .borderRadius($r('app.float.radius_pill'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            Text('🗑️')
              .fontSize(14)
              .fontColor($r('app.color.hint_text'))
              .padding({ left: 6, top: 2, bottom: 2 })
              .onClick(() => this.onDelete(m))
          }
        }
        .width('100%')

        Text(this.metaText(m))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .width('100%')

        Row({ space: 8 }) {
          Text('📖 ' + this.openLabel)
            .fontSize(13)
            .fontColor($r('app.color.chip_text'))
            .backgroundColor($r('app.color.chip_bg'))
            .borderRadius($r('app.float.radius_pill'))
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => this.onOpen(m.id))
          if (m.gradedCount === 0) {
            Text('✏️ ' + this.quizLabel)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.brand_tint'))
              .borderRadius($r('app.float.radius_pill'))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .onClick(() => this.onQuiz(m.id))
          }
          Text('✓ ' + this.gradeLabel)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.brand_tint'))
            .borderRadius($r('app.float.radius_pill'))
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .onClick(() => this.onGrade(m.id))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.radius_lg'))
    .shadow({
      radius: $r('app.float.shadow_card_radius'),
      offsetY: $r('app.float.shadow_card_offset_y'),
      color: $r('app.color.shadow_color')
    })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text(this.titleLabel)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          if (this.metas.length > 0) {
            Text(`${this.metas.length}`)
              .fontSize(12)
              .fontColor($r('app.color.hint_text'))
          }
        }
        .width('100%')

        if (this.metas.length === 0) {
          EmptyState({
            title: this.emptyTitle,
            desc: this.emptyDesc,
            icon: '📚',
            goLabel: this.goLabel,
            onGo: () => this.onGo()
          })
        } else {
          ForEach(this.metas, (m: StoredMeta) => {
            this.Card(m)
          }, (m: StoredMeta) => `${m.id}-${m.gradedCount}-${m.wrongCount}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 16, right: 16, top: 14, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
  }
}

@Component
export struct MistakesPanel {
  @Prop mistakes: MistakeEntry[] = [];
  /** 重练模式（1.0.1 M1）：0 = 仅错题，1 = 错题+同类新题。 */
  @Prop drillMode: number = 1;
  /** 混编比例（1.0.1 M1）：1|2|3（仅错题+同类模式生效）。 */
  @Prop drillRatio: number = 2;
  private titleLabel: string = '';
  private clearButton: string = '';
  private emptyTitle: string = '';
  private emptyDesc: string = '';
  private goLabel: string = '';
  private drillTitle: string = '';
  private drillButton: string = '';
  private modeLabels: string[] = [];
  private ratioLabel: string = '';
  private ratioLabels: string[] = [];
  private onClear: () => void = (): void => {
  };
  private onDrill: () => void = (): void => {
  };
  private onGo: () => void = (): void => {
  };
  private onPickMode: (i: number) => void = (_i: number): void => {
  };
  private onPickRatio: (i: number) => void = (_i: number): void => {
  };

  private countText(): string {
    const rm = this.getUIContext().getHostContext()?.resourceManager;
    return rm === undefined ? '' : rm.getStringSync($r('app.string.mistakes_count').id, this.mistakes.length);
  }

  private metaText(e: MistakeEntry): string {
    const rm = this.getUIContext().getHostContext()?.resourceManager;
    return rm === undefined ? ''
      : rm.getStringSync($r('app.string.mistakes_entry_meta').id, e.wrongCount, e.srcTitle);
  }

  @Builder
  Row2(e: MistakeEntry) {
    Row({ space: 10 }) {
      // 错题图标块
      Column() {
        Text('❌')
          .fontSize(16)
      }
      .width(32)
      .height(32)
      .borderRadius($r('app.float.radius_sm'))
      .backgroundColor($r('app.color.answer_tint'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 4 }) {
        Text(e.q)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.metaText(e))
          .fontSize(11)
          .fontColor($r('app.color.hint_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('＝ ' + e.a)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .constraintSize({ maxWidth: '40%' })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.radius_lg'))
    .shadow({
      radius: $r('app.float.shadow_card_radius'),
      offsetY: $r('app.float.shadow_card_offset_y'),
      color: $r('app.color.shadow_color')
    })
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text(this.titleLabel)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          if (this.mistakes.length > 0) {
            Text(this.clearButton)
              .fontSize(12)
              .fontColor($r('app.color.hint_text'))
              .padding({ left: 10, top: 4, bottom: 4 })
              .onClick(() => this.onClear())
          }
        }
        .width('100%')

        if (this.mistakes.length === 0) {
          EmptyState({
            title: this.emptyTitle,
            desc: this.emptyDesc,
            icon: '✏️',
            goLabel: this.goLabel,
            onGo: () => this.onGo()
          })
        } else {
          // 重练卷行动卡（1.0.1 M1：模式 + 比例可选）
          Column({ space: 10 }) {
            Row() {
              Text(this.drillTitle)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Text(this.countText())
                .fontSize(12)
                .fontColor($r('app.color.secondary_text'))
            }
            .width('100%')
            Segmented({
              labels: this.modeLabels,
              selected: this.drillMode,
              onPick: (i: number) => this.onPickMode(i)
            })
            if (this.drillMode === 1) {
              Row({ space: 8 }) {
                Text(this.ratioLabel)
                  .fontSize(12)
                  .fontColor($r('app.color.secondary_text'))
                ForEach(this.ratioLabels, (label: string, i: number) => {
                  OptionChip({
                    label: label,
                    selected: this.drillRatio === i + 1,
                    onTap: () => this.onPickRatio(i + 1)
                  })
                }, (label: string) => label)
              }
              .width('100%')
            }
            PrimaryButton({
              label: this.drillButton,
              icon: '🔁',
              onTap: () => this.onDrill()
            })
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(14)
          .alignItems(HorizontalAlign.Start)

          ForEach(this.mistakes, (e: MistakeEntry, i: number) => {
            this.Row2(e)
          }, (e: MistakeEntry) => `${e.key}-${e.wrongCount}-${e.srcTitle}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 16, right: 16, top: 14, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring)
  }
}
