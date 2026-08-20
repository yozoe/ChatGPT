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
- 自动保存并恢复最近选择的本地项目路径，不向项目目录写入配置
- 自动保存并恢复 macOS 主窗口的大小与位置；覆盖安装同一应用后仍会保留
- 对话时间线采用扁平消息样式并自动滚至最新内容；Enter 发送消息，Shift+Enter 换行
- 可选默认、低、中、高和极高推理强度；选择会保存，并用于后续新建或恢复的任务
- 活跃与归档线程列表会跟随 App Server 分页加载，不限于首 50 条
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

## 安全边界

- 不会在项目文件、应用日志或界面中保存 API Key；密钥仅提交给本地 Codex 运行时。
- 运行时只通过本机 `stdio` JSON-RPC 通信；不会启用远程 WebSocket。
- 审批默认逐次确认；可在“变更与审批”切换为自动批准。自动模式会直接允许命令、文件变更与额外权限请求，并在时间线留下记录。
- 中转站仅接受 HTTPS（localhost 可用 HTTP），并要求 Responses API 与 SSE 流式协议兼容。密钥存入 macOS Keychain，Provider 定义仅注入本应用创建的 Thread，不修改 `~/.codex/config.toml`。
- macOS 桌面构建不启用 App Sandbox：客户端需要启动本机 `codex` 并读取其 `~/.codex` 配置。中转站凭据与运行时路径仍使用标准 macOS Keychain 保存，不依赖本地 ad-hoc 签名无法提供的 Data Protection Keychain entitlement。

## 参考

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
