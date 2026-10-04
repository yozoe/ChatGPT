# Codex Composer 行为验收矩阵

更新时间：2026-10-04

本文档把“官方协议证据”“项目实现证据”和“官方桌面客户端证据”分开记录。App Server 文档只能证明 JSON-RPC、线程/回合、审批和配置接口语义，不能证明桌面客户端的菜单顺序、文案、布局或快捷键视觉行为。

官方协议主证据：[Codex App Server](https://learn.chatgpt.com/docs/app-server)。官方桌面行为需要在固定版本的 Codex 客户端中重新操作并截屏；当前环境无法选择官方 Codex 桌面窗口，因此所有“桌面待验收”状态必须保留。

## VS Code 真实宿主 smoke check

2026-10-04 在本机 VS Code `1.135.0` 中以扩展开发目录加载
`integrations/vscode-codex-context`，通过 `codexDesk.discoveryFile` 指向临时
loopback discovery 文件，并打开本仓库 `README.md`。独立 transport runner 实际
收到过无文件快照、`openTabs` 更新以及包含 `activeFile`、空选区范围和绝对路径的
快照；Node 测试另外覆盖了真实 HTTP server 下的选区变化和扩展停用 `{}` 断连。
这证明了“VS Code 扩展 → discovery → loopback transport”的真实宿主链路，但不
证明官方 Codex 桌面窗口的视觉、菜单或 IDE 生命周期语义。

## 总矩阵

| 范围 | 官方协议/文档证据 | 项目实现与测试证据 | 官方桌面证据 | 当前结论 | 下一步 |
| --- | --- | --- | --- | --- | --- |
| `@` 文件/目录上下文 | App Server 支持结构化输入和文件系统接口，但没有 Composer 菜单顺序或触发边界定义 | `fuzzyFileSearch`、路径边界、符号链接和 `mention` 输入已实现；见 `test/composer_trigger_boundary_test.dart`、`test/widget_test.dart` | 未取得句首/句中/空白后/换行、筛选顺序和焦点操作截图 | 项目行为已验证，官方 UI 未对齐证明 | 固定客户端版本后记录完整菜单矩阵 |
| `/` 命令菜单 | App Server 定义 Goal、Review、Thread、Turn 等能力，不定义桌面命令菜单呈现 | 命令筛选、键盘导航、Goal/Plan/Skill/Review/Compaction 等已覆盖；见 `test/composer_menu_matrix_test.dart`、`test/composer_slash_command_test.dart` | 未取得分组、图标、禁用态和 Tab/Esc 行为截图 | 项目行为已验证，官方 UI 未对齐证明 | 对照官方菜单顺序和禁用条件 |
| Goal | `thread/goal/set|get|clear` 及生命周期事件有官方协议证据 | Goal 状态、恢复、blocked、继续、预算和线程隔离已覆盖；见 `test/runtime_protocol_test.dart`、`test/goal_completion_summary_test.dart` | 未取得官方卡片文案、状态行和编辑/暂停布局证据 | 协议和项目行为已验证，视觉待验收 | 固定版本验证运行中/完成/需要输入三态 |
| Plan | `collaborationMode` 和 `turn/plan/updated` 有官方协议证据 | Plan 选择、实时步骤、完成后实现和跨线程隔离已覆盖；见 `test/plan_mode_parity_test.dart` | 未取得官方步骤面板尺寸、动效和快捷键证据 | 协议和项目行为已验证，视觉待验收 | 对照 `Shift+Tab`、面板和完成卡片 |
| 任务文件 | App Server 有文件变更和 Diff 相关事件；未定义桌面“任务文件”最终范围 | 按 thread/turn 保存文件摘要、Diff、撤销和恢复；见 `test/task_file_parity_matrix_test.dart`、`test/file_change_protocol_test.dart` | 未证明官方以最新 turn、整个 thread、Git 工作树或其他组合展示 | 项目持久化已验证，产品语义未定 | 执行四轮修改/追问/旧文件/新文件流程并记录范围 |
| 审批 | App Server 定义 `item/permissions/requestApproval` 和 MCP elicitation 请求/响应 | 命令、文件变更、额外权限、MCP 表单和后台线程归属已覆盖；见 `test/approval_controller_test.dart`、`test/mcp_elicitation_controller_test.dart` | 未取得官方浮层高度、按钮顺序、自动批准视觉和焦点证据 | 协议和项目行为已验证，视觉待验收 | 对照手动、自动、拒绝、后台任务四组状态 |
| 快捷键 | App Server 不定义桌面快捷键 | `⌘L`、`⌘T`、`⌘W`、`⌘R`、`Shift+Tab`、`Esc`、`⌘N`、`⌘K` 等有项目测试 | 未取得官方快捷键作用域、输入法组合态和焦点转移证据 | 项目行为已验证，官方语义待验收 | 固定窗口和输入法状态逐项记录 |
| 智能体默认设置 | `config/read`、`config/value/write`、`config/batchWrite` 及配置来源/版本有官方协议证据 | 三态值、来源、能力探测、`expectedVersion`、连续写入和失败回滚已覆盖；见 `test/model_configuration_test.dart`、`test/codex_app_server_config_write_test.dart` | 未取得用户配置选择器、覆盖提示、保存位置和重启后的官方界面证据 | 协议和项目行为已验证，桌面边界待验收 | 在运行中、切换项目、重连、重启下实测 |
| IDE 上下文 | App Server 可接收 `additionalContext`，但不定义宿主插件 IPC | 通用 `codex_desk/ide_context` bridge 与首个独立 VS Code 宿主已交付；loopback discovery/token、编辑器事件、选区、可见 Tab、停用断连和重连已覆盖，见 `test/codex_ide_context_bridge_test.dart`、`integrations/vscode-codex-context/extension.test.js`、`tool/verify_ide_context_host_transport.dart` | 无官方桌面插件证据 | VS Code 宿主项目行为已验证，官方桌面插件语义仍未证明 | 在真实 VS Code 安装扩展并记录工作区切换、发现文件更新和真实 Codex Desk 生命周期 |

## 统一验收状态

- 已证明：项目内部协议映射、状态隔离、持久化和回归测试。
- 未证明：官方 Codex 桌面客户端的菜单顺序、视觉几何、默认文案、快捷键作用域和任务文件展示范围。
- 当前阻塞条件：CUA 能枚举其他应用，但无法选择官方 Codex 客户端窗口；没有可复核的官方桌面截图或操作记录。
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
