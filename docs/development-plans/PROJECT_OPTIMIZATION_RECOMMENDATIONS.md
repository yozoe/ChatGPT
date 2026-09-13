# Codex Desk 项目优化建议

> 生成日期：2026-09-06
> 文档性质：基于当前仓库实现与验证结果形成的优化提案，不代表相关事项已经交付。

## 1. 总体判断

Codex Desk 已经具备较高的功能完成度，覆盖 Codex App Server 连接、会话历史、Git 审查、插件与 MCP、内置浏览器、文件预览、计划任务、子智能体和 macOS 原生集成等能力。

当前最值得投入的方向不是继续扩大功能面，而是：

1. 稳定自动化测试基线；
2. 降低核心状态与界面的耦合；
3. 缩小流式更新造成的 Widget 重建范围；
4. 改善大型文件和测试套件的可维护性；
5. 补齐 macOS 原生层与发布链路验证。

## 2. 分析快照（2026-09-06）

以下指标记录本提案生成时的分析结果；它们不是持续更新的仓库规模仪表盘。实施后应在对应任务的验收记录中重新采集数据。

| 项目 | 当前情况 |
| --- | --- |
| `flutter analyze` | 通过，无静态分析问题 |
| 完整 `flutter test` | P0 完成后连续 3 次通过（每次 481 项）；2026-09-07 当前工作树拆分后 497 项通过；`--concurrency=1` 基线亦通过 |
| `lib` 下 Dart 文件 | 337 个 |
| 测试 Dart 文件 | 45 个 |
| `CodexController` | 约 8,453 行 |
| `CodexWorkspaceState` | 约 3,040 行 |
| `test/widget_test.dart` | 约 18,977 行、约 402 个测试 |
| `CodexController.notifyListeners()` | 约 154 处 |
| 忽略 `unused_import` 的 `lib` 文件 | 约 241 个 |
| macOS 自定义 Swift | 约 416 行，原生测试仍为占位内容 |

初始分析时工作树保持干净；本提案的 P0 已在 2026-09-07 完成实现与验证。

## 3. 优先优化事项

### P0：稳定测试基线（已完成）

#### 完成内容

原有失败来源与本次处理如下：

1. 新增可注入的 `CodexClock`，计划任务的校验、任务 ID 时间戳、计时器延迟和排期弹层均使用同一时间来源。
2. “过去时间”回归测试改为固定时钟和显式初始排期，不再操作系统日期/时间选择器，也不依赖时区或 12/24 小时制。
3. 计划任务取消竞态测试改为显式驱动待分发任务，不再等待真实 100ms 定时器。
4. Markdown 工作区预览测试改为等待目标 Tab 与内容实际出现，不再依赖固定的 60/80/220ms 异步 I/O 等待。
5. 方向调整附件竞态测试改为等待 Fake App Server 明确进入 `steerTurn`，不再假设固定数量的事件循环足以完成附件持久化。

#### 验证结果

- `flutter analyze` 通过。
- 默认并发下，完整 `flutter test` 连续 3 次全部通过（每次 481 项）。
- `flutter test --concurrency=1` 通过（481 项）。
- 定向验证计划任务持久化、取消竞态、过去时间提示与 Markdown 工作区预览均通过。

其他与本次失败无关的固定等待和全局测试替身不在此 P0 范围内，后续可结合按功能拆分测试文件的 P1 工作继续收敛。

### P1：拆分核心状态并缩小重建范围

#### 当前进度（2026-09-07）

- 运行时诊断日志已从全局控制器刷新路径中切出独立监听边界：`CodexRuntimeDiagnostics` 直接通知诊断区域，设置弹窗的日志子树不再等待整个工作区重建；诊断报告、复制、导出与清除 API 保持不变。
- 计划任务的排期、持久化、计时器、重试、跨项目切换和取消竞态已提取至 `ScheduledTaskCoordinator`；`CodexController` 保持既有公开 API 与时间线/运行时回调，计划任务的持久化和切换中取消回归可独立验证。

#### 现状

`CodexController` 同时负责：

- App Server 生命周期；
- 当前项目与附加目录；
- 会话、线程与后台任务；
- 时间线与流式输出；
- 历史缓存和附件；
- 审批与 MCP elicitation；
- 插件、技能和 marketplace；
- Git 状态、Diff 和审查操作；
- 计划任务；
- 运行时诊断与通知。

当前 Riverpod 层仍然发布同一个可变 `CodexController` 实例，并将 `updateShouldNotify` 固定为 `true`。工作区根节点直接监听整个控制器。流式文本通知以 50ms 为合并窗口，理论上仍可能触发每秒约 20 次较大范围的界面重建。

