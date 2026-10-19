import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class TestAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onWindowStageCreate');
    windowStage.loadContent('test/pages/Index', (err, data) => {
      hilog.info(0x0000, 'testTag', 'loadContent: err=%{public}s data=%{public}s', JSON.stringify(err) ?? '', JSON.stringify(data) ?? '');
    });
  }
}
