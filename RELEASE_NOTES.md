# Codex Desk Release Notes

## Unreleased

- 在任务完成后显示文件变更摘要卡片，并提供只读代码审查窗口：可按文件查看逐行 Diff、统计新增/删除行数和浏览长代码行。
- 当 App Server 只返回文件路径而未携带文件级 Diff 时，对未跟踪文件通过 Git 工作区只读预览补齐；无法可靠取得 Diff 时显示未知统计，避免误报 `+0 -0`。
- 审查窗口中的完整任务 Diff 不计入文件数量，单个文件 Diff 读取失败也不会阻断其他文件的预览。
- 已编辑文件摘要支持悬停预览：预览会避开窗口边缘、显示 unified Diff 的实际行号，并在文件 Diff 异步补齐或更新后同步刷新。
- 输入区上方新增文件变更统计提示条，展示“X 个文件已更改”及新增/删除行数；无法取得 Diff 时显示未知统计。
- 运行中任务支持从最新用户消息进入“调整方向”；运行期间 Composer 保持可编辑，修正指令通过 `turn/steer` 发送到当前活动 turn，停止按钮继续用于中断任务。
- 修复运行中调整方向误清空附件上下文、成功后输入框残留文本，以及 steering 后未沿用服务端返回 turn ID 的问题；运行期间附件、目标、计划模式和技能上下文入口会暂时禁用。
- 修复 App Server 暂时返回空线程列表时历史任务无法自动恢复并导致输入区锁死的问题；应用会保留本地缓存线程作为恢复候选，并等待历史缓存加载完成后再连接运行时。

## 1.0.0+1

Initial macOS release.

- Connect to the local Codex App Server and manage tasks, approvals, plugins, and workspace threads while using Codex-native model and provider configuration.
- Automatically connect restored workspaces, keep the runtime usable after a failed task, and recover startup failures or unexpected process exits with bounded 1/2/5-second retries.
- Create, retain, switch, and forget multiple workspaces, with independent primary/additional directories and local history for each entry.
- Negotiate the App Server experimental API capability required to pass additional workspace roots when starting a task.
- Show saved workspaces directly in the sidebar with stable creation order, a distinct active state, one-click switching, bounded scrolling, and separate create/manage actions.
- Cancel stale in-flight runtime startups safely during reconnect or disposal, and serialize additional-workspace persistence so older writes cannot replace newer directory selections.
- Keep encrypted local conversation history, restore workspace preferences, and provide a read-only Git change view.
- Include runtime diagnostics with credential redaction, API Key / browser sign-in, effective model/provider values and sources read from Codex configuration, and configurable reasoning effort.
- Select a model for subsequent new tasks from the App Server catalog, keep a follow-configuration option, and update reasoning-effort choices to match the selected model without overriding historical threads.
- Show live structured task plans in a floating step-progress panel with pending, active, and completed states.
- Add a reference-matched composer menu for files, folders, workspace context, persistent goals, plan mode, skill recording, and workspace-scoped App Server skills, plus ChatGPT-style desktop file dropping, Finder file/folder pasting, and clipboard screenshot pasting with thumbnail and zoomable preview support, deduplicated attachment chips, and normal text paste preservation.
- Make in-place macOS installs resilient to cancelled Automation quit requests, and request administrator privileges only when `/Applications` is not writable.
- Use Riverpod for application-level controller ownership and workspace state subscriptions, while preserving safe test and embedded-controller injection.
- Support batch archive and confirmed permanent task deletion with duplicate-submission protection.
- Package the Release application with `./build_dmg.sh`; unsigned output remains the default while Developer ID credentials are unavailable.
- Search and filter read-only Git changes, with an explicit warning when a large Diff preview is truncated.
- Show plugin-operation progress, actionable CLI failure details, and persistent runtime-restart feedback.
- Resolve `yeknom_ui_kit` from a pinned Git commit and verify formatting, analysis, tests, and the macOS Debug build in GitHub Actions.
- Support Developer ID signing, notarization, stapling, and Gatekeeper assessment in `build_dmg.sh` when release credentials are supplied.
- Align local development and CI on Flutter 3.47.1 / Dart 3.13.1 and migrate the macOS project to the Flutter-supported macOS 12.0 deployment target.
