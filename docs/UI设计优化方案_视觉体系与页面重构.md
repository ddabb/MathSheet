# 出题本 · UI 设计优化方案：视觉体系与页面重构（v1.1.0 提案）

> 现状：应用已上架（显示名「出题本」，内部代号 MathSheet，v1.0.0 立项并发布）。功能链路完整（生成 / 卷库 / 错题 / 答题 / 批改 / 预览导出），但上线后 UI 被评价"丑"。本文先出设计文档，不动代码；落地阶段再按 §8 清单逐项改造。
> 约束红线：离线、买断、零网络权限不变；深色模式跟随系统必须保留；不引入第三方 UI 库（保持纯 ArkUI + 现有 color/string 资源体系）。

## 1. 现状诊断（来自实代码走查）

| 编号 | 问题 | 代码证据 | 观感影响 |
|---|---|---|---|
| D1 | 配色是"系统默认蓝灰"，无识别度 | `color.json`：brand `#2E6FD6`、accent `#F59E0B`、page_bg `#F5F5F5`、card `#FFFFFF`；success `#15803D`（偏暗绿） | 像未打磨的模板，与"专业教育工具"定位不符 |
| D2 | 全局零图标，纯文字 | Index/HeroCard/UiKit 所有控件皆 `Text`；Segmented、Chip、TabBar 无任何图标 | 信息密度低、层级靠字号硬撑，显廉价 |
| D3 | 生成页是一张"长列表卡"，靠细 Divider 分段 | `Index.ets` 593-698：年级/题型/难度/题数/列数/高级全部塞进同一个 `Column` + `Divider` | 一屏信息过载、无呼吸感、无分组 |
| D4 | 选型控件两套管子 | 题型 chips 在 `Index.ets` 603-617 内联手写，与 `UiKit.OptionChip` 重复且细节不一 | 同类控件两套样式，割裂 |
| D5 | 底部操作条是"文字药丸"拼凑 | `PreviewPage.ets` 723-752：换一批/存图/导出 PDF 三个 `Text` 药丸并排 | 主次不分，导出主操作被淹没 |
| D6 | 空态只有文字，无插画 | `UiKit.EmptyState` 纯标题+说明+按钮 | 卷库/错题空态冷清，无引导感 |
| D7 | 品牌行光秃秃 | `Index.ets` 559-571：仅 `app_name` 22px 粗体 + 极小离线标签 | 首页缺视觉锚点（logo/渐变/插画） |
| D8 | 没有阴影/层级体系 | 全站仅 `borderColor` 描边，无 `shadow`/`elevation` | 卡片浮不起来，扁平显旧 |
| D9 | 间距魔法数字满天飞 | 各处 `.padding(16)`/`.space(12)`/`.space(14)`/字号 13/14/22 散落 | 缺乏节奏，难统一维护 |

## 2. 设计目标与原则

1. **从"能用的工具"到"想用的工具"**：第一眼专业、亲和、有教育温度。
2. **一套 Token 管到底**：颜色 / 间距 / 圆角 / 字号 / 阴影全部资源化，杜绝魔法数字。
3. **图标即层级**：用鸿蒙内置 `SymbolGlyph`（零资源成本、风格统一）替代纯文字控件。
4. **分组而非罗列**：生成页拆成「年级 / 题型 / 难度 / 题量 / 高级」五张 SectionCard，每张带图标标题。
5. **主次分明**：主操作（生成 / 导出）实心品牌色大按钮；次要操作（换一批 / 存图）幽灵按钮。

## 3. 设计 Token 体系（重写 `color.json` + 新增 `float.json` 阴影）

### 3.1 配色（建议值，保留语义名便于最小改动）

| Token | 旧值 | 新值 | 说明 |
|---|---|---|---|
| `brand` | `#2E6FD6` | `#3A63E0` | 更通透的靛蓝，去灰感 |
| `brand_tint` | `#1A2E6FD6` | `#1A3A63E0` | 跟随新 brand |
| `accent` | `#F59E0B` | `#FF9F2E` | 暖琥珀，活力 |
| `success_green` | `#15803D` | `#1FA971` | 明快绿，对/正确反馈 |
| `danger_red` | `#DC2626` | `#E5484D` | 柔和红，错题/答案页 |
| `page_background` | `#F5F5F5` | `#F6F7FB` | 冷调浅灰，更干净 |
| `card_background` | `#FFFFFF` | `#FFFFFF` | 不变 |
| `primary_text` | `#333333` | `#1A1D29` | 近黑不刺眼 |
| `secondary_text` | `#666666` | `#5B6172` | 次级 |
| `hint_text` | `#999999` | `#9AA0AE` | 弱化 |
| `border_color` | `#EEEEEE` | `#ECEEF3` | 更淡描边 |
| `chip_bg` | `#F2F2F2` | `#EFF1F6` | 控件底 |

> 不换主色相（仍是蓝），避免与已上架品牌、商店素材、图标脱节；重点在"提纯度 + 配套语义色 + 层级"，解决"丑"而非"换皮"。

### 3.2 间距 / 圆角 / 字号 / 阴影（新增 `float.json` 与约定）

- **间距轴**：`xs=4 md=8 sm=12 lg=16 xl=20 xxl=24`（页面边距统一 `lg=16`，卡内 `lg=16`，组间距 `xl=20`）。
- **圆角轴**：`sm=8 md=12 lg=16 xl=20 pill=999`（卡片 `lg`，芯片 `pill`，按钮 `xl/pill`）。
- **字号轴**：`caption=11 label=13 body=14 title=17 headline=20 brand=22`。
- **阴影**：`card_elevation`（y=2, blur=8, color `#1A1A1D29`）；`cta_elevation`（y=4, blur=12）；深色模式下阴影降透明度。