#### 建议

按业务边界逐步迁移为独立 Riverpod Notifier，例如：

- `RuntimeConnectionNotifier`
- `ConversationNotifier`
- `WorkspaceCatalogNotifier`
- `GitReviewNotifier`
- `ExtensionCatalogNotifier`
- `ScheduledTasksNotifier`
- `RuntimeDiagnosticsNotifier`

每个 Notifier 应发布不可变状态快照。界面使用 `ref.watch(provider.select(...))` 只订阅需要的字段。

单个 Widget 内部且生命周期明确的状态继续保留为局部状态，例如：

- 悬停；
- 展开/收起；
- 输入法组合态；
- 临时输入内容；
- 当前弹层位置；
- 单个滚动视口的短期交互状态。

#### 迁移顺序

1. 先提取依赖较少的计划任务和运行时诊断状态。
2. 再提取插件、MCP、技能和 Git 审查状态。
3. 最后处理会话、线程、流式时间线和项目切换。
4. 每次只迁移一个状态域，保持用户可见行为不变。

#### 验收标准

- 流式文本更新不会重建工作区侧栏、设置页、浏览器和无关扩展面板。
- 项目列表刷新不会重建当前 Markdown 回复子树。
- 每个异步状态域都有明确的 loading、data、error 和刷新代次边界。
- 不再通过一个全局 `ChangeNotifier` 广播所有功能变化。

### P1：拆分大型实现和测试文件

#### 当前进度（2026-09-07）

