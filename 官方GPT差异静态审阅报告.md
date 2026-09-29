# 官方 GPT / Codex 客户端差异静态审阅报告

> 审阅范围：仅基于当前仓库源码、README、路线图和 Composer 一致性基线进行静态分析。
>
> 结论等级：
>
> - **已确认**：代码直接体现出的产品、UI 或功能差异。
> - **高概率差异**：从实现结构可以判断与官方客户端产品边界不同，但仍建议运行时复核。
> - **待实测**：静态代码无法证明，需要与官方桌面客户端进行行为或截图对照。

## 一、总体结论

当前项目不是官方 ChatGPT 客户端的直接复刻，而是一个以 Codex 为核心、加入本地开发工作台能力的独立桌面应用。它已经实现了较多 Codex App Server 和 Composer 能力，但在以下方面与官方 GPT / Codex 客户端存在明显差异：

1. 品牌、应用身份和产品命名不同。
2. 工作台范围明显扩大，加入了 Git、浏览器、插件、MCP、Worktrees、定时任务、Pull Request、Subagents 等开发工具能力。
3. 设置页仍有大量可见但禁用或“待开发”的入口。
4. 部分已实现能力与设置页文案不同步。
5. 真实 IDE 插件、语音、电脑操控、应用快照等能力并未完整实现。
6. Composer 的核心协议能力较完整，但菜单排序、像素级视觉和部分桌面交互仍未完成官方实测。

## 二、已确认的 UI / 产品身份差异

### 1. 应用身份不是官方 ChatGPT

- Flutter 应用标题为 `Codex Desk`。
- 侧栏和窗口状态使用 `Xedoc` 品牌。
- 代码中不存在官方 ChatGPT 客户端的完整品牌身份和产品命名。

证据：

- [`lib/src/app_codex_desk_app_view_state.dart:52`](<lib/src/app_codex_desk_app_view_state.dart:52>)
- [`README.md:54`](<README.md:54>)
- [`README.md:79`](<README.md:79>)

判断：**已确认差异**。如果目标是官方 ChatGPT，属于最明显的产品层偏离；如果目标是 Codex 替代客户端，则属于主动品牌选择。

### 2. 使用自定义主题系统

应用使用 `YeknomWorkbenchTheme`、`YeknomPalette` 和自定义颜色 preset，而不是直接复用官方客户端的主题 token。

证据：

- [`lib/src/app_codex_desk_app_view_state.dart:55`](<lib/src/app_codex_desk_app_view_state.dart:55>)
- [`lib/src/app_codex_desk_app_view_state.dart:55`](<lib/src/app_codex_desk_app_view_state.dart:55>)

判断：**已确认存在视觉差异**。仅凭代码不能确定每个颜色、圆角和间距具体偏差多大。

### 3. 自定义“开发工作台”布局

界面不是单一聊天窗口，而是由以下区域组成：

- 项目树和多项目导航
- 会话时间线
- Composer
- 右侧环境信息面板
- 代码审查工作区
- 内置浏览器
- 文件浏览器和文件 Tab
- 子智能体 Tab
- Git / Diff / Pull Request 工作区

证据：

- [`lib/src/presentation/workspace/codex_workspace_state.dart:2715`](<lib/src/presentation/workspace/codex_workspace_state.dart:2715>)
- [`README.md:136`](<README.md:136>)
- [`README.md:161`](<README.md:161>)

判断：**已确认是产品结构差异**。这更像 Codex IDE 工作台，而不是普通 ChatGPT 对话客户端。

## 三、已确认的额外功能差异

### 1. 内置浏览器

代码实现了带多 Tab、地址栏、前进后退、刷新、弹出窗口处理和 Chrome 导入边界的浏览器工作区。

证据：

- [`lib/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart:564`](<lib/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart:564>)
- [`lib/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart:541`](<lib/src/presentation/browser/codex_workspace_browser_workspace_page_state.dart:541>)

判断：**高概率差异**。它属于开发工作台能力，不是普通 ChatGPT 主聊天界面的标准组成部分。

### 2. Git、Diff、提交、推送和 Pull Request

代码提供：

- Git 分支切换和创建
- 暂存与还原文件
- Diff 浏览
- 提交和推送
- 通过本机 GitHub CLI 创建 Pull Request