## 4. 组件库升级（扩 `UiKit.ets`）

| 组件 | 现状 | 目标 |
|---|---|---|
| `SectionCard` | 无（页面内联 `Column+Divider`） | 新增：图标 + 标题 + 内容槽，统一卡片容器，自带 `lg` 圆角 + `card_elevation` |
| `OptionChip` / `Segmented` | 纯文字 | 增加可选 `icon` 参数，题型/年级等带 `SymbolGlyph` |
| `PrimaryButton` / `GhostButton` | 各处手写 `Button` | 新增统一主/次按钮 builder，固定高度 48、圆角 `xl` |
| `Toolbar` | 预览页文字药丸 | 新增底部工具条：左侧状态、右侧主+次操作，主次分明 |
| `EmptyState` | 纯文字 | 增加 `illustration` 槽（用 `SymbolGlyph` 大图标或 SVG 插画占位） |
| `BrandHeader` | 光秃秃文字行 | 新增：app 图标 + 名称 + 离线标签 + 可选渐变/插画，作为首页视觉锚 |

## 5. 逐页重构方案

### 5.1 首页 / 生成页（Index.ets）
- 顶部 `BrandHeader`（图标 + 「出题本」+ 离线徽标），替代现有裸文字行。
- `HeroCard` 保留品牌色卡，文案与按钮微调，加图标。
- 表单拆为 5 张 `SectionCard`：①年级（Segmented+图标）②题型（带图标多选 Chip）③难度（Segmented）④题量·列数（Chip 组）⑤高级（Toggle 组）。每张卡带图标标题，卡间 `xl` 间距。
- 题型 Chip 统一改用 `UiKit.OptionChip`（消除 D4 双套）。
- 底部固定主按钮 `PrimaryButton`（生成题卡），高度 48、圆角 `xl`、带 `cta_elevation`。

### 5.2 卷库页 / 错题本页（LibraryWidgets / MistakesPanel）
- 列表项改为「缩略图（小预览图）+ 标题 + 元信息（年级/日期/批改进度）+ 状态徽标（待批改/已批改/打卡）」卡片。
- 空态接入 `EmptyState` 插画槽（D6）。
- 操作（打开/批改/答题/删除）统一为卡片内图标按钮，非整段文字。

### 5.3 设置页（Index.ets SettingsTab）
- 现有分组卡结构保留，应用 Token（间距/圆角/字号），信息行加首尾图标。
- 成员管理行增加头像色块（首字母/emoji），弱化"管理后台"感。

### 5.4 预览页（PreviewPage.ets）
- 顶栏保留返回/标题/答案红徽标/套切换，标题加图标。
- 底部操作条改用 `Toolbar`：左侧页码状态，右侧「换一批」(Ghost) +「存图」(Ghost) +「导出 PDF」(Primary)，主次清晰（解决 D5）。
- 导出遮罩保留，改圆角与配色一致。

### 5.5 答题页 / 批改页（QuizPage.ets / GradePage.ets）
- 数字键盘加大点按区、主色描边；对错反馈用 `success_green` / `danger_red` 强化（即时判分闪绿、错停红）。
- 批改速录：题卡状态用色块而非纯文字。

## 6. 视觉识别（轻量，不换图标也行）
- **App 图标**：维持现有 `app_icon.png`，若重做建议圆角卡片 + 算式/铅笔符号，与品牌蓝一致。
- **空态插画 / Hero 背景**：优先用 `SymbolGlyph` 大图标（零资源）；后续可补 2-3 张 SVG 教育插画（算式、奖杯、铅笔）。
- **字体**：保持系统默认，靠字重（Bold/Normal）与字号轴拉层级，不引入自定义字体（合规与体积）。

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| 改 `color.json` 影响已上架素材/图标色 | 主色相不变，仅提纯；商店截图如需同步再另排期 |
| 深色模式回退 | 所有新 Token 在 `dark` 资源目录补齐（page_bg/卡片反相、阴影降透明），纳入回归 |
| SymbolGlyph 设备兼容 | 真机回归；个别图标缺失时回退文字标签 |
| 重构范围失控 | §8 清单按页拆分，每张卡独立 PR，先首页后内页 |

## 8. 实施清单（落地阶段，本文不执行）

| 文件 | 改动 |
|---|---|
| `entry/.../base/element/color.json` | 按 §3.1 提纯配色 |
| `entry/.../base/element/float.json`（新增） | 阴影/圆角/间距 Token |
| `components/UiKit.ets` | 新增 `SectionCard` / `PrimaryButton` / `GhostButton` / `Toolbar` / `BrandHeader`（扩展 `OptionChip`/`Segmented`/`EmptyState` 带图标） |
| `components/HeroCard.ets` | 接入图标与 Token |
| `pages/Index.ets` | 首页 `BrandHeader` + 五张 `SectionCard` + 统一主按钮；设置页 Token 化 |
| `components/LibraryWidgets.ets` / `MistakesPanel` | 列表卡片 + 空态插画 |
| `pages/PreviewPage.ets` | `Toolbar` 重构底部操作条 |
| `pages/QuizPage.ets` / `GradePage.ets` | 键盘与反馈色强化 |
| `resources/base` + `dark` 目录 | 深色模式 Token 补齐 |

## 9. 验收

- 全站零魔法数字（间距/圆角/字号/颜色全部走 Token）
- 首页分组清晰、主次分明，首屏有品牌锚点
- 预览页导出主操作突出，操作条一致
- 深色模式全页正常，无纯黑/纯白刺眼
- 离线、买断、零网络权限声明不变