- 已将计划任务持久化/取消竞态回归迁移到 `test/scheduled_tasks_test.dart`，并显式初始化 Flutter test binding，使其可以脱离混合 Widget 测试文件独立执行。
- 已将 Markdown 与源码工作区预览回归迁移到 `test/markdown_workspace_preview_test.dart`，保留真实文件 I/O、Tab 保活、相对链接、源码模式和关闭 Tab 的断言；源码刷新改为等待目标内容出现，不再依赖固定 80ms 延时。
- 已将浏览器与文件工作区的 Tab 创建、窗口收起、焦点释放、全页切换和状态保活回归迁移到 `test/browser_workspace_test.dart`，不再与无关的侧栏和 Composer 测试共享同一个混合测试文件。
- 已将运行时诊断的凭据脱敏、有界日志、局部刷新、并发启动去重、CLI 缺失探测及失败后可恢复重试回归迁移到 `test/runtime_diagnostics_test.dart`；控制器测试显式等待初始配置，使诊断域可独立验证而无需加载完整工作区 Widget 套件。
- 已将子智能体头像、目录分组、并发活动与检查器 Tab 回归迁移到 `test/subagent_workspace_test.dart`；测试拆分遗留的无用导入已清理，独立测试和全量默认并发套件均通过。
- 新增 `test/file_change_stats_test.dart`，独立覆盖混合不可计数 Diff、多工程路径补齐、精确路径优先、有歧义后缀拒绝统计及禁止借用无关整轮 Diff 的边界。
- 已将 App Server 文件事件与整轮统一 Diff 的合并、仅整轮 Diff 文件派生、后续 Diff 替换、元数据事件后的补丁刷新及带引号路径解析迁移到 `test/file_change_protocol_test.dart`；上游快照协议与下游统计边界现在可以分别独立回归。
- 已将账户通知状态、服务端认证要求与恢复线程附着前发送门禁迁移到 `test/session_access_test.dart`，会话访问边界不再依赖巨型 Widget 测试文件的初始化顺序。
- 已将侧栏长任务标题渐隐与渐隐层尾缘锚定迁移到 `test/sidebar_task_title_test.dart`，窗口尺寸和行尾布局回归可独立执行，不再与用户消息交互测试混杂。
- 已将用户消息右对齐/内部左对齐、长内容折叠、悬停时间与复制操作不挤动布局，以及内联编辑发送迁移到 `test/user_message_bubble_test.dart`；窗口边界、鼠标生命周期和剪贴板清理均在独立 Widget 套件中保留。
- 已将普通权限审批的响应编码、命令级会话批准、文件变更单次批准、自动批准模式、统一文案及配置持久化迁移到 `test/approval_controller_test.dart`；普通审批与 MCP elicitation 协议不再混在同一测试职责中。
- 已将 MCP elicitation 的结构化接受响应、自动批准模式下保持人工确认及畸形 schema 安全拒绝迁移到 `test/mcp_elicitation_controller_test.dart`，表单协议安全边界可脱离 Widget 布局独立验证。
- 已将 MCP elicitation 的后台任务来源标识与提交、窄窗口大表单高度约束、审批/表单到达顺序及当前任务提示优先级迁移到 `test/mcp_elicitation_widget_test.dart`；协议和呈现两层测试均已脱离巨型 Widget 文件。
- 已将 Agent 文本增量合并、reasoning summary 通知节流与活动覆盖、命令生命周期/耗时/迟到隔离、Web 搜索/MCP item、文件读搜列改动作，以及动态技能读取状态迁移到 `test/runtime_streaming_test.dart`，流式与 live activity 状态更新可独立验证。
- 已完成运行时完成事件纯控制器测试域拆分：`test/runtime_completion_test.dart` 可独立验证同一回合完成事件去重、旧协议无回合 ID 的前台完成、迟到重放隔离、任务失败后继续复用已连接运行时、同一后台项目的多个完成事件串行保存、无 ID 后台完成的跨项目对账、切换竞态，以及成功/取消前后台任务的提醒确认矩阵。实际 Widget 与系统通知呈现继续由对应界面集成测试覆盖。
- 已将失败回合重试的 8 个纯控制器回归迁移到 `test/failed_turn_retry_test.dart`，独立覆盖自动网络等待耗尽、额度分类、结构化启动错误、原始输入保真、重复提交保护、切换任务竞态、再次失败保留重试及中断不提供重试；统一显式等待初始配置，移除对巨型 Widget 文件全局初始化顺序的依赖。
- 已将 App Server 请求编码和线程启动契约迁移到 `test/runtime_protocol_test.dart`，独立覆盖历史线程模型来源、新线程多工作区根、开始线程/回合、运行中调整、停止回合和实验能力初始化负载；协议测试不再与 Git、历史和界面回归共享同一测试文件。
- 已将模型与推理强度配置回归迁移到 `test/model_configuration_test.dart`，独立覆盖新线程参数、模型切换后的能力过滤、默认模型能力范围、服务端新增推理强度兼容、目录加载失败以及项目切换时清理运行时配置；测试显式等待初始配置，原混合 Widget 文件中的重复块已删除。
- 已将 Git 审查的 6 个纯状态与控制器回归迁移到 `test/git_review_controller_test.dart`，独立覆盖操作错误、过滤、大型 Diff 截断、选中 Diff、连续多文件审查和最多 6 路并发读取；界面弹窗测试继续留在 Widget 域，控制器测试显式等待初始配置。
- 已将 4 个真实临时仓库的 Git 服务安全回归归入 `test/git_project_service_test.dart`，集中覆盖隐藏未跟踪文件的检查与删除、精确反向应用、冲突时保留用户修改、路径白名单和暂存区保护；原混合 Widget 文件中的重复块已删除。
- 已将线程历史解析、最新回合文件快照、恢复状态、最近 8 个任务视图缓存、回合/项目分页、协作与上下文压缩记录、分页失败隔离及页数上限部分结果的 10 个控制器回归迁移到 `test/thread_history_test.dart`；测试显式等待初始配置，原混合 Widget 文件中的重复块已删除。
- 已将线程列表刷新代次、稳定排序、取消归档恢复以及归档/删除通知同步刷新的 5 个控制器回归迁移到 `test/thread_list_refresh_test.dart`；独立验证活动与归档列表的一致性，测试显式等待初始配置，原混合 Widget 文件中的重复块已删除。
- 已将连续命令/搜索活动分组、自动批准命令合并、同时间戳活动隔离及展开动画回归迁移到 `test/timeline_activity_list_test.dart`，时间线活动清单现在可以脱离巨型 Widget 套件独立验证。
- 已将本地会话列表缓存、历史写入串行化、缓存容错、活动元数据往返、旧时间线稳定 ID 和导入格式版本边界迁移到 `test/conversation_history_serialization_test.dart`，并保留 `test/conversation_history_store_test.dart` 的加密磁盘持久化覆盖；两层基础契约均可独立执行。

#### 现状

以下文件已形成明显的高变更半径：

- `lib/src/app_controller_codex_controller_runtime.dart`
- `lib/src/presentation/workspace/codex_workspace_state.dart`
- `lib/src/presentation/settings/codex_workspace_settings_page_state.dart`
- `lib/src/presentation/conversation/codex_workspace_conversation_composer_panel_state.dart`
- `test/widget_test.dart`

特别是 `test/widget_test.dart` 同时包含侧栏、Composer、运行时、历史、Markdown、Git、插件、审批和后台任务测试，不利于定位失败、并行执行和多人修改。

#### 建议

测试按产品能力拆分：

