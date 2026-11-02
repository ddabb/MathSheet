/**
 * 共享 UI 构件（M7 从 Index 抽取，控单文件 ≤ 900 行）。
 *
 * 全局 @Builder 传参规则：按值传参不随状态刷新；必须"单参数 + 调用处直接对象字面量"
 * （按引用）才能在组件状态变化时刷新 UI。因此此处所有 builder 均为
 * "参数类 + 单字面量调用"形态；文案由调用方解析（rm.getStringSync）后以 string 传入。
 *
 * v1.1.0 视觉重构：新增 SectionCard / PrimaryButton / GhostButton / Toolbar / BrandHeader，
 * 并为 OptionChip / Segmented / EmptyState 增加可选图标（emoji，零资源依赖、跨版本稳定）。
 * 图标后续可平滑替换为 SymbolGlyph 或定制 SVG，不影响调用方。
 */

export const WIDE_CONTENT_MAX_VP: number = 640;

/** @BuilderParam 默认值：必须是 @Builder 函数（空内容，仅作占位）。 */
@Builder
function emptyBuilder() {
}

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
  icon?: string;
  onTap: () => void = (): void => {
  };
}

@Builder
export function OptionChip(p: ChipParam) {
  Row({ space: p.icon ? 4 : 0 }) {
    if (p.icon) {
      Text(p.icon)
        .fontSize(14)
        .fontColor(p.selected ? $r('app.color.on_accent_text') : $r('app.color.chip_text'))
    }
    Text(p.label)
      .fontSize(14)
      .fontWeight(p.selected ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(p.selected ? $r('app.color.on_accent_text') : $r('app.color.chip_text'))
  }
  .backgroundColor(p.selected ? $r('app.color.brand') : $r('app.color.chip_bg'))
  .borderRadius($r('app.float.radius_pill'))
  .padding({ left: 16, right: 16, top: 7, bottom: 7 })
  .onClick(() => p.onTap())
}

/** 分段单选容器（年级 / 难度）：灰底圆角轨道 + 选中实心段。icons 与 labels 等长时显示图标。 */
export class SegmentedParam {
  labels: string[] = [];
  icons?: string[];
  selected: number = 0;
  onPick: (i: number) => void = (_i: number): void => {
  };
}

@Builder
export function Segmented(p: SegmentedParam) {
  Row() {
    ForEach(p.labels, (label: string, i: number) => {
      Row({ space: 4 }) {
        if (p.icons && p.icons.length > i && p.icons[i]) {
          Text(p.icons[i])
            .fontSize(14)
            .fontColor(i === p.selected ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
        }
        Text(label)
          .fontSize(14)
          .fontWeight(i === p.selected ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(i === p.selected ? $r('app.color.on_accent_text') : $r('app.color.secondary_text'))
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(i === p.selected ? $r('app.color.brand') : Color.Transparent)
      .borderRadius(10)
      .padding({ top: 8, bottom: 8 })
      .onClick(() => p.onPick(i))
    }, (label: string) => label)
  }
  .backgroundColor($r('app.color.chip_bg'))
  .borderRadius($r('app.float.radius_md'))
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

/** 空态页（卷库 / 错题本）：插画图标 + 标题 + 说明 + 去生成。 */
export class EmptyStateParam {
  title: string = '';
  desc: string = '';
  goLabel: string = '';
  icon: string = '';
  onGo: () => void = (): void => {
  };
}

@Builder
export function EmptyState(p: EmptyStateParam) {
  Column({ space: 12 }) {
    Blank()
    if (p.icon) {
      Text(p.icon)
        .fontSize(48)
        .margin({ bottom: 4 })
        .opacity(0.9)
    }
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
      .borderRadius($r('app.float.radius_pill'))
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

/* ============ v1.1.0 新增：布局与品牌组件 ============ */

/** 分组卡片容器：图标标题 + 内容槽，自带卡片阴影与圆角。 */
@Component
export struct SectionCard {
  @Prop icon: string = '';
  @Prop title: string = '';
  @BuilderParam content: () => void = emptyBuilder;

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        if (this.icon) {
          Text(this.icon)
            .fontSize(17)
            .fontColor($r('app.color.brand'))
        }
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
      }
      .alignItems(VerticalAlign.Center)
      .width('100%')
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.radius_lg'))
    .shadow({
      radius: $r('app.float.shadow_card_radius'),
      offsetY: $r('app.float.shadow_card_offset_y'),
      color: $r('app.color.shadow_color')
    })
  }
}

/** 主操作按钮：实心品牌色 + CTA 阴影，固定高度 48、圆角胶囊。 */
@Component
export struct PrimaryButton {
  @Prop label: string = '';
  @Prop icon: string = '';
  onTap: () => void = (): void => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 6 }) {
        if (this.icon) {
          Text(this.icon)
            .fontSize(18)
            .fontColor($r('app.color.on_accent_text'))
        }
        Text(this.label)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_accent_text'))
      }
    }
    .width('100%')
    .height($r('app.float.btn_height'))
    .borderRadius($r('app.float.radius_xl'))
    .backgroundColor($r('app.color.brand'))
    .shadow({
      radius: $r('app.float.shadow_cta_radius'),
      offsetY: $r('app.float.shadow_cta_offset_y'),
      color: $r('app.color.shadow_color')
    })
    .onClick(() => this.onTap())
  }
}

/** 次操作按钮：幽灵样式（透明底 + 品牌色描边/文字）。 */
@Component
export struct GhostButton {
  @Prop label: string = '';
  @Prop icon: string = '';
  onTap: () => void = (): void => {
  };

  build() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 6 }) {
        if (this.icon) {
          Text(this.icon)
            .fontSize(16)
            .fontColor($r('app.color.brand'))
        }
        Text(this.label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand'))
      }
    }
    .height(40)
    .padding({ left: 16, right: 16 })
    .borderRadius($r('app.float.radius_pill'))
    .backgroundColor(Color.Transparent)
    .border({ width: 1, color: $r('app.color.border_color') })
    .onClick(() => this.onTap())
  }
}

/** 底部工具条：左状态 + 右操作区，主次分明。 */
@Component
export struct Toolbar {
  @BuilderParam leading: () => void = emptyBuilder;
  @BuilderParam trailing: () => void = emptyBuilder;

  build() {
    Row() {
      this.leading()
      Blank()
      this.trailing()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.border_color') })
  }
}

/** 首页品牌头：应用图标 + 名称 + 离线徽标，作为视觉锚点。 */
@Component
export struct BrandHeader {
  @Prop name: string = '';
  @Prop badge: string = '';

  build() {
    Row({ space: 12 }) {
      Image($r('app.media.app_icon'))
        .width(44)
        .height(44)
        .borderRadius(12)
        .shadow({
          radius: $r('app.float.shadow_card_radius'),
          offsetY: $r('app.float.shadow_card_offset_y'),
          color: $r('app.color.shadow_color')
        })
      Column({ space: 4 }) {
        Text(this.name)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        if (this.badge) {
          Text(this.badge)
            .fontSize(11)
            .fontColor($r('app.color.success_green'))
            .backgroundColor($r('app.color.brand_tint'))
            .borderRadius($r('app.float.radius_pill'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