证据：

- [`README.md:161`](<README.md:161>)
- [`lib/src/presentation/code_review/code_review_panel_code_review_panel_state.dart`](<lib/src/presentation/code_review/code_review_panel_code_review_panel_state.dart>)

判断：**已确认属于开发工具扩展**，不能视为官方 ChatGPT 的通用聊天功能。

### 3. 插件、MCP 和 Skills 管理

插件页、MCP 服务器、技能库、marketplace 和安装/卸载流程均有独立 UI。

证据：

- [`README.md:136`](<README.md:136>)
- [`README.md:159`](<README.md:159>)
- [`lib/src/presentation/extensions/`](<lib/src/presentation/extensions/>)

判断：**已确认属于 Codex 开发环境扩展**。

### 4. 本地定时任务

应用提供“已安排”工作区，可以保存提示词和执行时间，到点后创建任务并发送。

证据：

- [`lib/src/presentation/workspace/codex_workspace_state.dart:2359`](<lib/src/presentation/workspace/codex_workspace_state.dart:2359>)
- [`lib/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_page_state.dart:65`](<lib/src/presentation/extensions/codex_workspace_extensions_scheduled_tasks_page_state.dart:65>)

判断：**已确认是额外产品能力**。其本地运行时约束也不同于云端 ChatGPT 任务体系。

### 5. 子智能体工作区

代码将子智能体作为右侧工作区 Tab、实时活动、完成记录和只读检查器来展示。

证据：

- [`lib/src/presentation/workspace/codex_workspace_state.dart:2852`](<lib/src/presentation/workspace/codex_workspace_state.dart:2852>)
- [`lib/src/presentation/conversation/codex_workspace_conversation_subagent_thread_panel.dart`](<lib/src/presentation/conversation/codex_workspace_conversation_subagent_thread_panel.dart>)

判断：**高概率差异**。这是 Codex 多智能体工作流的产品化表现，不是普通 GPT 聊天的标准信息架构。

## 四、已确认的半成品或入口状态问题

### 1. 多个设置入口可见但不可用

以下设置项明确标记为“待开发”并禁用：

- 默认文件打开位置
- 菜单栏显示
- 底部面板
- 默认终端位置
- 防止系统休眠
- 提示词建议
- 指针光标
- 减少动态效果
- UI 字号
- 代码字体大小
- 差异标记
- 字体平滑

证据：

- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:620`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:620>)
- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:649`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:649>)
- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:767`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:767>)
- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:802`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:802>)

判断：**已确认的完成度差异**。官方成熟客户端一般不会把大量未实现设置暴露在主导航中，除非明确采用实验功能或灰度标记。

### 2. 设置导航存在重复入口

设置页同时存在：

- `Worktrees`
- `Worktrees（待开发）`

证据：

- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1842`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1842>)
- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1867`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1867>)

判断：**已确认的 UI 信息架构问题**，容易让用户误以为存在两个不同的 Worktrees 功能。

### 3. 已实现功能仍显示“待开发”

README 描述已经支持本地历史导入/导出，但设置导航中的“导入”仍显示“待开发”。

证据：