```text
test/
  conversation/
    composer_test.dart
    steering_test.dart
    timeline_scrolling_test.dart
    markdown_rendering_test.dart
  runtime/
    connection_test.dart
    retry_test.dart
    approvals_test.dart
  workspace/
    switching_test.dart
    history_test.dart
    sidebar_test.dart
  extensions/
    plugins_test.dart
    scheduled_tasks_test.dart
  git/
    review_workspace_test.dart
    undo_test.dart
```

共享 Fake 也应按职责拆分，并继续遵守“一类一文件、公开类名”的仓库规则。

#### 验收标准

- 单个测试文件原则上不超过约 1,500 行。
- 任一主要能力可以通过一条聚焦命令单独验证。
- CI 可以按功能域分片运行测试。
- 测试失败信息能直接指向对应产品模块。

### P1：恢复静态分析信号

#### 当前进度（2026-09-07）

- `CodexController` 运行时实现、Riverpod 桥接 Notifier 及全部拆分库文件已移除整文件 lint 豁免。Dart 自动修复清理了超过一千处无用或重复导入和缺失的构造函数 Key；全库 `dart analyze lib` 通过，`unused_import`、`unnecessary_import`、`duplicate_import` 和 `use_key_in_widget_constructors` 的整文件豁免均为零。

#### 现状

历史上大量拆分后的 Dart 文件使用了整文件级忽略：

- `unused_import`
- `unnecessary_import`
- `duplicate_import`
- `use_key_in_widget_constructors`

这曾使 `flutter analyze` 虽然能够通过，但部分代码质量问题被全局屏蔽；该批豁免现已清理完毕。

#### 建议

- 按目录逐批清理无用和重复导入。
- 删除不再需要的 `ignore_for_file`。
- 避免通过大型依赖聚合文件向所有 Widget 暴露过多符号。
- 在现有 lint 基础上评估启用：
  - `unawaited_futures`
  - `discarded_futures`
  - `cancel_subscriptions`
  - `close_sinks`
  - `use_build_context_synchronously`
  - `avoid_dynamic_calls`
- 对确实需要忽略的代码使用最小范围的单行说明。

#### 验收标准

- `lib` 中不再批量忽略 `unused_import` 和 `duplicate_import`。
- 新增文件不得复制通用的整文件忽略模板。
- 静态检查仍保持零错误、零警告。

### P1：建立性能基准

#### 建议场景

在 Profile 模式下建立可重复的基准场景：

1. 持续接收 5 分钟流式回复；
2. 在两个长会话之间快速切换；
3. 加载 1,000 个历史任务的侧栏；
4. 打开包含大量文件和长 Diff 的审查工作区；
5. 同时运行多个后台任务并接收完成通知；
6. 展开内置浏览器后返回会话继续流式输出。

#### 建议指标

- 目标帧时间及掉帧比例；
- 每次流式增量涉及的 Widget rebuild 数量；
- 长会话切换耗时；
- 常驻内存与最近 8 个会话缓存占用；
- 大型 Diff 的解析时间与峰值内存；
- 应用冷启动到工作区可交互的时间。

优化应以测量结果为准，优先处理可重复观察到的瓶颈。

### P1：补齐 macOS 原生层测试

#### 当前进度（2026-09-07）

- `RunnerTests` 已不再是模板占位：剪贴板临时文件的直接文件删除、嵌套路径、目录外路径和受管目录子目录拒绝均由 Xcode 的 macOS Test Target 覆盖并通过。
- 剪贴板删除边界已提取为不依赖窗口或 MethodChannel 的 `ClipboardTemporaryItemStore`，同时编译进 Runner 与 RunnerTests，避免测试依赖不可导入的可执行 Runner 模块。
- Dock badge 文本规范已提取为同时编译进 Runner 与 RunnerTests 的 `DockBadgeCount`；负数/零、普通计数和超过 99 的上限均有原生测试覆盖。
- `setDockBadge` 的 MethodChannel 参数解析已收敛为原生纯逻辑：兼容旧版 `visible` 负载，接受整数 `count`，并拒绝缺失字段或错误类型，避免无效请求静默清除徽标。

#### 现状

`macos/Runner/AppDelegate.swift` 和 `macos/Runner/MainFlutterWindow.swift` 仍包含通知、Dock 图标和窗口生命周期等尚未完全覆盖的用户可见行为；剪贴板删除与 Dock badge 参数/数值边界已经脱离模板占位并具备原生测试。

#### 建议覆盖

- 剪贴板临时文件只能从指定目录安全删除；
- 目录外路径、嵌套路径和非法参数必须被拒绝；
- Dock badge 在主线程更新；
- badge 数量的边界行为；
- 未知 Dock 图标返回明确错误；
- 通知权限拒绝、通知提交失败和 AppDelegate 不可用；
- MethodChannel 参数缺失或类型错误；
- 窗口恢复与激活回调的生命周期。

