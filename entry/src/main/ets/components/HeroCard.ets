/**
 * 每日一练 Hero 卡（M7 从 Index 抽取）：记忆上次生成配置，一键"生成今天的题卡"
 * + 本地连续打卡展示。文案由父组件解析后以 @Prop 传入（状态变化父侧重渲染即刷新）。
 */

@Component
export struct HeroCard {
  /** 日期文案（如 "10月21日" / "Oct 21"）。 */
  @Prop dateText: string = '';
  /** 打卡状态文案（已练 / 待练 / 未开始）。 */
  @Prop streakText: string = '';
  /** 上次配置摘要（空 = 无记忆，隐藏行）。 */
  @Prop cfgText: string = '';
  @Prop hasConfig: boolean = false;
  private onToday: () => void = (): void => {
  };

  build() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text('📅')
              .fontSize(17)
              .fontColor($r('app.color.on_accent_text'))
            Text($r('app.string.daily_title'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
          }
          Text(`${this.dateText} · ${this.streakText}`)
            .fontSize(12)
            .fontColor($r('app.color.on_accent_text'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      // 配置摘要行恒占位（透明占位替代条件渲染）：hasConfig 翻转时卡片高度零跳动，
      // 下方表单 chips 坐标稳定（批改走查两次踩中 +52px 位移陷阱的根治项）。
      Text(this.cfgText)
        .fontSize(12)
        .fontColor($r('app.color.on_accent_text'))
        .opacity(this.hasConfig ? 0.85 : 0)
        .constraintSize({ minHeight: 16 })
      Button($r('app.string.daily_generate_button'))
        .width('100%')
        .height($r('app.float.btn_height'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.brand'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius($r('app.float.radius_xl'))
        .shadow({
          radius: $r('app.float.shadow_card_radius'),
          offsetY: $r('app.float.shadow_card_offset_y'),
          color: $r('app.color.shadow_color')
        })
        .onClick(() => this.onToday())
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.brand'))
    .borderRadius(18)
    .alignItems(HorizontalAlign.Start)
  }
}