- [`README.md:128`](<README.md:128>)
- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1781`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1781>)

判断：**已确认的文案与实际能力不同步**。

### 4. 录制技能入口可见但始终禁用

Composer 中保留“录制技能”入口，但当前 App Server 没有公开录制协议，因此点击不会启动录制流程。

证据：

- [`lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:682`](<lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:682>)
- [`lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:778`](<lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:778>)

判断：**已确认是可见但不可用的功能入口**。

## 五、能力缺失或边界不同

### 1. 没有真正的 IDE 插件端

仓库只实现通用的 `codex_desk/ide_context` 宿主协议，可接收当前文件、选区和打开标签；仓库不包含 VS Code、Xcode 等具体插件。

证据：

- [`CODEX_COMPOSER_PARITY_BASELINE.md:25`](<CODEX_COMPOSER_PARITY_BASELINE.md:25>)
- [`CODEX_COMPOSER_PARITY_FOLLOWUP.md:31`](<CODEX_COMPOSER_PARITY_FOLLOWUP.md:31>)

判断：**已确认能力边界**。独立运行时 IDE 上下文入口会保持禁用。

### 2. 语音、电脑操控和应用快照未完成

设置中存在这些入口，但均标记为待开发：

- 语音
- 电脑操控
- 应用快照

证据：

- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1791`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1791>)
- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1822`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1822>)
- [`lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1826`](<lib/src/presentation/settings/codex_workspace_settings_page_state.dart:1826>)

判断：**已确认缺失或未完成**。

### 3. 本地优先数据模型与官方云端会话不同

应用使用本地加密历史缓存、项目级任务边界、图片附件持久化和可导出的明文 JSON。导出的 JSON 不包含 App Server 原始 session，也不会恢复远端会话。

证据：

- [`README.md:128`](<README.md:128>)
- [`README.md:235`](<README.md:235>)
- [`README.md:254`](<README.md:254>)
- [`lib/src/app_controller_codex_controller_runtime.dart:4934`](<lib/src/app_controller_codex_controller_runtime.dart:4934>)

判断：**已确认的数据边界差异**。这不是单纯 UI 差异，会影响同步、恢复、隐私和跨设备行为。

## 六、Composer：已经接近，但仍不能宣称完全一致

当前代码已经实现或接入：

- `/plan`
- Goal
- `@` 文件和目录搜索
- Skills
- MCP 状态
- Code Review
- 侧边聊天
- Chat fork
- 压缩
- 反馈
- 模型和推理强度

证据：

- [`CODEX_COMPOSER_PARITY_BASELINE.md:21`](<CODEX_COMPOSER_PARITY_BASELINE.md:21>)
- [`lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:757`](<lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:757>)

但以下项目仍不能仅通过代码确认与官方完全一致：

- `/` 菜单的完整顺序、分组和隐藏条件
- `@` 菜单的完整排序和视觉分组
- 鼠标悬停、方向键、Enter、Tab、Esc 的每个边界行为
- 输入法组合态下的焦点和提交细节
- 窄窗口和极限窗口的布局
- 菜单的圆角、行高、阴影、字体和间距
- 任务文件按当前 turn、整个 thread 还是 Git 工作区展示

证据：

- [`CODEX_COMPOSER_PARITY_BASELINE.md:17`](<CODEX_COMPOSER_PARITY_BASELINE.md:17>)
- [`CODEX_COMPOSER_PARITY_BASELINE.md:19`](<CODEX_COMPOSER_PARITY_BASELINE.md:19>)
- [`CODEX_COMPOSER_PARITY_FOLLOWUP.md:8`](<CODEX_COMPOSER_PARITY_FOLLOWUP.md:8>)

判断：**协议层较接近，桌面视觉和精确交互仍待实测**。

## 七、建议的逐项分析顺序

建议后续按以下顺序逐项分析，优先处理用户最容易感知的问题：

1. **品牌和主布局**：`Codex Desk / Xedoc`、左侧项目树、右侧工作区是否要保留。
2. **设置页入口**：删除、隐藏或实现全部“待开发”项目；先解决重复 Worktrees。
3. **Composer 菜单**：核对 `/`、`@`、添加菜单的官方顺序、文案和禁用逻辑。
4. **会话时间线**：核对消息气泡、工具活动、计划、审批、完成状态和滚动行为。
5. **任务文件与 Diff**：用真实官方客户端验证跨轮展示范围和撤销语义。
6. **额外工作台**：确认浏览器、Git、插件、MCP、定时任务和子智能体是否属于产品目标，还是应从“官方 GPT 兼容模式”中移除。
7. **账户、语音和 IDE**：明确是补齐官方能力，还是保持 Codex Desk 的差异化边界。
8. **像素级视觉验收**：最后再固定浅色、深色、窄窗口和边界尺寸截图对比。

## 八、当前不能下结论的事项

静态代码无法可靠证明以下内容：

- 与官方客户端的像素级相似度。
- 官方客户端当前版本的实际菜单隐藏条件。
- macOS 标题栏、窗口按钮、Dock、焦点和多窗口行为是否完全一致。
- App Server 实际运行时返回事件是否覆盖所有协议分支。
- 官方客户端对任务文件的最终范围定义。

这些内容应通过固定版本的官方桌面客户端进行行为矩阵和截图回归，而不能仅凭 Flutter 代码推断。

## 九、专项分析：Composer 菜单

### 已修复：运行时菜单英文 slash 别名与提交解析不一致

此前版本的静态审阅曾将此项列为 P0。当前实现已为运行时命令目录补齐 canonical 英文别名，并由菜单筛选与提交路径共同使用；`/plan`、`/mcp`、`/review`、`/compact`、`/feedback`、`/archive`、`/model`、`/reasoning`、`/new` 等路径已有专项测试覆盖。该项不再是当前缺陷，但官方完整命令集合和排序仍待实测。

### 已修复：`/` 和 `@` 的触发范围过窄

此前版本只支持 Composer 文本起始位置。当前实现按光标所在 token 计算触发范围，支持句首、空白后和消息中间的有效 token，并只替换当前 token；无效范围、换行边界和键盘选择已有专项测试。是否与官方在标点、输入法组合态等细节完全一致，仍待实测。

### P1：禁用项仍参与可见菜单，官方隐藏/禁用策略尚未对齐

`IDE 上下文`、运行中的`计划模式`、`录制技能`等会以禁用行显示；键盘选择会跳过禁用项，但鼠标和视觉上仍能看到它们。

证据：

- [`lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:352`](<lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:352>)
- [`lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:480`](<lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:480>)
- [`lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:1691`](<lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart:1691>)

修复建议：

- 先通过官方客户端行为矩阵确定每一项是“隐藏”还是“显示但禁用”。
- 将 `visibility` 与 `enabled` 分开建模，避免所有不可用能力都被渲染成灰色菜单行。
- 无 IDE 宿主时建议隐藏 IDE 上下文；录制技能无协议时建议隐藏，而不是让用户尝试一个永远无效的入口。

### 已部分修复：`/`、`@` 和“添加”菜单的动作元数据已共享

此前版本存在三套独立定义。当前实现已抽取共享的 `ComposerSlashCommand` 命令描述，`/`、`@` 和“添加”菜单复用文件、工作区上下文、目标、计划模式和技能录制等核心元数据；选择、禁用和键盘导航也已统一测试。仍需官方矩阵确认完整入口集合、顺序和隐藏条件，后续若发现动作集合继续分叉，再扩展为完整的不可变 action catalog。

### P2：精确顺序和视觉仍不能宣称与官方一致

代码当前顺序是自定义顺序，例如 `/` 菜单先放 IDE 上下文和 MCP，再放代码审查、目标、计划、侧边、分支、压缩等；`@` 菜单则混合“添加”、文件搜索和插件。

官方完整顺序、分组、图标和隐藏条件仍属于仓库标记的“待实测”范围。

修复建议：

- 固定官方版本，逐项记录 `/`、`@`、`+` 在新聊天、历史聊天、运行中、审查模式、侧边聊天和离线状态下的菜单矩阵。
- 以矩阵驱动测试和菜单目录，不要只依赖 golden screenshot。

## 十、专项分析：会话时间线

### P1：时间线条目被多层折叠，需确认是否符合官方信息层级

当前实现有三层折叠：

- 连续工具/命令活动折叠为 `TimelineActivityList`。
- 已完成回合折叠为 `CompletedTurnDisclosure`。
- 连续耗时回合折叠为 `ElapsedTurnGroup`。

完成回合中，最终答案、审批和错误会被移到折叠区域之外，其他过程条目默认放入可展开区域。

证据：

- [`lib/src/presentation/timeline/codex_workspace_timeline_completed_turn_disclosure_state.dart:29`](<lib/src/presentation/timeline/codex_workspace_timeline_completed_turn_disclosure_state.dart:29>)
- [`lib/src/presentation/timeline/codex_workspace_timeline_timeline_activity_list.dart:7`](<lib/src/presentation/timeline/codex_workspace_timeline_timeline_activity_list.dart:7>)
- [`lib/src/presentation/conversation/codex_workspace_conversation_conversation_timeline.dart:385`](<lib/src/presentation/conversation/codex_workspace_conversation_conversation_timeline.dart:385>)

风险：

- 过程说明、命令、工具调用、计划和最终答案的层级可能与官方不同。
- 用户可能需要多次点击才能看到工具错误或审批上下文。
- 同一条回合在“运行中”和“完成后”有不同折叠层级，容易产生布局跳动。

修复建议：

- 用官方截图和真实事件序列确认：最终答案是否始终可见、审批/错误是否始终置顶、命令活动是否按回合或连续区间折叠。
- 为每一种事件序列建立 golden + widget test：纯回复、回复+命令、多个命令、审批、错误、Plan、Subagent、最终答案补发。
- 将“信息可见性策略”从 Widget 中抽成纯函数，避免依赖 UI 分支隐式决定折叠行为。

### 已修复：异步条目数量变化时的时间线索引越界

此前版本在 `itemBuilder` 中直接依赖实时列表长度。当前实现使用不可变渲染快照，并在实时活动、协作活动和文件摘要同帧变化时安全降级；相关时间线和完成状态测试已通过。

### 已修复边界：审批、用户输入和 Plan 实施卡的 thread/turn 归属

卡片仍以 Composer 底部浮动区域呈现，这一点是否与官方信息架构一致仍待实测；但当前实现已将审批、MCP elicitation、结构化用户输入和 Plan 实施请求绑定到明确的 thread/turn。旧 turn 请求在同一线程切换后隐藏，后台线程请求保留并显示任务归属，专项测试已覆盖。

### P2：滚动策略复杂，但缺少官方行为证据

当前实现使用 `extentAfter <= 48` 判断是否跟随底部，显式回到底部时约 260ms 动画，部分布局变化使用 `jumpTo`。

证据：

- [`lib/src/presentation/workspace/codex_workspace_state.dart:572`](<lib/src/presentation/workspace/codex_workspace_state.dart:572>)
- [`lib/src/presentation/workspace/codex_workspace_state.dart:641`](<lib/src/presentation/workspace/codex_workspace_state.dart:641>)
- [`lib/src/presentation/conversation/codex_workspace_conversation_conversation_viewport_state.dart:101`](<lib/src/presentation/conversation/codex_workspace_conversation_conversation_viewport_state.dart:101>)

修复建议：

- 记录官方的跟随阈值、完成提示出现条件、用户上滑后的恢复条件和窗口 resize 行为。
- 将滚动状态拆成 `followingLatest`、`userDetached`、`historyRestoring`、`programmaticReveal` 四种明确状态。
- 增加长 Markdown、活动展开、Plan 浮层高度变化和窗口缩放测试。

## 十一、专项分析：任务文件与 Diff

### 已修复：恢复历史时跨轮文件摘要丢失

此前版本在遍历每个 turn 时重复清空文件状态。当前实现将 thread 累计文件摘要与当前 turn Diff 分开维护，恢复时按 thread 合并多轮文件，并保留最近一次可撤销的 turn Diff；跨轮恢复、重启和删除清理已有回归测试。

### 已修复：thread 级文件摘要与 turn 级 Diff 混用

当前 UI 和控制器已拆分累计文件摘要、当前 turn Diff、统计范围和撤销资格。卡片展示累计文件集合，撤销只针对当前 turn 的完整 Diff；当累计集合超出当前 Diff 覆盖范围、Diff 被截断或任务仍在运行时，撤销保持禁用。

本轮进一步统一了可见统计：Composer、会话时间线和右侧环境信息的文件列表/数量仍表示 thread 累计文件集合，但 `+新增/-删除` 行数只从当前 turn 文件和当前 turn Diff 计算，并在时间线卡片中标记“本回合”。这修复了“累计文件数配当前回合行数”在不同 UI 区域不一致的问题；官方客户端最终采用的展示范围仍需真实客户端矩阵实测。

### P1：撤销条件保守但不能覆盖所有有效文件变更

`canUndoFileChanges` 要求统一 Diff 包含完整文件头、覆盖摘要中的所有路径、未截断且当前没有任务运行。

证据：

- [`lib/src/app_controller_codex_controller_runtime.dart:1414`](<lib/src/app_controller_codex_controller_runtime.dart:1414>)

这能避免误撤销，但当 App Server 只发送路径/类型、或者 tracked 文件 Diff 缺失时，即使实际有可恢复内容，按钮也会一直禁用。当前 Git 补全只对未跟踪文件尝试读取：

- [`lib/src/app_controller_codex_controller_runtime.dart:9590`](<lib/src/app_controller_codex_controller_runtime.dart:9590>)
- [`lib/src/app_controller_codex_controller_runtime.dart:9614`](<lib/src/app_controller_codex_controller_runtime.dart:9614>)

修复建议：

- 保持“无法证明安全就禁用”的原则，不要直接放宽条件。
- 增加任务开始前的 Git baseline，之后可对 tracked 文件计算任务增量，而不是拿当前工作树 Diff 猜测。
- 在按钮旁区分“无 Diff”“Diff 截断”“包含任务前已有改动”“任务仍在运行”等具体原因。
- 只有服务端明确给出任务级 patch 或 baseline 校验通过时才允许撤销。

### 已修复边界：文件路径归属与重复合并

当前文件事件会按工作区路径进行安全匹配，并在整轮 Diff 派生文件时统一处理相对/绝对路径和引号路径；同一 turn 的后续 Diff 会替换派生文件，跨 turn 则保留 thread 摘要。仍建议在官方任务文件矩阵完成后补充最终展示范围验证。

### 部分完成：本地七个任务文件场景已覆盖，官方范围仍待实测

当前仓库已覆盖跨轮修改、只追问、重启恢复、切换任务、撤销禁用和删除清理等本地行为；但官方客户端究竟展示当前 turn、thread 累计集合还是 Git 工作树，无法仅凭本地代码确认。因此官方范围矩阵仍保留为待实测，不阻塞本地实现。

## 十二、建议的修复优先级

### 已完成：本地正确性与状态边界

此前 P0/P1 中的 slash canonical aliases、光标 token 触发、菜单核心元数据共享、跨轮文件摘要、turn Diff 拆分、请求 thread/turn 归属、时间线异步快照和路径合并边界均已实现并通过回归测试。本地实现暂无待处理的同类 P0/P1 修复项。

### 仍待确认：官方行为矩阵

1. 官方 `/`、`@`、`+` 的完整顺序、分组、图标、文案和隐藏/禁用条件。
2. 官方时间线折叠、审批卡锚定、完成提醒和滚动阈值。
3. 官方七个任务文件场景的展示范围、Diff 统计和撤销语义。

### P2：最后做官方行为和视觉对齐

1. 采集官方菜单顺序、隐藏条件和键盘行为矩阵。
2. 采集官方时间线折叠、审批卡和滚动行为矩阵。
3. 完成七个任务文件场景的官方实测。
4. 再进行浅色、深色、窄窗口和边界尺寸 golden 对比。

## 十三、2026-09-29 回归与客户端对照补充

- 完整 `flutter test` 首轮暴露了后台请求选择、首次 turn 撤销空快照、无 thread 撤销、窄窗口 Composer 溢出、工作树路径失效和完成提醒确认等回归；相关执行路径已修复，并以聚焦测试逐项复验。
- `/`、`@`、`+` 当前共享文件、工作区上下文、目标、计划模式和录制技能等命令元数据；禁用项不会截获 Enter，Esc 只关闭当前菜单或浮层，`@` 文件查询仍使用当前工作区的模糊搜索结果。
- 官方客户端真实对照存在环境限制：本机已安装 `/Applications/ChatGPT.app`，Bundle ID 为 `com.openai.codex`、版本 `26.924.22138`，但系统拒绝 Computer Use 自动化绑定该应用；浏览器侧也缺少 Codex 鉴权 token。当前可访问的 `chatgpt` 窗口实际为本地 Xedoc/Codex Desk 构建。因此本轮不能把官方菜单顺序、图标和隐藏条件标记为最终实测完成，后续仍需在允许绑定官方包的环境补齐截图与行为矩阵。
- 当前可访问窗口的 AX/截图证据显示：底部 Composer 有独立的“+”添加入口、审批模式入口（“帮我批准”）、模型与推理强度选择；右侧环境栏显示“任务文件”并在无任务时显示“暂无”。这些证据只能用于确认本地构建的层级和术语，不能替代官方包的菜单顺序、禁用态与键盘实测。
- Goal 完成摘要已补齐：目标完成时，时间线显示带完成图标的“已在 Xm Ys 内达成目标”紧凑提示；服务端未提供用时时按 0 秒安全降级。该实现对齐用户提供的参考形态，但官方字体、图标和精确间距仍属于待实测项。
