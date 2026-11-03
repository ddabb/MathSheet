/**
 * 预览页弹层/操作组件（PreviewPage 行数护栏拆出，控单文件 ≤ 900 行；样式沿用 UiKit 资源 Token）：
 * - PreviewActions：底栏右侧操作药丸组（换一批/保存图片/导出 PDF）；
 * - PdfOptionsDialog：导出 PDF 选项弹层（题目/答案页独立页码开关，开关状态由页面持有、会话内记忆）；
 * - ExportingOverlay：导出合成中遮罩（PDF/长图两态文案）。
 */

import { ToggleRow } from './UiKit';

/** 底栏右侧操作：统一 40 高内容宽紧凑药丸（修复：原 GhostButton/PrimaryButton 组合
 * 在 360vp 屏上总宽超出屏宽、且 PrimaryButton 内部 width('100%') 撑满挤压，导出 PDF 文字被裁）。 */
@Component
export struct PreviewActions {
  @Prop showChangeBatch: boolean = false;
  onChangeBatch: () => void = (): void => {
  };
  onSaveImage: () => void = (): void => {
  };
  onExportPdf: () => void = (): void => {
  };

  build() {
    Row({ space: 6 }) {
      if (this.showChangeBatch) {
        Button($r('app.string.change_batch'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand'))
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.border_color') })
          .borderRadius($r('app.float.radius_pill'))
          .height(40)
          .padding({ left: 12, right: 12 })
          .onClick(() => this.onChangeBatch())
      }
      Button($r('app.string.save_image_button'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand'))
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: $r('app.color.border_color') })
        .borderRadius($r('app.float.radius_pill'))
        .height(40)
        .padding({ left: 12, right: 12 })
        .onClick(() => this.onSaveImage())
      Button($r('app.string.export_pdf_button'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.brand'))
        .borderRadius($r('app.float.radius_pill'))
        .height(40)
        .padding({ left: 12, right: 12 })
        .onClick(() => this.onExportPdf())
    }
    .alignItems(VerticalAlign.Center)
  }
}

/** 导出 PDF 选项弹层：题目/答案页独立页码开关（文案由调用方解析后传入，沿用 UiKit 惯例）。 */
@Component
export struct PdfOptionsDialog {
  @Prop numSep: boolean = false;
  @Prop toggleLabel: string = '';
  onFlip: (v: boolean) => void = (_v: boolean): void => {
  };
  onCancel: () => void = (): void => {
  };
  onConfirm: () => void = (): void => {
  };

  build() {
    Column() {
      Column({ space: 14 }) {
        Text($r('app.string.export_pdf_button'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Column({ space: 6 }) {
          ToggleRow({
            label: this.toggleLabel,
            isOn: this.numSep,
            onFlip: this.onFlip
          })
          Text($r('app.string.pdf_num_sep_hint'))
            .fontSize(11)
            .fontColor($r('app.color.hint_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        Row({ space: 10 }) {
          Button($r('app.string.dialog_cancel'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.secondary_text'))
            .backgroundColor($r('app.color.chip_bg'))
            .borderRadius($r('app.float.radius_pill'))
            .layoutWeight(1)
            .height(44)
            .onClick(() => this.onCancel())
          Button($r('app.string.export_pdf_button'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.on_accent_text'))
            .backgroundColor($r('app.color.brand'))
            .borderRadius($r('app.float.radius_pill'))
            .layoutWeight(1)
            .height(44)
            .onClick(() => this.onConfirm())
        }
        .width('100%')
      }
      .padding(20)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius($r('app.float.radius_lg'))
      .width('84%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000')
  }
}

/** 导出合成中遮罩：居中圆角深色卡片（exporting 1=PDF 合成 2=长图合成）。 */
@Component
export struct ExportingOverlay {
  @Prop exporting: number = 0;

  build() {
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
