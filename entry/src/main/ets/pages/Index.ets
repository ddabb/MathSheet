@Entry
@Component
struct Index {
  build() {
    Scroll() {
      Column({ space: 16 }) {
        // 品牌卡：应用名 + 一句话定位 + 买断/离线标签
        Column({ space: 10 }) {
          Text($r('app.string.app_name'))
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text($r('app.string.app_tagline'))
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
            .textAlign(TextAlign.Center)
          Row({ space: 8 }) {
            Text($r('app.string.buyout_note'))
              .fontSize(11)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.brand_tint'))
              .borderRadius(10)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            Text($r('app.string.offline_note'))
              .fontSize(11)
              .fontColor($r('app.color.brand'))
              .backgroundColor($r('app.color.brand_tint'))
              .borderRadius(10)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          }
        }
        .width('90%')
        .padding(20)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .justifyContent(FlexAlign.Center)

        // 版本行
        Row({ space: 6 }) {
          Text($r('app.string.version_label'))
            .fontSize(12)
            .fontColor($r('app.color.hint_text'))
          Text($r('app.string.version_value'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
        }

        // M0 脚手架卡：P0 模块清单
        Column({ space: 12 }) {
          Text($r('app.string.scaffold_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Text($r('app.string.scaffold_desc'))
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
          ForEach([
            $r('app.string.mod_presets'),
            $r('app.string.mod_engine'),
            $r('app.string.mod_sets'),
            $r('app.string.mod_layout'),
            $r('app.string.mod_daily'),
            $r('app.string.mod_mistake'),
            $r('app.string.mod_library')
          ], (item: ResourceStr) => {
            Row({ space: 8 }) {
              Text('\u2022')
                .fontSize(13)
                .fontColor($r('app.color.brand'))
              Text(item)
                .fontSize(13)
                .fontColor($r('app.color.primary_text'))
            }
            .alignItems(VerticalAlign.Center)
          })
        }
        .width('90%')
        .padding(20)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        Text($r('app.string.plan_note'))
          .fontSize(12)
          .fontColor($r('app.color.hint_text'))
          .textAlign(TextAlign.Center)
          .width('90%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 32, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
