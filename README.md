# Codex Desk

一个以 Flutter 构建的本地优先 Codex 桌面客户端。首个目标平台是 macOS。

## 当前进度

- Flutter macOS 工程骨架
- 通过 `stdio` 启动 `codex app-server`
- JSON-RPC 初始化、创建线程、发起任务与中断任务的最小客户端
- 任务时间线与运行时状态界面

## 运行

```bash
flutter run -d macos
```

应用使用已安装的 `codex` 命令。选择本地项目、点击“启动运行时”，完成 Codex 登录后即可发起任务。

## 安全边界

- 不会在应用内保存或显示 API Key。
- 运行时只通过本机 `stdio` JSON-RPC 通信；不会启用远程 WebSocket。
- 当前版本仅建立协议闭环；Provider 管理、Keychain、文件 Diff 和审批操作会在后续阶段加入。

## 参考

- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
