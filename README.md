# Codex Desk

一个以 Flutter 构建的本地优先 Codex 桌面客户端。首个目标平台是 macOS。

后续开发任务、优先级与发布前置条件见 [ROADMAP.md](ROADMAP.md)；每项工作完成后会同步更新该清单和本文档。

平台支持范围与 Windows/Linux 评估见 [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md)。

## 当前进度

- Flutter macOS 工程骨架
- 通过 `stdio` 启动 `codex app-server`
- JSON-RPC 初始化、创建线程、发起任务与中断任务的最小客户端
- 任务时间线与运行时状态界面
- 应用共享状态由 Riverpod 管理：`ProviderScope` 持有 `CodexController` 生命周期，工作区通过 Provider 订阅状态；页面临时交互状态仍保留在局部 `StatefulWidget`
- ChatGPT 浏览器登录与 OpenAI API Key 登录入口
- 命令、文件变更与额外权限的显式审批
- Provider、Base URL、凭据与默认模型均由本地 Codex App Server 按 Codex 配置层级直接读取；应用不再提供独立中转站输入。“Codex 配置”窗口展示当前项目最终生效的模型、Provider、字段来源和读取状态；输入框右下角的模型选择器可从 `model/list` 为后续新任务临时选模，也可随时恢复为“跟随配置”
- 当前工作区线程历史：列表、恢复、重命名、归档与归档视图恢复
- 对话记录、线程列表与文件 Diff 会按本地项目加密缓存到 macOS Application Support；Release 构建的加密密钥仅保存在 macOS Keychain，开发构建使用隔离的本地开发存储；启动时先恢复缓存，连接 App Server 后再同步最新状态
- 线程列表支持按标题或预览内容搜索；可将常用任务置顶，置顶状态按本地项目保存并在重启后恢复
- 可从线程区的“本地历史”菜单导出或导入可移植 JSON：导入只替换当前项目的 Codex Desk 缓存，不会伪造或恢复 App Server 原始 session，也不会修改项目文件
- 可新建并保存多个工作区，左侧栏按创建顺序以名称和路径列表展示，切换时顺序保持不变；当前项高亮，其他项可直接切换，列表标题提供独立的“新建”和“管理”入口。每个工作区独立维护一个主目录、多个附加目录和本地历史，并自动恢复及清理失效路径，不向项目目录写入配置。新建、恢复或切换工作区后会自动连接运行时；客户端会在初始化握手中声明实验性 App Server 能力，以便通过 `runtimeWorkspaceRoots` 将附加目录授权给后续新任务。目录可随时增删，已有任务不受影响
- 自动保存并恢复 macOS 主窗口的大小与位置；覆盖安装同一应用后仍会保留
- 对话时间线采用扁平消息样式并自动滚至最新内容；Enter 发送消息，Shift+Enter 换行
- 运行中任务会根据 App Server 的 `turn/plan/updated` 通知悬浮展示结构化步骤，区分待执行、进行中与已完成状态，并显示当前“第 N / M 步”；任务结束后自动收起
- 底部输入区采用深色圆角工作台样式，集中展示任务状态、审批模式、模型与推理强度，并会随窗口宽度折叠次要工具项
- 输入区“添加”菜单支持附加文件、图片和文件夹路径，显式附加当前项目，设置线程目标，切换计划模式，录制技能，以及从 App Server 动态选择项目可用技能；也可把文件或文件夹直接拖入输入卡片，在 Finder 中复制后通过 `Command+V` / `Control+V` 粘贴，或直接粘贴剪贴板中的屏幕截图；图片附件会显示缩略图，点击可在可缩放的大图预览中查看，普通文本剪贴板仍按当前光标或选区粘贴；图片、目标、计划模式和技能分别通过 Codex 原生结构化协议发送
- 已接入本地 `yeknom_ui_kit` 的 Workbench 主题入口；顶部“主题”按钮可切换跟随系统、浅色或深色模式，以及八套 UI Kit 配色预设，工作区表面与状态颜色会随主题语义色同步切换
- 任务完成后会在对话区显示文件变更摘要卡片，列出文件数与新增/删除行数，并通过“审核”打开只读代码审查窗口；窗口支持按文件查看逐行 Diff、长行横向滚动和完整任务 Diff，不提供提交或推送操作。若 App Server 未携带文件级 Diff，应用会对未跟踪文件从 Git 工作区安全补齐；无法可靠取得 Diff 时显示未知统计，不伪装成 `+0 -0`
- 右侧“文件变更”及对话区顶部入口会按 App Server 事件列出 AI 修改的文件；可展开查看每个文件与本次任务的统一 Diff，不扫描本地项目文件
- 模型与推理强度选项由 Codex App Server 动态提供；推理强度会随所选模型联动并保存，两者只用于后续新建任务，不覆盖恢复的历史任务
- 活跃与归档线程列表会跟随 App Server 分页加载，不限于首 50 条
- 提供“插件”管理入口：读取本机 Codex CLI 的已安装与可安装插件、添加本地或远程 marketplace、刷新 Git marketplace、安装/卸载及启用/停用插件；操作期间会显示具体进度与失败原因，成功后会自动重连运行时并更新生效状态；插件会展示安装策略与认证时机，OAuth/连接器授权仍由 Codex Host 在安装或首次使用时处理
- “Codex CLI”运行时窗口会展示 CLI 自动发现来源、版本与最近 stderr/协议诊断日志；日志仅在内存中保留最近 200 条，可一键复制脱敏诊断报告，不会写入对话历史
- 侧栏“Git 项目”提供只读的当前分支、暂存/未暂存/未跟踪改动摘要、按路径搜索和状态筛选的文件列表与 Diff；超大 Diff 会明确提示仅显示前 120,000 个字符；不会执行暂存、还原、提交、切分支、拉取或推送
- 线程列表支持批量归档；单个活跃或归档线程可在二次确认后永久删除，删除会同时移除 App Server 定义的派生线程，且无法恢复
- 如果 App Server 暂时返回空线程列表，活跃列表会回退读取当前项目的本地 Codex session 元数据；回退读取只解析每个文件开头的有限元数据，并按工作区合并并缓存 10 秒，服务端有结果时始终以服务端为准，归档列表不使用此回退
- 归档、恢复和永久删除操作具备重复提交防护，线程状态通知会同步刷新活跃与归档列表
- 历史线程恢复会保留原 Provider，并防止过期刷新结果污染当前列表
- 恢复线程时加载用户消息、Codex 回复与命令输出到当前时间线
- 历史 turns 支持通过 `thread/turns/list` 分页补齐；未加载的 items 会按 turn 通过 `thread/items/list` 继续恢复，并展示计划、推理摘要、文件变更及工具事件
- 历史补齐失败会保留原线程时间线；超过安全页数时保留已加载内容并提示未完全加载
- 网页搜索、MCP/动态工具、图片、等待和审查模式会以专用历史事件卡片展示
- 提供真实 App Server 历史协议验证脚本，不创建任务或修改所选工作区文件

