# PreviewPage JsCrash 修复记录与待办

> 来源：应用市场测试报告（HarmonyOS 6.1，MateBook Pro / MatePad Pro 11 / Mate 60 三端复现）。
> 现象：进入预览页必现 JsCrash，堆栈 `at anonymous (entry|entry|1.0.0|src/main/ets/pages/PreviewPage.ts:814:49)`。

## 1. 根因（已定位，证据链完整）

- 本地模拟器（127.0.0.1:5555）故障日志两份，签名一致：
  - `jscrash-com.ddabb.mathsheet-…-20261030092407089.log`
  - `jscrash-com.ddabb.mathsheet-…-20261102083836118.log`
  - 均为 `TypeError: undefined is not callable`，触发路径 `Index.generate → pushUrl(PreviewPage) → Toolbar initialRender → actionsTrailing → this.strOf`（PreviewPage.ets:699）。
- Release 中间产物 `PreviewPage.ts:814:49` 精确对应 `label: this.strOf($r('app.string.change_batch'))`，与测试报告行号完全吻合。
- 根因：`PreviewPage.build()` 把 `@Builder` 方法以裸引用传给 `Toolbar` 的 `@BuilderParam`：

  ```ts
  Toolbar({
    leading: this.pageStatusLeading,   // ❌ builder 体内 this = 子组件 Toolbar
    trailing: this.actionsTrailing     // ❌ this.strOf / this.storedMode 均为 undefined
  })
  ```

  官方文档（@BuilderParam 的 this 指向）明确：传函数本身时 this 指向调用点组件（Toolbar）；
  箭头函数包裹时 this 指向定义处组件（PreviewPage）。
  `this.strOf` 在 Toolbar 实例上不存在 → `undefined is not callable` → 进预览页必崩。

## 2. 修复（已完成）

`entry/src/main/ets/pages/PreviewPage.ets:822`，按官方推荐写法改为箭头函数包裹：

```ts
Toolbar({
  leading: (): void => {
    this.pageStatusLeading();
  },
  trailing: (): void => {
    this.actionsTrailing();
  }
})
```

已验证：

| 项 | 结果 |
|---|---|
| arkts_check（PreviewPage.ets） | 通过 |
| debug 构建（product=default） | BUILD SUCCESSFUL |
| release 构建（product=release，含混淆） | BUILD SUCCESSFUL，中间产物 1150–1155 行确认箭头包裹生效 |
| 全库同类模式排查 | 仅此一处；Index 的 SectionCard 为尾随闭包写法（安全），其余页面无裸引用传 @Builder |

## 3. 待办与进展

| 编号 | 事项 | 前置条件 | 验收 | 状态 |
|---|---|---|---|---|
| T1 | 模拟器运行时验证：安装 debug 包 → 点「生成」进预览页 → 翻页/切套/换一批操作 | 模拟器空闲 | 进预览页不再崩溃；无新增 jscrash | ✅ 2026-11-02 通过（记录见 §3.1） |
| T2 | 用 release 产物（已重编含修复）重新提交应用市场测试 | T1 通过（已满足） | 三端不再复现 `PreviewPage.ts:814:49` 崩溃 | ⏳ 待执行（人工提交应用市场） |

### 3.1 T1 验证记录（2026-11-02）

- 设备：PhoneAgc 模拟器（设备号 20020063，即产生两份修复前基线 jscrash 的同一实例；原 `127.0.0.1:5555` 会话失效后经模拟器列表重新启动，前后对比有效）。
- 构建：debug / product=default，BUILD SUCCESSFUL（本轮重编后安装 `entry-default-signed.hap`）。
- 用例（自动化 UI 走查，校验 ID `2c8a242f-0f28-4034-920c-e125ef3ae699`）：
  首页「⚙️ 高级」选「2套」→「✨ 生成题卡」进预览页（不崩溃，页码 1/4 正常）→
  向左甩动翻页 → 顶栏切「B」套 → 切回「A」套 →「🔄 换一批」→「‹ 返回」回首页，全程无崩溃无闪退。
- jscrash 复核：`hdc shell ls /data/log/faultlog/faultlogger/` 过滤本包名，仅存两份修复前基线
  （`jscrash-com.ddabb.mathsheet-20020063-20261030092407089.log`、
  `jscrash-com.ddabb.mathsheet-20020063-20261102083836118.log`），
  验证多次进出预览页后**无新增文件**。
- 补充证据：本轮共 3 次自动化验证，其中 2 次成功进入预览页（修复前该路径必现崩溃），0 次复现；
  另 1 次未进入预览页（表单滚动定位失败，属 UI 操作问题，非应用故障）。
- 结论：**T1 通过**。剩余 T2 为人工动作（用已含修复的 release 产物重新提交应用市场测试）。

## 4. 备注

- 测试报告堆栈中的 `entry|entry|1.0.0` 为模块名/包名/oh-package 版本（entry/oh-package.json5 恒为 1.0.0），非应用版本号；本次崩溃对应 v1.1.0 候选包。
- 模拟器上如需复核，故障日志取法：`hdc shell faultlogger` 目录下按包名过滤 `jscrash-com.ddabb.mathsheet-*`，以时间戳区分修复前后。
