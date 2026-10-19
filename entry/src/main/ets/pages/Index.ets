/**
 * 生成器主页（计划 §5.1）：年级分段 + 题型多选 chips + 题数/列数 +
 * 高级开关（题头/答案页）→ 生成题卡（携带配置跳转 PreviewPage，同参数同种子同卷）。
 * M2 范围：生成 → 预览闭环；每日一练（M4）/ 底部页签（随卷库、错题本批次）暂未引入。
 */

import { i18n } from '@kit.LocalizationKit';
import { GradePresets, PresetEntry } from '../core/GradePresets';
import { PreviewParams } from '../common/PreviewParams';

const COUNT_OPTIONS: number[] = [20, 50, 100, 200];
const COLUMN_OPTIONS: number[] = [2, 3, 4];
const GRADES: number[] = [1, 2, 3];

@Entry
@Component
struct Index {
  @State grade: number = 2;
  @State selectedIds: string[] = ['g2_add100_plus', 'g2_mul_table', 'g2_div_table'];
  @State problemCount: number = 50;
  @State columns: number = 3;
  @State headerOn: boolean = true;
  @State answerOn: boolean = true;

  private labelOf(entry: PresetEntry): string {
    const lang: string = i18n.getSystemLanguage();
    return lang.indexOf('zh') === 0 ? entry.labelZh : entry.labelEn;
  }

  private defaultIdsForGrade(grade: number): string[] {
    if (grade === 1) {
      return ['g1_add20_plus', 'g1_sub20_plus'];
    }
    if (grade === 3) {
      return ['g3_add_3d', 'g3_sub_3d'];
    }
    return ['g2_add100_plus', 'g2_mul_table', 'g2_div_table'];
  }

  private toggleType(id: string): void {
    const next: string[] = this.selectedIds.slice();
    const pos: number = next.indexOf(id);
    if (pos >= 0) {
      next.splice(pos, 1);
    } else {
      next.push(id);
    }
    this.selectedIds = next;
  }

  private generate(): void {
    if (this.selectedIds.length === 0) {
      this.getUIContext().getPromptAction()
        .showToast({ message: $r('app.string.pick_type_first'), duration: 2500 });
      return;
    }
    const params: PreviewParams = {
      typeIds: this.selectedIds.slice(),
      seed: Math.floor(Math.random() * 2147483647),
      count: this.problemCount,
      columns: this.columns,
      headerOn: this.headerOn,
      answerOn: this.answerOn
    };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PreviewPage', params: params });
  }

  @Builder
  SectionLabel(res: Resource) {
    Text(res)
      .fontSize(13)
      .fontColor($r('app.color.hint_text'))
  }

  @Builder
  OptionChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(14)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(selected ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
      .backgroundColor(selected ? $r('app.color.brand') : $r('app.color.card_background'))
      .borderRadius(14)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .onClick(() => onTap())
  }

  @Builder
  BrandBadge(res: Resource) {
    Text(res)
      .fontSize(11)
      .fontColor($r('app.color.brand'))
      .backgroundColor($r('app.color.brand_tint'))
      .borderRadius(10)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 品牌行
          Column({ space: 8 }) {
            Text($r('app.string.app_name'))
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Text($r('app.string.app_tagline'))
              .fontSize(13)
              .fontColor($r('app.color.secondary_text'))
            Row({ space: 8 }) {
              this.BrandBadge($r('app.string.buyout_note'))
              this.BrandBadge($r('app.string.offline_note'))
            }
          }
          .width('90%')
          .padding({ top: 18, bottom: 4 })
          .alignItems(HorizontalAlign.Start)

          // 表单卡
          Column({ space: 12 }) {
            this.SectionLabel($r('app.string.grade_label'))
            Row({ space: 8 }) {
              ForEach(GRADES, (g: number) => {
                Text(g === 1 ? $r('app.string.grade_g1')
                  : g === 3 ? $r('app.string.grade_g3') : $r('app.string.grade_g2'))
                  .fontSize(14)
                  .fontWeight(this.grade === g ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.grade === g ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
                  .backgroundColor(this.grade === g ? $r('app.color.brand') : $r('app.color.card_background'))
                  .borderRadius(16)
                  .padding({ left: 18, right: 18, top: 8, bottom: 8 })
                  .onClick(() => {
                    if (this.grade !== g) {
                      this.grade = g;
                      this.selectedIds = this.defaultIdsForGrade(g);
                    }
                  })
              }, (g: number) => g.toString())
            }

            Divider().color($r('app.color.border_color'))
            this.SectionLabel($r('app.string.type_label'))
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(GradePresets.forGrade(this.grade), (entry: PresetEntry) => {
                Text(this.labelOf(entry))
                  .fontSize(13)
                  .fontColor(this.selectedIds.indexOf(entry.id) >= 0 ? $r('app.color.on_accent_text')
                    : $r('app.color.primary_text'))
                  .backgroundColor(this.selectedIds.indexOf(entry.id) >= 0 ? $r('app.color.brand')
                    : $r('app.color.page_background'))
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => this.toggleType(entry.id))
              }, (entry: PresetEntry) => entry.id)
            }

            Divider().color($r('app.color.border_color'))
            this.SectionLabel($r('app.string.count_label'))
            Row({ space: 8 }) {
              ForEach(COUNT_OPTIONS, (n: number) => {
                this.OptionChip(n.toString(), this.problemCount === n, () => {
                  this.problemCount = n;
                })
              }, (n: number) => 'c' + n.toString())
            }

            this.SectionLabel($r('app.string.columns_label'))
            Row({ space: 8 }) {
              ForEach(COLUMN_OPTIONS, (n: number) => {
                this.OptionChip(n.toString(), this.columns === n, () => {
                  this.columns = n;
                })
              }, (n: number) => 'k' + n.toString())
            }

            Divider().color($r('app.color.border_color'))
            this.SectionLabel($r('app.string.advanced_label'))
            Row({ space: 8 }) {
              Text($r('app.string.header_toggle_label'))
                .fontSize(14)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.headerOn })
                .onChange((isOn: boolean) => {
                  this.headerOn = isOn;
                })
            }
            Row({ space: 8 }) {
              Text($r('app.string.answer_page_toggle_label'))
                .fontSize(14)
                .fontColor($r('app.color.primary_text'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.answerOn })
                .onChange((isOn: boolean) => {
                  this.answerOn = isOn;
                })
            }
          }
          .width('90%')
          .padding(18)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Center)
      .edgeEffect(EdgeEffect.Spring)

      // 底部：主按钮 + 版本行
      Column({ space: 6 }) {
        Button($r('app.string.generate_button'))
          .width('90%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .backgroundColor($r('app.color.brand'))
          .borderRadius(24)
          .onClick(() => this.generate())
        Row({ space: 6 }) {
          Text($r('app.string.version_label'))
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
          Text($r('app.string.version_value'))
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
        }
      }
      .width('100%')
      .padding({ top: 10, bottom: 12 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
