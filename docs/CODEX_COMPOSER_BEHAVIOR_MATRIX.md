# Codex Composer 行为验收矩阵

更新时间：2026-10-04

本文档把“官方协议证据”“项目实现证据”和“官方桌面客户端证据”分开记录。App Server 文档只能证明 JSON-RPC、线程/回合、审批和配置接口语义，不能证明桌面客户端的菜单顺序、文案、布局或快捷键视觉行为。

官方协议主证据：[Codex App Server](https://learn.chatgpt.com/docs/app-server)。官方桌面行为需要在固定版本的 Codex 客户端中重新操作并截屏；当前环境无法选择官方 Codex 桌面窗口，因此所有“桌面待验收”状态必须保留。

本轮核对的直接协议章节：[Manage a thread goal](https://learn.chatgpt.com/docs/app-server#manage-a-thread-goal)、[API overview](https://learn.chatgpt.com/docs/app-server#api-overview)、[Events](https://learn.chatgpt.com/docs/app-server#events) 和 [Approvals](https://learn.chatgpt.com/docs/app-server#approvals)。这些章节证明 App Server 的状态与事件契约，不证明桌面菜单、布局或快捷键。

2026-10-04 收到两张官方 Codex 桌面客户端截图，分别展示 Composer 的 `/` 菜单顶部和向下滚动后的后半段。两张图共同证明 `/` 菜单是可滚动的长列表，包含会话、模型、状态、目标、计划模式、重命名、技能，以及 IDE 上下文、MCP、代码审查、侧边聊天、创建聊天分支、初始化、压缩、反馈和归档等命令。截图未覆盖 `@` 菜单、快捷键作用域、禁用态、Goal/Plan 面板或审批浮层，因此这些范围仍保持待验收。

随后收到两张官方客户端 Composer“添加”菜单截图，展示不同滚动位置的插件与上下文入口。已直接观察到文件和文件夹、附加项目、目标、计划模式、录制技能、绘图，以及 Documents、PDF、Spreadsheets、Presentations、Template Creator、浏览器、电脑、Code Review、Visualize 和标签页等入口。进一步确认：在官方 Composer 直接输入 `@` 会立即打开这组“添加”上下文菜单，不会先出现独立的模糊文件搜索列表；文件和目录入口再进入原生选择器。该行为应作为 `@` 的官方触发语义记录，而不是继续假设存在独立 `@` 搜索面板。

同日又收到“添加 → 文件和文件夹”的流程截图：官方客户端打开 macOS 原生列式文件选择器，选中 `custody_oss` 文件夹并通过“打开”返回 Composer；Composer 随后显示带缩略图、文件夹类型标签和移除按钮的 `custody_oss` 附件。该证据确认了原生选择器与 Composer 附件 chip 的边界，但不证明 `@` 提及搜索、路径筛选或结构化 `mention` payload。

随后收到官方 Goal 运行中截图：Composer 上方显示“进行中的目标”状态条，时间线显示该目标请求并处于“正在思考”，发送按钮切换为停止按钮。该图直接证明了目标模式的运行中状态和停止入口，但尚未覆盖完成、暂停、需要用户输入或编辑/清除状态。

又收到运行结束后的官方客户端截图：停止按钮恢复为上箭头发送按钮，Composer 回到可编辑、可提交的空闲状态，时间线不再显示“正在思考”。该图证明了 Goal 回合结束后的 Composer 空闲边界；截图中没有独立的“Goal 已完成”卡片或完成文案，因此不把它扩展解释为完整的 Goal 完成卡片证据。

## VS Code 真实宿主 smoke check

2026-10-04 在本机 VS Code `1.135.0` 中以扩展开发目录加载
`integrations/vscode-codex-context`，通过 `codexDesk.discoveryFile` 指向临时
loopback discovery 文件，并打开本仓库 `README.md`。独立 transport runner 实际
收到过无文件快照、`openTabs` 更新以及包含 `activeFile`、空选区范围和绝对路径的
快照；Node 测试另外覆盖了真实 HTTP server 下的选区变化和扩展停用 `{}` 断连。
这证明了“VS Code 扩展 → discovery → loopback transport”的真实宿主链路，但不
证明官方 Codex 桌面窗口的视觉、菜单或 IDE 生命周期语义。

同日还用 VS Code `1.135.0` 的隔离 `user-data-dir` 和 `extensions-dir` 完成了
本地 VSIX 安装 smoke check；安装成功后已删除临时 profile、扩展目录和 VSIX，
没有修改用户现有 VS Code 配置。真实 VSIX 首次验证发现未信任工作区不会激活宿主，
随后加入 `capabilities.untrustedWorkspaces.supported` 并在全新隔离 profile 中确认
`onStartupFinished` 实际激活、持续发送快照；Node 生命周期测试另外覆盖 discovery
文件删除后不发送陈旧快照、文件恢复后自动重连，以及工作区切换后发送新的当前文件。

2026-10-05 再次探测官方 Codex 客户端 surface：应用清单可以看到正在运行的
官方 `ChatGPT`（`com.openai.codex`）；不过 `cua.getApp("ChatGPT")` 会解析到本项目
的 `chatgpt`（`com.yozoe.chatgpt`，AX 标题为“Codex Desk”），按官方安装路径
`/Applications/ChatGPT.app` 绑定则被当前 Computer Use 安全策略拒绝。本次没有获得
官方窗口状态、客户端版本、窗口尺寸、主题或截图，官方桌面验收状态不变。

同日重跑项目侧 IDE 验证：`integrations/vscode-codex-context` 的 Node 测试 2/2
通过，`dart run tool/verify_ide_context_host_transport.dart` 通过；该证据只覆盖
VS Code 宿主和 Debug Codex Desk 的 loopback 链路，不覆盖官方 Codex 客户端语义。

## 总矩阵

| 范围 | 官方协议/文档证据 | 项目实现与测试证据 | 官方桌面证据 | 当前结论 | 下一步 |
| --- | --- | --- | --- | --- | --- |
| `@` 文件/目录上下文 | App Server 支持结构化输入和文件系统接口，但没有 Composer 菜单顺序或触发边界定义 | `fuzzyFileSearch`、路径边界、符号链接和 `mention` 输入已实现；见 `test/composer_trigger_boundary_test.dart`、`test/widget_test.dart` | 官方截图与操作记录证明：直接输入 `@` 会立即打开“添加”上下文菜单；菜单中的“文件和文件夹”入口再打开 macOS 原生选择器。当前未观察到独立的 fuzzy 搜索列表，也未覆盖句首/句中/空白后/换行、筛选顺序和焦点操作 | `@` 的官方触发语义已部分对齐：触发添加菜单；项目侧非空查询 fuzzy 搜索作为增强能力保留并已通过测试，官方查询形态仍待补证 | 对照文件/目录入口的选中后 payload、取消流程和不同输入位置 |
| Composer“添加”菜单 | App Server 可承载文件、图片、结构化 Goal/Plan/Skill 和插件工具输入，但不定义桌面添加菜单呈现 | 文件/文件夹、项目上下文、Goal、Plan、Skill、绘图和插件入口均已实现并覆盖测试；见 `test/widget_test.dart`、`test/composer_menu_matrix_test.dart` | 用户提供的官方客户端截图证明添加菜单是可滚动列表，包含文件/文件夹、附加项目、目标、计划模式、录制技能、绘图，以及 Documents、PDF、Spreadsheets、Presentations、Template Creator、浏览器、电脑、Code Review、Visualize 和标签页；另有流程截图证明“文件和文件夹”打开原生列式选择器，选中目录后返回 Composer 显示带缩略图和移除按钮的文件夹附件；未证明各入口的快捷键、禁用条件和提交后的结构化 payload | 官方添加菜单结构及文件夹附件流程已有直接截图证据，`@` 提及和协议映射仍需逐项核对 | 补充 `@` 文件/目录搜索、插件筛选、禁用态和提交后输入结构 |
| `/` 命令菜单 | App Server 定义 Goal、Review、Thread、Turn 等能力，不定义桌面命令菜单呈现 | 命令筛选、键盘导航、Goal/Plan/Skill/Review/Compaction 等已覆盖；见 `test/composer_menu_matrix_test.dart`、`test/composer_slash_command_test.dart` | 用户提供的官方客户端截图证明菜单为可滚动长列表，并记录了顶部与滚动后半段的命令顺序：新聊天、模型、状态、目标、计划模式、重命名、IDE 上下文、MCP、代码审查、侧边聊天、分支、初始化、压缩、反馈、归档等；未覆盖 `@`、图标、禁用态和 Tab/Esc 行为 | 官方 `/` 菜单结构已有直接截图证据，交互细节仍待验收 | 补充 `/` 的筛选、键盘导航、禁用条件和 Tab/Esc 行为；`@` 菜单单独按其触发矩阵验收 |
| Goal | 官方 App Server 文档明确：`thread/goal/set|get|clear` 管理同一份持久化 Goal 状态，且该状态由 TUI `/goal` 展示；文档不定义桌面卡片布局 | Goal 状态、恢复、blocked、继续、预算和线程隔离已覆盖；见 `test/runtime_protocol_test.dart`、`test/goal_completion_summary_test.dart` | 用户提供的官方客户端截图证明运行中状态：Composer 上方显示“进行中的目标”，时间线显示目标请求和“正在思考”，发送按钮变为停止按钮；另有结束后截图证明停止按钮恢复为上箭头、Composer 回到空闲可提交状态；未取得独立 Goal 已完成卡片、暂停/恢复、需要输入、编辑和清除截图 | 官方 Goal 运行中与结束后 Composer 空闲边界已有直接证据，完整生命周期视觉仍待验收 | 补充完成卡片、暂停/恢复、需要输入和编辑/清除状态 |
| Plan | 官方 App Server API overview 定义实验性的 `collaborationMode/list`，并允许 `turn/start` 携带 `collaborationMode`；桌面步骤面板仍未由协议定义 | Plan 选择、实时步骤、完成后实现和跨线程隔离已覆盖；见 `test/plan_mode_parity_test.dart` | 未取得官方步骤面板尺寸、动效和快捷键证据 | 协议和项目行为已验证，视觉待验收 | 对照 `Shift+Tab`、面板和完成卡片 |
| 任务文件 | 官方 App Server 文档只定义 thread item 中的 file change、Diff/turn 事件及 thread/item 读取接口，没有定义桌面“任务文件”聚合范围 | 按 thread/turn 保存文件摘要、Diff、撤销和恢复；已覆盖四轮修改矩阵、无变更追问后的重建恢复、项目切换和撤销冲突；见 `test/task_file_parity_matrix_test.dart`、`test/file_change_protocol_test.dart` | 未证明官方以最新 turn、整个 thread、Git 工作树或其他组合展示 | 项目持久化已验证，官方产品语义未定 | 执行四轮修改/追问/旧文件/新文件流程并记录范围 |
| 审批 | 官方 App Server API overview 定义 server-initiated `item/permissions/requestApproval`，以及 `mcpServer/elicitation/request` 的结构化表单/确认请求；协议不规定浮层几何 | 命令、文件变更、额外权限、MCP 表单和后台线程归属已覆盖；见 `test/approval_controller_test.dart`、`test/mcp_elicitation_controller_test.dart` | 未取得官方浮层高度、按钮顺序、自动批准视觉和焦点证据 | 协议和项目行为已验证，视觉待验收 | 对照手动、自动、拒绝、后台任务四组状态 |
| 快捷键 | App Server 不定义桌面快捷键 | `⌘L`、`⌘T`、`⌘W`、`⌘R`、`Shift+Tab`、`Esc`、`⌘N`、`⌘K` 等有项目测试 | 未取得官方快捷键作用域、输入法组合态和焦点转移证据 | 项目行为已验证，官方语义待验收 | 固定窗口和输入法状态逐项记录 |
| 智能体默认设置 | `config/read`、`config/value/write`、`config/batchWrite` 及配置来源/版本有官方协议证据 | 三态值、来源、能力探测、`expectedVersion`、连续写入和失败回滚已覆盖；另已验证运行中 turn 保留原模型/推理强度、controller 重建后恢复模型/推理偏好、runtime 重连后重新读取 effective defaults；见 `test/model_configuration_test.dart`、`test/codex_app_server_config_write_test.dart` | 未取得用户配置选择器、覆盖提示、保存位置和重启后的官方界面证据 | 协议和项目生命周期行为已验证，桌面边界待验收 | 在官方客户端中验证运行中、切换项目、重连、重启下的界面与保存语义 |
| IDE 上下文 | App Server 可接收 `additionalContext`，但不定义宿主插件 IPC | 通用 `codex_desk/ide_context` bridge 与首个独立 VS Code 宿主已交付；loopback discovery/token、编辑器事件、选区、可见 Tab、停用断连、发现文件删除/恢复重连和工作区切换已覆盖，见 `test/codex_ide_context_bridge_test.dart`、`integrations/vscode-codex-context/extension.test.js`、`tool/verify_ide_context_host_transport.dart`；VS Code 1.135.0 隔离 VSIX 安装在未信任工作区中已实际激活并把快照转发到真实 Debug Codex Desk，桌面 `/IDE 上下文` 从“未连接”变为可用 | 无官方桌面插件证据；真实 Codex Desk 的重启、旧 token 失效和新 discovery 接收已验证，但官方客户端语义仍未证明 | VS Code 宿主与真实 Debug Codex Desk 端到端链路已验证 | 继续官方 Codex 客户端矩阵与视觉/任务文件验收 |

## 统一验收状态

- 已证明：项目内部协议映射、状态隔离、持久化和回归测试。
- 已部分证明：官方 Codex 桌面客户端 `/` 菜单的长列表结构和主要命令顺序（依据用户提供的两张截图）。
- 已部分证明：官方添加菜单中的原生文件夹选择与 Composer 附件 chip 流程（含取消/打开边界的截图证据）。
- 已部分证明：官方桌面客户端输入 `@` 后直接打开“添加”上下文菜单，文件/目录入口进入原生选择器。
- 未证明：完整视觉几何、快捷键作用域、Goal/Plan/审批状态和任务文件展示范围，以及官方是否在其他上下文提供独立 fuzzy 文件搜索。
- 当前阻塞条件：CUA 能枚举其他应用，但无法选择官方 Codex 客户端窗口；官方 [Computer Use 文档](https://learn.chatgpt.com/docs/computer-use.md) 明确说明该功能不能自动化 ChatGPT 本身，因此这不是可通过普通应用授权解除的权限问题，后续桌面证据需要由用户提供截图或操作记录。
- 解除阻塞后，必须记录客户端版本、macOS 版本、运行时版本、账号能力和窗口尺寸；版本变化时建立新矩阵，不覆盖旧证据。

## 任务文件实验记录模板

固定同一项目和同一聊天，依次执行：

1. 第一轮修改已有文件。
2. 第二轮只追问，不修改文件。
3. 第三轮继续修改旧文件。
4. 第四轮修改新文件。
5. 分别执行审查、撤销、恢复、切换聊天、切换项目和应用重启。
6. 记录任务开始前已有的 Git 工作树改动是否进入任务文件区域。

每一步同时记录：服务端文件事件、右侧任务文件列表、Git Diff、撤销入口、恢复后的列表和项目切换后的列表。只有这些记录能确定任务文件的最终生命周期语义。

### 当前项目实现结论（不等同于官方结论）

- 任务文件摘要按聊天 thread 累积；没有文件变更的追问不会清空既有摘要，controller 重建后仍保留该摘要。
- 最新一轮的文件集合和 Diff 独立保留，用于当前轮审查与撤销判断。
- 撤销只在最新一轮 Diff 完整覆盖当前轮文件、未被后续编辑或暂存区改动冲突时可用。
- 切换任务、切换项目和重启通过本地历史快照恢复 thread 摘要；新聊天从空摘要开始。
- 这些结论已有 `test/task_file_parity_matrix_test.dart` 覆盖，但在官方 Codex 客户端完成四轮操作前，不能将其称为官方任务文件生命周期。