## 运行

开发与 CI 使用 Flutter 3.47.1（Dart 3.13.1）；项目最低 Dart 约束为 3.11.4。macOS 构建的最低系统版本为 macOS 12.0。

```bash
flutter run -d macos
```

Debug 与 Profile 构建使用独立的 `Codex Desk Development` Application Support 目录保存开发偏好和缓存，不访问 macOS Keychain，避免临时签名变化导致每次 `flutter run` 重复请求钥匙串密码。Release 构建仍使用 Keychain，并与开发数据隔离。

应用使用已安装的 `codex` 命令。在“工作区”窗口点击“新建工作区”并选择主目录后会自动连接运行时；之后可继续新建并切换其他工作区，也可为当前工作区添加多个附加目录。完成 Codex 登录后即可发起任务。界面不提供日常的运行时启动和停止操作。

### 运行时连接与恢复

Codex Desk 将 App Server 连接作为应用内部生命周期管理：启动时若恢复到有效工作区会自动连接；新建或切换工作区、修改 Codex CLI 路径以及插件配置成功变更后，也会自动建立或重建连接。附加目录的增删不重启运行时，只会影响之后新建的任务。工作区列表保存在应用偏好中；从列表移除只会删除该记录，不会删除磁盘目录或对应的本地历史缓存。

运行时启动失败或进程意外退出时，应用会按 1 秒、2 秒、5 秒的有限退避最多自动重试三次，并在时间线显示等待和失败原因，避免持续重启。修复 CLI 或配置后，可在“Codex CLI”窗口重新检测以立即恢复连接。单个任务返回失败只会结束该任务并保留错误信息，不会把仍然可用的 App Server 连接标记为失败。

运行时启动、停止和应用退出使用连接代次隔离异步结果：已被替换或取消的旧启动流程不能回写新连接状态，进程若已创建则会立即回收。附加工作区目录使用不可变快照串行保存，连续增删时较慢的旧写入不会覆盖较新的目录集合。

