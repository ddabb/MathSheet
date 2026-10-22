/**
 * 卷库页签 + 错题本页签（M7 从 Index 抽取，控单文件 ≤ 900 行）。
 *
 * 数据（metas / mistakes）由 Index 以 @Prop 注入（父侧状态变化即刷新）；
 * 交互（打开 / 批改 / 删除确认 / 清空 / 重练 / 去生成）以回调上抛。
 */

import { StoredMeta } from '../core/SheetCodec';
import { MistakeEntry } from '../core/MistakeCodec';
import { EmptyState } from './UiKit';

@Component
export struct LibraryPanel {
  @Prop metas: StoredMeta[] = [];
  private titleLabel: string = '';
  private emptyTitle: string = '';
  private emptyDesc: string = '';
  private goLabel: string = '';
  private openLabel: string = '';
  private gradeLabel: string = '';
  private deleteLabel: string = '';
  private onOpen: (id: string) => void = (_id: string): void => {
  };
  private onGrade: (id: string) => void = (_id: string): void => {
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
    return `${base} · ${statusText}`;
  }

  @Builder
  Card(m: StoredMeta) {
    Column({ space: 10 }) {
      Row() {
        Text(m.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.deleteLabel)
          .fontSize(12)
          .fontColor($r('app.color.hint_text'))
          .padding({ left: 10, top: 2, bottom: 2 })
          .onClick(() => this.onDelete(m))
      }
      .width('100%')

      Text(this.metaText(m))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')

      Row({ space: 8 }) {
        Text(this.openLabel)
          .fontSize(13)
          .fontColor($r('app.color.chip_text'))
          .backgroundColor($r('app.color.chip_bg'))
          .borderRadius(14)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .onClick(() => this.onOpen(m.id))
        Text(this.gradeLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_tint'))
          .borderRadius(14)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .onClick(() => this.onGrade(m.id))
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onOpen(m.id))
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
  private titleLabel: string = '';
  private clearButton: string = '';
  private emptyTitle: string = '';
  private emptyDesc: string = '';
  private goLabel: string = '';
  private drillTitle: string = '';
  private drillButton: string = '';
  private onClear: () => void = (): void => {
  };
  private onDrill: () => void = (): void => {
  };
  private onGo: () => void = (): void => {
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
    Row() {
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

      Text(e.a)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .constraintSize({ maxWidth: '42%' })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(14)
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
            goLabel: this.goLabel,
            onGo: () => this.onGo()
          })
        } else {
          // 重练卷行动卡
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
            Button(this.drillButton)
              .width('100%')
              .height(40)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.brand'))
              .borderRadius(20)
              .onClick(() => this.onDrill())
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
