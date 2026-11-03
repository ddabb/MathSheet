/**
 * 设置页签（1.0.1 M6 从 Index 抽取，控单文件 ≤ 900 行）。
 *
 * 结构：家庭成员管理（MemberManage）+ 备份与恢复（BackupStore 全量导出/导入）
 *       + 显示信息 + 关于信息。
 * 数据（rows 成员行）由 Index 以 @Prop 注入（父侧状态变化即刷新）；
 * 成员交互（切换 / 改名 / 删除 / 新增）以回调上抛；
 * 备份导出与恢复流程在面板内闭环，恢复成功后经 onRestored 通知首页整体刷新。
 */

import { BackupStore } from '../common/BackupStore';
import { ExportUtil, ExportOutcome } from '../common/ExportUtil';
import { resourceManager } from '@kit.LocalizationKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { MemberRowModel, MemberManage } from './MemberWidgets';
import { SectionLabel, InfoRow, GhostButton, PrimaryButton } from './UiKit';

@Component
export struct SettingsPanel {
  @Prop rows: MemberRowModel[] = [];
  private sectionLabel: string = '';
  private renameLabel: string = '';
  private deleteLabel: string = '';
  private addLabel: string = '';
  private backupSectionLabel: string = '';
  private backupExportLabel: string = '';
  private backupImportLabel: string = '';
  private displayLabel: string = '';
  private aboutLabel: string = '';
  private onPick: (id: string) => void = (_id: string): void => {
  };
  private onRename: (id: string) => void = (_id: string): void => {
  };
  private onDelete: (id: string) => void = (_id: string): void => {
  };
  private onAdd: () => void = (): void => {
  };
  private onRestored: () => void = (): void => {
  };

  /** 同步取字符串资源（信息行文案在面板内解析，减少父组件传参）。 */
  private strOf(res: Resource): string {
    const rm: resourceManager.ResourceManager | undefined =
      this.getUIContext().getHostContext()?.resourceManager;
    return rm === undefined ? '' : rm.getStringSync(res.id);
  }

  /** 当前外观模式文案（浅色/深色 · 跟随系统）：修复浅色模式下原静态“深色模式”文案错误。 */
  private colorModeText(): string {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    const abilityCtx: common.UIAbilityContext | undefined =
      ctx !== undefined ? ctx as common.UIAbilityContext : undefined;
    const dark: boolean = abilityCtx !== undefined
      && abilityCtx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    return this.strOf(dark ? $r('app.string.settings_mode_dark')
      : $r('app.string.settings_mode_light'));
  }

  /** 全量备份 → 沙箱临时文件 → 系统保存器（用户选位置；免权限）。 */
  private exportBackup(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    BackupStore.buildTempFile(ctx).then((tmp: string | null) => {
      if (tmp === null) {
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.backup_empty_toast'), duration: 2500 });
        return;
      }
      ExportUtil.saveToDocument(this.getUIContext(), tmp,
        BackupStore.exportFileName(), '.json').then((r: number) => {
        if (r === ExportOutcome.FAIL) {
          this.getUIContext().getPromptAction()
            .showToast({ message: $r('app.string.backup_export_fail_toast'), duration: 2500 });
        } else if (r === ExportOutcome.SAVED) {
          this.getUIContext().getPromptAction()
            .showToast({ message: $r('app.string.backup_saved_toast'), duration: 2000 });
        }
      });
    });
  }

  /** 选择备份文件 → 读取 → 确认覆盖 → 整体恢复。 */
  private pickRestoreFile(): void {
    ExportUtil.pickDocument(this.getUIContext(), ['.json']).then((uri: string | null) => {
      if (uri === null) {
        return;
      }
      const text: string | null = BackupStore.readPicked(uri);
      if (text === null || text === '') {
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.backup_invalid_toast'), duration: 2500 });
        return;
      }
      this.confirmRestore(text);
    });
  }

  private confirmRestore(text: string): void {
    const param: AlertDialogParamWithButtons = {
      title: $r('app.string.backup_confirm_title'),
      message: $r('app.string.backup_confirm_msg'),
      autoCancel: false,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.backup_confirm_ok'),
        action: () => this.doRestore(text)
      }
    };
    this.getUIContext().showAlertDialog(param);
  }

  private doRestore(text: string): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    BackupStore.restoreFromText(ctx, text).then((ok: boolean) => {
      if (!ok) {
        this.getUIContext().getPromptAction()
          .showToast({ message: $r('app.string.backup_invalid_toast'), duration: 2500 });
        return;
      }
      this.onRestored();
      this.getUIContext().getPromptAction()
        .showToast({ message: $r('app.string.backup_done_toast'), duration: 2500 });
    });
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // 家庭成员（M7）
        MemberManage({
          rows: this.rows,
          sectionLabel: this.sectionLabel,
          renameLabel: this.renameLabel,
          deleteLabel: this.deleteLabel,
          addLabel: this.addLabel,
          onPick: (id: string) => this.onPick(id),
          onRename: (id: string) => this.onRename(id),
          onDelete: (id: string) => this.onDelete(id),
          onAdd: () => this.onAdd()
        })

        // 备份与恢复（1.0.1 M6）：全量导出单文件 / 导入整体替换
        Column({ space: 12 }) {
          SectionLabel({ text: this.backupSectionLabel })
          Row({ space: 12 }) {
            GhostButton({
              label: this.backupExportLabel,
              icon: '📤',
              onTap: () => this.exportBackup()
            })
            .layoutWeight(1)
            .height($r('app.float.btn_height'))
            PrimaryButton({
              label: this.backupImportLabel,
              icon: '📥',
              onTap: () => this.pickRestoreFile()
            })
            .layoutWeight(1)
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 12 }) {
          SectionLabel({ text: this.displayLabel })
          InfoRow({
            label: this.strOf($r('app.string.settings_color_mode_label')),
            value: this.colorModeText()
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 12 }) {
          SectionLabel({ text: this.aboutLabel })
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
}
