/**
 * ohosTest 套件注册表——运行协议：
 *  - 模拟器 class 过滤定向跑纯逻辑套件（勿全量跑）：
 *      hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *        -s class mathCoreTest -s timeout 15000
 *      （M2 套件：-s class sheetM2Test）
 *      （M3/M4 套件：-s class sheetM34Test -s timeout 30000）
 *      （M5 性能套件：-s class perfTest -s timeout 60000）
 *      （M7 成员套件：-s class memberTest -s timeout 30000）
 *  - 纯逻辑套件先行（hypium 直测，不依赖 ability context）；
 *  - sheetM34Test 含 Context I/O（SheetStore/MistakeStore）与 PDF 合成（async 用例）；
 *  - perfTest 为 §6.5 预算复核（模拟器口径），计时均值断言 + console.info 落数；
 *  - memberTest 为 M7 成员档案（ProfileStore 生命周期/存量迁移/成员隔离，async 用例）。
 */
import abilityTest from './Ability.test';
import mathCoreTest from './MathCore.test';
import sheetM2Test from './SheetM2.test';
import sheetM34Test from './SheetM34.test';
import perfTest from './Perf.test';
import memberTest from './Member.test';

export default function testsuite() {
  abilityTest();
  mathCoreTest();
  sheetM2Test();
  sheetM34Test();
  perfTest();
  memberTest();
}
