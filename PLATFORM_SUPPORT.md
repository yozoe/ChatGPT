# 平台支持评估

## 当前支持

Codex Desk 当前仅支持 macOS 12.0 及以上版本。它依赖 macOS Keychain 保存本地历史加密密钥和应用偏好，并使用 macOS 原生窗口状态保存和 Applications/DMG 安装流程；Provider 凭据由 Codex 自身的配置与认证存储管理。

## Windows 评估

可复用 Flutter/Dart 的界面、App Server stdio、历史缓存格式、Git 只读服务和插件 CLI 调用。开始开发前需要完成：

- 将 Keychain 存储替换为 Windows Credential Manager，并验证 `flutter_secure_storage` 的桌面实现与加密恢复行为。
- 增加 MSIX 或安装程序构建流程，替代 DMG 和 Applications 安装脚本。
- 在 Windows Git、路径分隔符、PowerShell/CLI PATH 与文件选择器上补充回归测试。
- 检查 Codex CLI 的 Windows 安装、插件 marketplace 与 `CODEX_HOME` 行为是否一致。

## Linux 评估

可复用的应用层与 Windows 基本相同；发行版差异更大。开始开发前需要完成：

- 明确 Secret Service / libsecret 可用性、无钥匙环环境下的降级提示与加密密钥迁移策略。
- 选择 AppImage、deb、rpm 或 Flatpak 的发布方式，并建立对应签名与更新流程。
- 验证 Wayland/X11 窗口几何恢复、文件选择器、`git` 与 Codex CLI 自动发现。
- 在至少一个 Debian/Ubuntu 与一个 Fedora 系环境完成安装回归。

## 结论

云端 CI 已可通过固定 Git 提交获取 `yeknom_ui_kit`。在 macOS 正式发布并完成无障碍回归前，仍不启动 Windows/Linux 实现；跨平台工作应新建独立阶段，避免改变现有 macOS 的 Keychain 安全边界。