### 安装到 Applications

在项目根目录运行以下脚本会在应用源码发生变化时构建 Release 版本；随后会先正常关闭正在运行的 Codex Desk、替换 `/Applications/Codex Desk.app`，再启动新版本。如果 macOS Automation 权限或应用状态导致正常退出请求被取消，脚本会静默回退，仅终止该安装包的进程后继续安装。若源码未变，则会重启已安装版本，避免临时签名重新覆盖后重复触发 macOS Keychain 授权。仅当当前账户对 `/Applications` 没有写权限时，macOS 才会要求输入管理员密码。

```bash
./install_macos.sh
```

如需只构建、不安装或启动，可运行 `./install_macos.sh --build-only`。如需使用既有的 Release 构建重新安装而不重新编译，可运行 `./install_macos.sh --install-only`。

### 生成 DMG

以下命令会构建 Release 应用并生成未签名 DMG；不会启动应用。默认输出为 `dist/Codex-Desk-<version>.dmg`，版本来自 `pubspec.yaml`。

```bash
./build_dmg.sh
```

可使用 `./build_dmg.sh --output /absolute/path/Codex-Desk.dmg` 指定输出路径。提供 Developer ID 和已保存到 Keychain 的 `notarytool` profile 后，可直接生成签名、公证并装订的 DMG：

```bash
./build_dmg.sh \
  --sign-identity "Developer ID Application: Example (TEAMID)" \
  --notary-profile "codex-desk-notary"
```

也可通过 `CODEX_DESK_SIGN_IDENTITY` 与 `CODEX_DESK_NOTARY_PROFILE` 环境变量传入。脚本会依次执行 `codesign` 验证、Apple notarization、staple 验证和 Gatekeeper 评估。发布步骤及干净 macOS 安装回归见 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)；当前仓库尚不包含 Apple Developer 证书或 notarization 凭据。

## App Server 历史验证

在有历史线程的工作区执行以下命令，可验证真实 App Server 的初始化、线程列表、恢复和全部 turns 分页协议；脚本不会创建任务、发送消息或修改工作区文件。

```bash
dart run tool/verify_app_server_history.dart --cwd /path/to/workspace
```

也可以用 `--thread-id <id>` 明确指定待验证的历史线程。若工作区暂无历史，脚本仅验证初始化与线程列表。

## 本地历史导入与导出

在线程区点击归档图标打开“本地历史”菜单，可执行以下操作：

- “导出本地历史”：将当前项目的线程列表、置顶状态、已缓存对话和文件 Diff 写入 JSON 文件。
- “导入到当前项目”：读取此前导出的 JSON，并替换当前项目在 Codex Desk 中的本地缓存。

导出文件不含 API Key、Keychain 内容或 Codex App Server 原始 session；但它包含对话文本和 Diff，文件本身为了可移植性未加密，请仅存放在可信位置。导入不会发送请求、恢复远端任务或修改项目文件；连接 App Server 后，服务端线程列表仍是权威来源。

## 运行时诊断

在侧栏点击“Codex CLI”可打开运行时窗口。窗口会重新探测当前 CLI，展示自动发现策略、解析到的可执行文件和版本；最近的 App Server stderr 与无法解析的协议行会以信息、警告或错误级别显示。使用“复制诊断”或“导出诊断”可生成包含运行状态、CLI 检测结果、`CODEX_HOME` 是否已配置以及最近日志的文本，适合贴到问题反馈中。导出时会再次生成脱敏文本，并仅写入你在系统文件选择器中指定的位置。

日志最多保留 200 条，重启本地运行时时会清空，且不会保存到历史缓存或项目文件。复制与展示前会完整隐藏 `Authorization: Bearer ...` 和 `Authorization: Basic ...` 凭据、`sk-` Key 以及 `api_key`、`token`、`secret`、`password` 等常见凭据字段；仍应在分享前自行检查诊断文本是否含有不希望公开的项目或环境信息。

## Git 项目视图

选择本地项目后，Codex Desk 会读取其 Git 工作区状态；点击侧栏“Git 项目”可手动刷新。视图显示当前分支（分离 HEAD 时显示 `DETACHED`）、暂存/未暂存/未跟踪改动数量，以及每个改动文件的状态和 Diff。未跟踪文件的 Diff 以 `/dev/null` 为基准预览；过大的 Diff 会被截断以避免占用过多内存。

