/**
 * ohosTest 套件注册表（M0 脚手架）——运行协议：
 *  - 模拟器 class 过滤定向跑纯逻辑套件：
 *      hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *        -s class ActsAbilityTest -s timeout 15000
 *  - 纯逻辑套件先行（hypium 直测，不依赖 ability context）；
 *  - 各计划的核心套件（mathCoreTest / pixelCoreTest / mdCoreTest）随 M0+ 批次注册进本表。
 */
import abilityTest from './Ability.test';

export default function testsuite() {
  abilityTest();
}
