# Codex Desk

一个以 Flutter 构建的本地优先 Codex 桌面客户端。首个目标平台是 macOS。

## 当前进度

- Flutter macOS 工程骨架
- 通过 `stdio` 启动 `codex app-server`
- JSON-RPC 初始化、创建线程、发起任务与中断任务的最小客户端
- 任务时间线与运行时状态界面
- ChatGPT 浏览器登录与 OpenAI API Key 登录入口
- 命令、文件变更与额外权限的显式审批
- OpenAI Responses API 兼容中转站：模型、Base URL 与 macOS Keychain 密钥管理
- 已配置中转站 API Key 时，无需额外完成 OpenAI 账户登录即可发送任务
- 当前工作区线程历史：列表、恢复、重命名、归档与归档视图恢复
- 对话记录、线程列表与文件 Diff 会按本地项目加密缓存到 macOS Application Support；加密密钥仅保存在 macOS Keychain，启动时先恢复缓存，连接 App Server 后再同步最新状态
- 线程列表支持按标题或预览内容搜索；可将常用任务置顶，置顶状态按本地项目保存并在重启后恢复
- 可从线程区的“本地历史”菜单导出或导入可移植 JSON：导入只替换当前项目的 Codex Desk 缓存，不会伪造或恢复 App Server 原始 session，也不会修改项目文件
- 自动保存并恢复最近选择的本地项目路径，不向项目目录写入配置
- 自动保存并恢复 macOS 主窗口的大小与位置；覆盖安装同一应用后仍会保留
- 对话时间线采用扁平消息样式并自动滚至最新内容；Enter 发送消息，Shift+Enter 换行
- 底部输入区采用深色圆角工作台样式，集中展示任务状态、审批模式、模型与推理强度，并会随窗口宽度折叠次要工具项
- 已接入本地 `yeknom_ui_kit` 的 Workbench 主题入口；顶部“主题”按钮可切换跟随系统、浅色或深色模式，以及八套 UI Kit 配色预设，工作区表面与状态颜色会随主题语义色同步切换
- 右侧“文件变更”及对话区顶部入口会按 App Server 事件列出 AI 修改的文件；可展开查看每个文件与本次任务的统一 Diff，不扫描本地项目文件
- 推理强度选项由当前 Codex 模型能力动态提供；选择会保存，并用于后续新建或恢复的任务
- 活跃与归档线程列表会跟随 App Server 分页加载，不限于首 50 条
- 提供“插件”管理入口：读取本机 Codex CLI 的已安装与可安装插件、添加本地或远程 marketplace、刷新 Git marketplace、安装/卸载及启用/停用插件；插件会展示安装策略与认证时机，OAuth/连接器授权仍由 Codex Host 在安装或首次使用时处理；变更后需重启运行时并新建任务才会生效
- 如果 App Server 暂时返回空线程列表，活跃列表会回退读取当前项目的本地 Codex session 元数据；回退读取只解析每个文件开头的有限元数据，并按工作区合并并缓存 10 秒，服务端有结果时始终以服务端为准，归档列表不使用此回退
- 归档恢复操作具备重复提交防护，线程状态通知会同步刷新活跃与归档列表
- 历史线程恢复会保留原 Provider，并防止过期刷新结果污染当前列表
- 恢复线程时加载用户消息、Codex 回复与命令输出到当前时间线
- 历史 turns 支持通过 `thread/turns/list` 分页补齐；未加载的 items 会按 turn 通过 `thread/items/list` 继续恢复，并展示计划、推理摘要、文件变更及工具事件
- 历史补齐失败会保留原线程时间线；超过安全页数时保留已加载内容并提示未完全加载
- 网页搜索、MCP/动态工具、图片、等待和审查模式会以专用历史事件卡片展示
- 提供真实 App Server 历史协议验证脚本，不创建任务或修改所选工作区文件

## 运行

```bash
flutter run -d macos
```

应用使用已安装的 `codex` 命令。选择本地项目、点击“启动运行时”，完成 Codex 登录后即可发起任务。

### 安装到 Applications

在项目根目录运行以下脚本会构建 Release 版本、替换 `/Applications/Codex Desk.app` 并启动应用。写入 `/Applications` 时 macOS 会要求输入管理员密码。

```bash
./install_macos.sh
```

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

## 安全边界

- 不会在项目文件、应用日志或界面中保存 API Key；密钥仅提交给本地 Codex 运行时。
- macOS Application Support 内的本地历史缓存会用 Keychain 密钥加密；手动导出的历史 JSON 为便于跨设备或备份恢复而保持明文，因此可能包含敏感对话和 Diff。
- 运行时只通过本机 `stdio` JSON-RPC 通信；不会启用远程 WebSocket。
- 审批默认逐次确认；可在“变更与审批”切换为自动批准。自动模式会直接允许命令、文件变更与额外权限请求，并在时间线留下记录。
- 中转站仅接受 HTTPS（localhost 可用 HTTP），并要求 Responses API 与 SSE 流式协议兼容。密钥存入 macOS Keychain，Provider 定义仅注入本应用创建的 Thread，不修改 `~/.codex/config.toml`。
- macOS 桌面构建不启用 App Sandbox：客户端需要启动本机 `codex` 并读取其 `~/.codex` 配置。中转站凭据与运行时路径仍使用标准 macOS Keychain 保存，不依赖本地 ad-hoc 签名无法提供的 Data Protection Keychain entitlement。
- 插件管理会调用本机 `codex plugin` 子命令，并仅修改当前 Codex Home（优先 `CODEX_HOME`，否则 `~/.codex`）配置中相应插件的 `enabled` 状态；会保留 TOML 行尾注释，请只添加和安装可信来源的 marketplace 与插件。

## 开发约定

- 项目中的 Dart 方法均使用 Dartdoc 双语注释：先说明中文职责，再给出对应英文说明；公开方法还会说明重要的参数、返回值或副作用。
- 注释描述当前行为与边界，不记录实现过程；修改方法行为时，必须同步更新其双语注释与本 README。
- 提交前依次运行 `dart format`、`flutter analyze` 与 `flutter test`；涉及 macOS 集成时，再运行 `flutter build macos --debug`。

### 本地 UI Kit

开发环境通过 path dependency 使用 `/Volumes/External HD/Code/private/yeknom-ui-kit`；桌面工具应从 `package:yeknom_ui_kit/yeknom_workbench.dart` 导入，并使用 `YeknomWorkbenchTheme`，避免复制主题 Token 或硬编码新的全局主题配置。

## 参考

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
