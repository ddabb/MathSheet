/**
 * ohosTest 套件注册表——运行协议：
 *  - 模拟器 class 过滤定向跑纯逻辑套件（勿全量跑）：
 *      hdc shell aa test -b com.ddabb.mathsheet -m entry_test -s unittest OpenHarmonyTestRunner
 *        -s class mathCoreTest -s timeout 15000
 *      （M2 套件：-s class sheetM2Test）
 *      （M3/M4 套件：-s class sheetM34Test -s timeout 30000）
 *      （M5 性能套件：-s class perfTest -s timeout 60000）
 *      （M7 成员套件：-s class memberTest -s timeout 30000）
 *      （1.0.1 M8 套件：-s class g45Test -s timeout 30000）
 *  - 纯逻辑套件先行（hypium 直测，不依赖 ability context）；
 *  - sheetM34Test 含 Context I/O（SheetStore/MistakeStore）与 PDF 合成（async 用例）；
 *  - perfTest 为 §6.5 预算复核（模拟器口径），计时均值断言 + console.info 落数；
 *  - memberTest 为 M7 成员档案（ProfileStore 生命周期/存量迁移/成员隔离，async 用例）；
 *  - g45Test 为 1.0.1 M8 四五年级（小数/竖式/简便运算 + M7 边界回归，纯逻辑直测）；
 *  - drillTest 为 1.0.1 M1 错题重练（模式/比例钳制/来源日期/物化入库，末用例真 Context I/O）；
 *  - backupTest 为 1.0.1 M6 备份恢复（全量回环/损坏拒绝/残留清理，真 Context I/O）；
 *  - figTest 为 v1.1 §17.3 数形结合（看图列式/点阵乘法/数轴填空/面积模型拆分/小数数轴/小数面积模型：结构/判分回环/宽度预算/渲染冒烟）。
 */
import abilityTest from './Ability.test';
import mathCoreTest from './MathCore.test';
import sheetM2Test from './SheetM2.test';
import sheetM34Test from './SheetM34.test';
import perfTest from './Perf.test';
import memberTest from './Member.test';
import g45Test from './G45.test';
import drillTest from './Drill.test';
import backupTest from './Backup.test';
import figTest from './Fig.test';

export default function testsuite() {
  abilityTest();
  mathCoreTest();
  sheetM2Test();
  sheetM34Test();
  perfTest();
  memberTest();
  g45Test();
  drillTest();
  backupTest();
  figTest();
}
