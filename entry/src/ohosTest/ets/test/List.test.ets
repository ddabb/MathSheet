/**
 * ohosTest 套件注册表——运行协议：
 *  - 模拟器 class 过滤定向跑纯逻辑套件（勿全量跑）：
 *      hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *        -s class mathCoreTest -s timeout 15000
 *      （M2 套件：-s class sheetM2Test）
 *  - 纯逻辑套件先行（hypium 直测，不依赖 ability context）；
 *  - 后续批次：PdfCodec 字节校验 / 卷库存储等套件随批注册。
 */
import abilityTest from './Ability.test';
import mathCoreTest from './MathCore.test';
import sheetM2Test from './SheetM2.test';

export default function testsuite() {
  abilityTest();
  mathCoreTest();
  sheetM2Test();
}
