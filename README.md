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
- 当前工作区线程历史：列表、恢复、重命名与归档
- 历史线程恢复会保留原 Provider，并防止过期刷新结果污染当前列表
- 恢复线程时加载用户消息、Codex 回复与命令输出到当前时间线

## 下一阶段

- 为历史 turns/items 增加分页与完整 item 类型展示
- 增加真实 App Server 进程下的历史恢复端到端验证

## 运行

```bash
flutter run -d macos
```

应用使用已安装的 `codex` 命令。选择本地项目、点击“启动运行时”，完成 Codex 登录后即可发起任务。

## 安全边界

- 不会在项目文件、应用日志或界面中保存 API Key；密钥仅提交给本地 Codex 运行时。
- 运行时只通过本机 `stdio` JSON-RPC 通信；不会启用远程 WebSocket。
- 审批默认逐次确认；不会在后台自动批准命令、文件变更或额外权限。
- 中转站仅接受 HTTPS（localhost 可用 HTTP），并要求 Responses API 与 SSE 流式协议兼容。密钥存入 macOS Keychain，Provider 定义仅注入本应用创建的 Thread，不修改 `~/.codex/config.toml`。

## 参考

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
