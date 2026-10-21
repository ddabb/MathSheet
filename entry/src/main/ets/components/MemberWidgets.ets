/**
 * 家庭成员 UI（M7，计划 §5.3）：本地多档（非账号，无登录无云端）。
 *
 * - MemberBar：生成页成员快捷条（点击切换当前成员 + 新增入口）；
 * - MemberManage：设置页成员管理卡（列表 / 改名 / 删除 / 新增）；
 * - MemberEditDialog：成员编辑内容组件（昵称 + 年级），由 Index 通过
 *   UIContext.getPromptAction().openCustomDialog() 打开（数据预置后开弹窗，
 *   校验失败 toast 提示且不关闭）。
 * 数据模型（昵称 6 码点钳制、年级 1-3）约束见 core/ProfileCodec。
 */

import { ProfileCodec } from '../core/ProfileCodec';

/** 成员快捷条数据（Index 由 ProfileIndex 派生）。 */
export class MemberChip {
  id: string = '';
  name: string = '';
  isCurrent: boolean = false;
}

/** 成员管理行数据（subText 由 Index 拼好：年级 · 当前标记）。 */
export class MemberRowModel {
  id: string = '';
  name: string = '';
  subText: string = '';
  canDelete: boolean = true;
}

/** 弹窗文案（Index 解析资源后传入，弹窗不直接持有 Context）。 */
export class MemberDialogTexts {
  title: string = '';
  nameHint: string = '';
  gradeLabel: string = '';
  grades: string[] = [];
  cancel: string = '';
  confirm: string = '';
  nameEmptyToast: string = '';
}

@Component
export struct MemberBar {
  @Prop chips: MemberChip[] = [];
  private currentTag: string = '';
  private addLabel: string = '';
  private onPick: (id: string) => void = (_id: string): void => {
  };
  private onAdd: () => void = (): void => {
  };

  build() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
      ForEach(this.chips, (c: MemberChip) => {
        Text(c.isCurrent ? `${c.name} · ${this.currentTag}` : c.name)
          .fontSize(13)
          .fontWeight(c.isCurrent ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(c.isCurrent ? $r('app.color.on_accent_text') : $r('app.color.chip_text'))
          .backgroundColor(c.isCurrent ? $r('app.color.brand') : $r('app.color.chip_bg'))
          .borderRadius(14)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .margin({ right: 8, bottom: 8 })
          .onClick(() => this.onPick(c.id))
      }, (c: MemberChip) => `${c.id}-${c.isCurrent}`)
      Text(`+ ${this.addLabel}`)
        .fontSize(13)
        .fontColor($r('app.color.brand'))
        .backgroundColor($r('app.color.brand_tint'))
        .borderRadius(14)
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .margin({ bottom: 8 })
        .onClick(() => this.onAdd())
    }
    .width('100%')
  }
}

@Component
export struct MemberManage {
  @Prop rows: MemberRowModel[] = [];
  private sectionLabel: string = '';
  private renameLabel: string = '';
  private deleteLabel: string = '';
  private addLabel: string = '';
  private onPick: (id: string) => void = (_id: string): void => {
  };
  private onRename: (id: string) => void = (_id: string): void => {
  };
  private onDelete: (id: string) => void = (_id: string): void => {
  };
  private onAdd: () => void = (): void => {
  };

  build() {
    Column({ space: 12 }) {
      Text(this.sectionLabel)
        .fontSize(13)
        .fontColor($r('app.color.hint_text'))
      ForEach(this.rows, (r: MemberRowModel) => {
        Row() {
          Column({ space: 3 }) {
            Text(r.name)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(r.subText)
              .fontSize(11)
              .fontColor($r('app.color.hint_text'))
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(this.renameLabel)
            .fontSize(12)
            .fontColor($r('app.color.hint_text'))
            .padding({ left: 10, top: 4, bottom: 4 })
            .onClick(() => this.onRename(r.id))
          if (r.canDelete) {
            Text(this.deleteLabel)
              .fontSize(12)
              .fontColor($r('app.color.danger_red'))
              .padding({ left: 10, top: 4, bottom: 4 })
              .onClick(() => this.onDelete(r.id))
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.chip_bg'))
        .borderRadius(12)
        .onClick(() => this.onPick(r.id))
      }, (r: MemberRowModel) => `${r.id}-${r.subText}`)
      Button(this.addLabel)
        .width('100%')
        .height(38)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.brand'))
        .backgroundColor($r('app.color.brand_tint'))
        .borderRadius(19)
        .onClick(() => this.onAdd())
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }
}

/** 成员编辑弹窗内容（新增 / 改名共用；经 openCustomDialog 展示）。 */
@Component
export struct MemberEditDialog {
  private texts: MemberDialogTexts = new MemberDialogTexts();
  private initialName: string = '';
  private initialGrade: number = 2;
  private onConfirm: (name: string, grade: number) => void = (_n: string, _g: number): void => {
  };
  /** 关闭请求（确认成功或取消时均回调，由持有弹窗 id 的一方执行关闭）。 */
  private onRequestClose: () => void = (): void => {
  };
  @State name: string = '';
  @State grade: number = 2;

  aboutToAppear(): void {
    this.name = this.initialName;
    this.grade = ProfileCodec.clampGrade(this.initialGrade);
  }

  private confirm(): void {
    const clean: string = ProfileCodec.clampName(this.name);
    if (clean === '') {
      this.getUIContext().getPromptAction()
        .showToast({ message: this.texts.nameEmptyToast, duration: 2000 });
      return;
    }
    this.onConfirm(clean, ProfileCodec.clampGrade(this.grade));
    this.onRequestClose();
  }

  build() {
    Column({ space: 14 }) {
      Text(this.texts.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))

      TextInput({ text: this.name, placeholder: this.texts.nameHint })
        .fontSize(15)
        .height(44)
        .backgroundColor($r('app.color.chip_bg'))
        .borderRadius(10)
        .onChange((v: string) => {
          this.name = ProfileCodec.cutName(v);
        })

      Column({ space: 8 }) {
        Text(this.texts.gradeLabel)
          .fontSize(13)
          .fontColor($r('app.color.hint_text'))
        Row({ space: 8 }) {
          ForEach(this.texts.grades, (label: string, i: number) => {
            Text(label)
              .fontSize(14)
              .fontWeight(i === this.grade - 1 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(i === this.grade - 1 ? $r('app.color.on_accent_text') : $r('app.color.chip_text'))
              .backgroundColor(i === this.grade - 1 ? $r('app.color.brand') : $r('app.color.chip_bg'))
              .borderRadius(12)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
              .onClick(() => {
                this.grade = i + 1;
              })
          }, (label: string, i: number) => `${i}-${label}`)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row({ space: 10 }) {
        Button(this.texts.cancel)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .backgroundColor($r('app.color.chip_bg'))
          .borderRadius(20)
          .onClick(() => this.onRequestClose())
        Button(this.texts.confirm)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_accent_text'))
          .backgroundColor($r('app.color.brand'))
          .borderRadius(20)
          .onClick(() => this.confirm())
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .padding(20)
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(18)
    .alignItems(HorizontalAlign.Start)
  }
}