#### 验收标准

- CI 执行 `RunnerTests`（本地 `xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' test` 已通过）。
- Swift 原生测试覆盖关键成功和失败路径。
- 原生层改动不再只能依靠人工回归发现问题。

### P2：分批升级依赖

#### 当前进度（2026-09-07）

- 已独立升级 `flutter_riverpod` 至 `3.4.3`，同步解析 `riverpod` 与相关锁定依赖；`flutter analyze` 及主题/Provider 定向回归通过。
- 已独立升级 `desktop_drop` 至 `0.8.4`；静态检查、Composer 拖放去重及 macOS 安全作用域释放回归通过。
- 已独立升级 `flutter_secure_storage` 至 `11.0.0`；静态检查与本地加密存储回归通过。现有应用的本地存储实现不使用 Keychain，仍需在发布前的干净 macOS 账户安装回归中验证真实升级路径。

`flutter pub outdated` 显示以下直接依赖存在可解析的新版本：

| 依赖 | 当前版本 | 可解析版本 |
| --- | --- | --- |
| `desktop_drop` | `0.8.4` | `0.8.4` |
| `flutter_riverpod` | `3.4.3` | `3.4.3` |
| `flutter_secure_storage` | `11.0.0` | `11.0.0` |

建议每个直接依赖单独升级和提交，避免同时引入多个行为变量。

其中 `flutter_secure_storage` 是主版本升级，需要重点验证：

- macOS 既有数据读取；
- 存储迁移；
- 删除和覆盖语义；
- 无 Keychain 或权限异常时的恢复路径。

## 4. 发布与产品路线建议

### 近期

1. 修复测试确定性问题。
2. 完成干净 macOS 用户账户或测试机的 DMG 安装回归。
3. 补充原生测试和 Release 构建验证。
4. 在具备凭据后完成签名、公证和 notarized DMG 回归。

### 中期

1. 完成无障碍审计，包括键盘导航、焦点顺序、语义标签和高对比度。
2. 完成内置浏览器公开协议、安全边界、下载确认和独立数据边界。
3. 逐步迁移核心状态到职责明确的 Riverpod Notifier。

### 后期

本地 Worktree 是高价值能力，但会同时增加线程、目录、Git、持久化和清理生命周期的复杂度。建议在测试基线、状态边界和发布链路稳定后再进入全面实现。

## 5. 推荐实施阶段

### 第一阶段：质量基线（P0 已完成）

- 已完成修复原有失败测试、注入 `CodexClock`、移除本轮涉及的真实延时，并建立连续测试稳定性验收；计划任务仍使用 Dart `Timer`，尚未引入独立调度器抽象。
- 已完成计划任务与 Markdown 工作区预览测试的首批拆分；后续在 P1 中继续清理其余真实延时和跨测试全局状态。
- 继续拆分 `widget_test.dart`，让其余关键能力可独立执行与分片。

### 第二阶段：架构与性能

- 建立 Profile 性能基准；
- 提取计划任务、诊断、插件和 Git 状态；
- 使用不可变 Riverpod 状态和 `select`；
- 对比迁移前后的 rebuild、帧时间和内存。

### 第三阶段：发布工程

- 补充 macOS 原生测试；
- 分批升级依赖；
- 增加 Release 构建和 DMG 校验；
- 完成干净环境安装、签名和公证回归。

## 6. 文档同步要求

实施本提案时，应继续遵守仓库的文档同步约定：

- 用户可见行为或限制发生变化时更新 `README.md`；
- 在 `ROADMAP.md` 的唯一任务清单中更新状态；
- 在 `RELEASE_NOTES.md` 的未发布版本中记录用户可感知的新增或修复；
- 仅测试拆分、内部重构或无用户可见行为的性能优化，可以不新增发布说明，但应在代码审查中明确说明原因。

## 7. 建议的下一个实施任务

计划任务、Markdown/源码预览、浏览器/文件工作区、运行时诊断和子智能体测试完成首批拆分后，下一个实施任务建议定义为：

> 将 `test/widget_test.dart` 中 App Server 完成事件、后台任务和通知提醒回归迁移到职责明确的 runtime 测试文件；保留有 ID、无 ID、前台、后台、迟到重放和跨项目对账的完整矩阵，并保持默认并发与单并发完整套件通过。

这一组测试共享同一状态机边界，独立后可显著缩短完成事件兼容性回归的定位时间，也为后续提取 Conversation/Runtime Riverpod 状态建立安全网。
