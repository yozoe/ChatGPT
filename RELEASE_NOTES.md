# Codex Desk Release Notes

## Unreleased

- 收紧 Composer 默认输入文字至 14px，并将圆形发送按钮从 40px 缩小至 36px，保持上箭头居中和既有发送语义。
- 项目栏的紧凑“新建、刷新、本地历史”图标已替换为 Codex 风格的“新对话、拉取请求、已安排、插件”入口。拉取请求、已安排和插件现在会切换为独立右侧工作区：PR 页提供 GitHub CLI 安装提示、命令复制和 Git 项目入口；已安排页提供搜索、推荐模板、创建与取消；插件页提供搜索、已安装项、marketplace 管理、安装与刷新。已安排任务可保存提示词与时间，在 Codex Desk 保持运行时自动切换回对应项目并创建新对话发送。待执行项会跨重启保留，任务运行中或运行时不可用时会等待重试，不会打断当前工作。
- 插件工作区现可在“插件”和“技能”间切换；技能页展示 App Server 为当前项目提供的真实技能，并按个人/项目与系统范围分组。右上角“添加”菜单新增创建插件、添加插件市场和录制技能：创建插件会在新对话预填 `$plugin-creator`，录制技能会在新对话直接启用结构化录制上下文；市场表单支持 GitHub 仓库、Git URL 与本地目录，Git 引用继续使用 Codex CLI 的默认解析。
- 修复取消已安排任务时的竞态：若任务正等待项目切换或运行时重连，取消后不会继续创建新对话或发送提示词。
- 左侧项目树不再常驻显示任务搜索框；顶部搜索图标现在会打开与 Codex 桌面端一致的“搜索聊天”面板，可跨已加载项目按任务标题、预览、项目或 Provider 查找并恢复任务，同时提供新聊天、打开文件夹和文件变更搜索快捷操作。
- 修复新建任务或切换历史任务后，旧任务迟到的生命周期和计划通知可能写入当前视图的问题；项目详情卡片的任务数现在每次打开都会刷新。
- 修复文件变更统计将仅含 Diff 头、二进制或元数据的不可计数变更显示为 `+0 -0` 的问题；现在会明确显示 `+? -?`。
- 修复连续切换任务时，已打开任务会因完成状态延迟刷新而重新显示蓝色完成提醒的问题。
- 任务名称、Provider / App Server、沙箱边界和文件变更入口现在位于右侧工作台顶部；任务名称显示当前任务，点击后可行内修改，Enter 保存、Esc 取消。
- 工作区改为左右两列主结构：左侧项目列和右侧工作台列现在各自拥有独立顶部栏；宽屏下的环境信息继续保留在工作台内，原有 Git 与文件变更操作不受影响。
- 收紧右侧“环境信息”卡片的字号：标题、操作行、分组和文件行分别使用 18/14/14/13px，提升窄侧栏的信息密度。
- 修复耗时条目新增后未处理其时间线展示类型导致应用无法编译的问题。
- 修复插件 CLI 路径解析未受超时限制的问题：自动发现路径与插件命令现在均在 20 秒后超时，避免插件页持续加载。
- 修复插件管理在桌面应用 `PATH` 中找不到 `codex` 时无法加载列表的问题：插件命令现在复用运行时自动发现的 CLI 绝对路径。
- 收紧任务完成后文件变更摘要的标题和新增/删除行统计字号，避免其在对话流中显得过大。
- 收紧侧栏选中任务与任务搜索框的垂直内边距，列表扫描时不再显得过于松散。
- 对话时间线现在会显示正在运行的 Codex 命令；命令完成后自动收纳到既有活动清单，不会把持续刷新的命令输出展开成终端日志。每轮任务结束后会保留“已处理”耗时，恢复历史任务时同样可见。
- 修复已恢复任务的后台或迟到生命周期事件可能覆盖当前任务状态的问题：它们现在只刷新任务列表，不会清除当前命令/计划、写入错误耗时或污染文件变更与 Diff。
- 修复开发版工作区可能错误保存 macOS 系统临时目录的问题：测试不再写入真实偏好，应用会拒绝该目录作为项目或附加目录，并在启动恢复时自动移除既有记录。
- 所有 tooltip、项目详情卡片和文件 Diff 悬停预览现在都会在持续悬停 450ms 后显示，快速掠过控件或文件行不再弹出干扰操作的浮层。
- 修复侧栏跨项目任务预览：其他项目的缓存任务现在会先切换到所属项目并重连运行时再恢复，不能误在当前项目中继续、置顶、归档、重命名或删除。
- 文件变更协议记录不再逐条占据会话：实时与历史会话中的旧记录都会隐藏，文件数、增删行数和 Diff 仍会通过任务完成摘要、右侧检查器与“审核”入口提供。
- 修复展开多个项目后，其他项目的缓存任务会错误继承当前任务选中态与 loading 的问题；这两种状态现在只显示在当前项目。
- 修复任务运行中项目侧栏的“新建任务”按钮仍可点击的问题：按钮现在会禁用，避免显示与实际状态不符的“运行时就绪后才能新建任务”提示；完成或停止当前任务后即可新建。
- 侧栏项目树在每次启动时都会恢复并默认展开所有项目的本地任务列表；项目切换不再造成其他列表收起。需要收起时请点击项目行中的展开/收起按钮，该状态仅影响当前会话。
- 统一应用状态管理：主题偏好改由 Riverpod 持有并持久化，实时弹窗统一订阅共享控制器；局部表单、悬停、拖拽和滚动状态仍由对应 Widget 管理，用户可见行为保持不变。
- 切换侧栏任务时，首次加载会显示 Codex 风格历史加载页并缓存最近 8 个已打开任务的完整时间线页面和滚动位置；再次切换同一任务会直接显示已保活页面，任务切换和实时回复的自动定位均不再出现平滑滚动或文字随滚动出现的过渡，超出上限的较早任务会重新读取历史；历史读取失败时不会显示前一任务内容。
- 修复对话文字区域各自创建滚动容器的问题：文本仍可选择复制，但滚轮始终驱动整条对话时间线，不再出现嵌套滚动造成的文字出现过渡。
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
- 文件变更统计提示现悬浮在输入框顶缘，展示“X 个文件已更改”及新增/删除行数，不再占用独立布局高度；无法取得 Diff 时显示未知统计。
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
