import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

let abilityDelegator: abilityDelegatorRegistry.AbilityDelegator | undefined = undefined;
let abilityDelegatorArguments: abilityDelegatorRegistry.AbilityDelegatorArgs | undefined = undefined;

async function onAbilityCreateCallback(data: UIAbility): Promise<void> {
  hilog.info(0x0000, 'testTag', 'onAbilityCreateCallback, data: %{public}s', JSON.stringify(data));
}

async function addAbilityMonitorCallback(err: BusinessError): Promise<void> {
  hilog.info(0x0000, 'testTag', 'addAbilityMonitorCallback : %{public}s', JSON.stringify(err));
}

export default class OpenHarmonyTestRunner implements TestRunner {
  constructor() {
  }

  onPrepare(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'OpenHarmonyTestRunner OnPrepare');
  }

  async onRun(): Promise<void> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'OpenHarmonyTestRunner onRun run');
    abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
    abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
    Hypium.hypiumTest(abilityDelegator, abilityDelegatorArguments, testsuite);
    hilog.info(0x0000, 'testTag', '%{public}s', 'OpenHarmonyTestRunner onRun end');
  }
}