此阶段刻意限制为只读：内部仅调用 `git rev-parse`、`git branch --show-current`、`git status` 与 `git diff`，并始终禁用 Shell。应用不提供或自动执行任何会改写 Git 状态的操作。后续若加入提交、分支、拉取或推送，都会要求用户显式触发和确认。

## 安全边界

- 应用不保存自定义 Provider 的 Base URL 或 API Key，也不接受任意模型文本；这些内容由本地 Codex App Server 从 Codex 配置、环境变量或其认证存储读取。应用只保存用户从 App Server 模型目录中选择的模型 ID 与推理强度偏好。账户窗口临时提交的 OpenAI API Key 仅交给本地 Codex 运行时。
- Release 构建在 macOS Application Support 内的本地历史缓存会用 Keychain 密钥加密；Debug 与 Profile 构建的密钥和缓存位于隔离的 `Codex Desk Development` 目录，不应作为安全存储。手动导出的历史 JSON 为便于跨设备或备份恢复而保持明文，因此可能包含敏感对话和 Diff。
- App Server stderr 和协议诊断只会作为有上限的内存记录展示；不会进入历史缓存、项目文件或应用日志。运行时诊断复制内容会套用凭据脱敏规则，但任何诊断文本都应仅分享给可信对象。
- Git 项目视图为只读，且通过不使用 Shell 的受限 Git 子命令读取状态和 Diff；会显式读取全部未跟踪文件，不受用户 Git 的 `status.showUntrackedFiles` 配置影响；不会自动修改暂存区、工作区、分支或远端。
- 运行时只通过本机 `stdio` JSON-RPC 通信；不会启用远程 WebSocket。
- 审批默认逐次确认；可在“变更与审批”切换为自动批准。自动模式会直接允许命令、文件变更与额外权限请求，并在时间线留下记录。
- Codex App Server 按官方优先级解析 CLI 覆盖、受信任项目的 `.codex/config.toml`、选中的 profile、用户级 `$CODEX_HOME/config.toml`（默认 `~/.codex/config.toml`）、系统配置与内置默认值。本应用通过只读 `config/read` 获取最终生效的模型、Provider 和来源，不自行解析或覆盖 Provider 设置；“已读取”不代表凭据和网络已验证，仍需成功创建一次任务才能确认。修改外部配置后重新打开应用即可自动连接并读取最新值。
- 自定义 Provider 使用 `env_key` 时，对应环境变量必须对启动本应用的进程可见；也可使用 Codex 支持的其他认证来源。macOS 桌面构建不启用 App Sandbox，以便启动本机 `codex` 并读取其配置。运行时路径和本地历史加密密钥仍使用标准 macOS Keychain 保存。
- 插件管理会调用本机 `codex plugin` 子命令，并仅修改当前 Codex Home（优先 `CODEX_HOME`，否则 `~/.codex`）配置中相应插件的 `enabled` 状态；配置写入会串行化，并以同目录临时文件原子替换，且会保留 TOML 行尾注释；请只添加和安装可信来源的 marketplace 与插件。

## 开发约定

- 项目中的 Dart 方法均使用 Dartdoc 双语注释：先说明中文职责，再给出对应英文说明；公开方法还会说明重要的参数、返回值或副作用。
- 注释描述当前行为与边界，不记录实现过程；修改方法行为时，必须同步更新其双语注释与本 README。
- 应用范围状态从 `codexControllerProvider` 读取；新页面应优先使用 Riverpod 的 `ref.watch` / `ref.read`。`CodexController` 目前保留 `ChangeNotifier` 以桥接既有业务状态与异步服务，显式注入控制器仅用于测试或嵌入式场景。
- 提交前依次运行 `dart format`、`flutter analyze` 与 `flutter test`；涉及 macOS 集成时，再运行 `flutter build macos --debug`。

### 本地 UI Kit

项目将 `yeknom_ui_kit` 固定到 Git 仓库的已验证提交，开发机和 CI 使用同一来源。桌面工具应从 `package:yeknom_ui_kit/yeknom_workbench.dart` 导入，并使用 `YeknomWorkbenchTheme`，避免复制主题 Token 或硬编码新的全局主题配置。

### 持续集成

GitHub Actions 会在 macOS 上使用 Flutter 3.47.1 执行格式检查、`flutter analyze`、`flutter test` 和 macOS Debug 构建。UI Kit 由 `pubspec.lock` 固定 Git 提交，不需要 CI 访问开发机目录。

## 参考

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
