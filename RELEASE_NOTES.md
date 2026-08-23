# Codex Desk Release Notes

## Unreleased

- 统一应用状态管理：主题偏好改由 Riverpod 持有并持久化，实时弹窗统一订阅共享控制器；局部表单、悬停、拖拽和滚动状态仍由对应 Widget 管理，用户可见行为保持不变。
- 切换侧栏项目时，已访问项目的任务列表会保留展开状态，不再收起之前项目的任务。
- 随任务发送的图片现在会显示在对话时间线的用户消息气泡中；剪贴板生成的临时图片在时间线仍引用时不会因任务完成而提前删除。
- 已完成任务的蓝色提醒现在表示“未查看的完成结果”；打开对应任务后会自动清除提醒。
- 修复“变更与审批”中的审批模式未在重启后恢复的问题；选择“帮我批准”后，后续启动会继续自动批准命令、文件变更与额外权限请求。
- 左侧任务栏与右侧环境栏现在可通过分隔条拖拽调整宽度；悬停和拖动会提供主题强调色反馈，窄窗口仍会自动隐藏右侧栏。
- 连续的历史命令、文件读取和工具调用现在会以默认展开的 Codex 风格活动清单显示；点击摘要可折叠或展开，单项保留完整事件详情提示。
- 右侧检查器改为 Codex 风格的“环境信息”圆角卡片，接入本地 Git 变更、分支、提交/推送、创建拉取请求和比较分支入口；Git 视图新增文件级暂存、二次确认后的还原、显式提交和推送，以及通过本机 `gh` CLI 创建 PR。
- Codex 回复现按 GitHub Flavored Markdown 显示，列表、加粗、链接、引用、表格与代码块不再展示原始标记；内容仍可选择复制，用户输入、命令和系统记录继续以纯文本显示。
- 修复对话时间线误把 App Server 命令输出增量等协议级执行事件显示为“执行事件”的问题；这些高频内部通知现已隐藏，审批、任务结果和恢复历史中的实际命令记录不受影响。
- 修复项目独立历史升级后的缓存迁移：若项目 ID 已写入但历史仍按旧目录索引保存，应用会恢复该缓存并立即迁移，避免重启后历史任务显示为空。
- 修复加密本地历史保存覆盖其他项目缓存的问题，并串行化历史迁移与常规保存，避免切换项目或并发保存后历史丢失。
- 修复新建项目误显示同一源目录历史任务的问题：项目现在拥有独立任务归属，新项目从空任务列表开始，后续创建的任务仅显示在所属项目中。
- 新建项目改为 Codex 风格弹窗：项目名称可选，源文件夹区域支持点击打开目录选择器，也支持直接拖入目录后创建项目。
- 项目菜单的“编辑”改为 Codex 桌面端风格的项目编辑器：支持编辑项目显示名称、管理源文件夹、添加/移除附加文件夹、取消或保存，以及移除当前本地项目记录；移除操作不会删除磁盘目录或历史缓存。
- 修复项目编辑器名称输入框的重复边框；外层项目字段保留单层边框，聚焦时不再显示主题注入的内层边框。
- 优化任务 Composer：移除随心输入、模型选择和推理强度控件的额外边框，推理强度按钮与菜单改为仅显示“默认”“高”“中”“低”等强度名称。
- 在任务完成后显示文件变更摘要卡片，并提供只读代码审查窗口：可按文件查看逐行 Diff、统计新增/删除行数和浏览长代码行。
- 当 App Server 只返回文件路径而未携带文件级 Diff 时，对未跟踪文件通过 Git 工作区只读预览补齐；无法可靠取得 Diff 时显示未知统计，避免误报 `+0 -0`。
- 审查窗口中的完整任务 Diff 不计入文件数量，单个文件 Diff 读取失败也不会阻断其他文件的预览。
- 已编辑文件摘要支持悬停预览：预览会避开窗口边缘、显示 unified Diff 的实际行号，并在文件 Diff 异步补齐或更新后同步刷新。
- 输入区上方新增文件变更统计提示条，展示“X 个文件已更改”及新增/删除行数；无法取得 Diff 时显示未知统计。
- 运行中任务支持从最新用户消息进入“调整方向”；运行期间 Composer 保持可编辑，修正指令通过 `turn/steer` 发送到当前活动 turn，停止按钮继续用于中断任务。
- 修复运行中调整方向误清空附件上下文、成功后输入框残留文本，以及 steering 后未沿用服务端返回 turn ID 的问题；运行期间现在可以继续附加文件、图片、文件夹、技能、目标和计划上下文。
- 修复 App Server 暂时返回空线程列表时历史任务无法自动恢复并导致输入区锁死的问题；应用会保留本地缓存线程作为恢复候选，并等待历史缓存加载完成后再连接运行时。
- 左侧导航调整为 Codex 风格的项目树布局：工作区使用文件夹节点，任务作为文件缩进排列，选中任务显示低对比圆角背景；悬停项目自动展示目录、当前或本地缓存任务数和路径详情卡片，详情卡片支持持久化项目置顶，点击更多按钮可打开置顶、编辑、创建永久工作树、归档聊天和移除项目菜单，点击新建任务按钮会开始新的任务，任务运行中会在当前任务行尾显示加载指示器，任务完成显示蓝色信息点，任务错误显示红色叹号。
- 修复运行中任务在侧栏缺少状态反馈的问题：当前任务现在显示更醒目的加载指示器并可点击保持焦点；新线程在 App Server 列表同步前也会保留在侧栏，避免运行中的任务行暂时消失。

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
