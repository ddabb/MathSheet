/**
 * 共享 UI 构件（M7 从 Index 抽取，控单文件 ≤ 900 行）。
 *
 * 全局 @Builder 传参规则：按值传参不随状态刷新；必须"单参数 + 调用处直接对象字面量"
 * （按引用）才能在组件状态变化时刷新 UI。因此此处所有 builder 均为
 * "参数类 + 单字面量调用"形态；文案由调用方解析（rm.getStringSync）后以 string 传入。
 */

export const WIDE_CONTENT_MAX_VP: number = 640;

export class SectionParam {
  text: string = '';
}

@Builder
export function SectionLabel(p: SectionParam) {
  Text(p.text)
    .fontSize(13)
    .fontColor($r('app.color.hint_text'))
}

export class ChipParam {
  label: string = '';
  selected: boolean = false;
  onTap: () => void = (): void => {
  };
}

@Builder
export function OptionChip(p: ChipParam) {
  Text(p.label)
    .fontSize(14)
    .fontWeight(p.selected ? FontWeight.Bold : FontWeight.Normal)
    .fontColor(p.selected ? $r('app.color.on_accent_text') : $r('app.color.chip_text'))
    .backgroundColor(p.selected ? $r('app.color.brand') : $r('app.color.chip_bg'))
    .borderRadius(14)
    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
    .onClick(() => p.onTap())
}

/** 分段单选容器（年级 / 难度）：灰底圆角轨道 + 选中实心段。 */
export class SegmentedParam {
  labels: string[] = [];
  selected: number = 0;
  onPick: (i: number) => void = (_i: number): void => {
  };
}

@Builder
export function Segmented(p: SegmentedParam) {
  Row() {
    ForEach(p.labels, (label: string, i: number) => {
      Text(label)
        .fontSize(14)
        .fontWeight(i === p.selected ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(i === p.selected ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
        .backgroundColor(i === p.selected ? $r('app.color.brand') : Color.Transparent)
        .borderRadius(10)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .padding({ top: 8, bottom: 8 })
        .onClick(() => p.onPick(i))
    }, (label: string) => label)
  }
  .backgroundColor($r('app.color.chip_bg'))
  .borderRadius(12)
  .padding(3)
}

export class ToggleRowParam {
  label: string = '';
  isOn: boolean = false;
  onFlip: (v: boolean) => void = (_v: boolean): void => {
  };
}

@Builder
export function ToggleRow(p: ToggleRowParam) {
  Row() {
    Text(p.label)
      .fontSize(14)
      .fontColor($r('app.color.primary_text'))
      .layoutWeight(1)
    Toggle({ type: ToggleType.Switch, isOn: p.isOn })
      .onChange((v: boolean) => p.onFlip(v))
  }
}

export class TabBarItemParam {
  label: string = '';
  selected: boolean = false;
}

@Builder
export function TabBarItem(p: TabBarItemParam) {
  Column() {
    Text(p.label)
      .fontSize(13)
      .fontWeight(p.selected ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(p.selected ? $r('app.color.brand') : $r('app.color.hint_text'))
  }
  .justifyContent(FlexAlign.Center)
  .height('100%')
}

/** 空态页（卷库 / 错题本）：标题 + 说明 + 去生成。 */
export class EmptyStateParam {
  title: string = '';
  desc: string = '';
  goLabel: string = '';
  onGo: () => void = (): void => {
  };
}

@Builder
export function EmptyState(p: EmptyStateParam) {
  Column({ space: 12 }) {
    Blank()
    Text(p.title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.primary_text'))
    Text(p.desc)
      .fontSize(13)
      .fontColor($r('app.color.secondary_text'))
      .textAlign(TextAlign.Center)
      .padding({ left: 40, right: 40 })
    Button(p.goLabel)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.brand'))
      .backgroundColor($r('app.color.brand_tint'))
      .borderRadius(18)
      .padding({ left: 22, right: 22, top: 8, bottom: 8 })
      .margin({ top: 6 })
      .onClick(() => p.onGo())
    Blank()
  }
  .width('100%')
  .height('100%')
  .alignItems(HorizontalAlign.Center)
}

/** 设置行：左标签 + 右说明。 */
export class InfoRowParam {
  label: string = '';
  value: string = '';
}

@Builder
export function InfoRow(p: InfoRowParam) {
  Row() {
    Text(p.label)
      .fontSize(14)
      .fontColor($r('app.color.primary_text'))
      .layoutWeight(1)
    Text(p.value)
      .fontSize(13)
      .fontColor($r('app.color.secondary_text'))
  }
}
