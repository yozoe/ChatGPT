# Codex Desk 文档索引

本文档是项目文档的分类入口。辅助文档统一放在 `docs/` 目录；仓库根目录仅保留项目入口、路线图、发布记录和协作约定。

## 状态定义

- **已交付**：实现已合入，文档描述当前行为或已验证的契约。
- **进行中**：已有部分实现，仍有明确的用户可见能力或验收工作未完成。
- **待开发**：方案或规格已经形成，但对应能力尚未实现；开发前应先在 `ROADMAP.md` 建立任务。
- **参考 / 基线**：用于记录证据、平台结论或设计基线，不直接代表开发承诺。
- **发布维护**：发布、变更记录和日常维护流程。

## 待开发与进行中文档（优先关注）

这些文档描述尚未完全交付的能力，是后续开发前的主要入口。状态以实现为准，不以文档是否写完为准。

| 状态 | 文档 | 后续重点 | 关联任务 |
| --- | --- | --- | --- |
| **进行中** | [LOCAL_WORKTREE_DEVELOPMENT.md](development-plans/LOCAL_WORKTREE_DEVELOPMENT.md) | Composer 惰性创建 detached worktree、执行目录绑定、当前改动与受控忽略文件携带、完成后清理；随后再做分支选择、外部所有权证明、Handoff 和永久工作树 | `ROADMAP.md` P1 本地工作树 |
| **已交付** | [IN_APP_BROWSER_DEVELOPMENT.md](development-plans/IN_APP_BROWSER_DEVELOPMENT.md) | 已接入客户端注册的 `browser` namespace 与 `item/tool/call` 闭环；真实 Flutter/WebKit 组合 smoke、插件到 Dart 下载回调及成功/取消/HTTP 失败组合、HTTP 下载边界、原生 `WKDownload` 委托、Flutter 语义树遍历、WebKit/AXUIElement contract 和真实网页 AX 子孙节点审计均已覆盖 | `ROADMAP.md` P1 内置浏览器后续阶段 |
| **进行中 / 待验收** | [CODEX_COMPOSER_PARITY_FOLLOWUP.md](development-plans/CODEX_COMPOSER_PARITY_FOLLOWUP.md) | 官方桌面行为矩阵、视觉并排、任务文件最终范围和官方 Codex 客户端 IDE 语义；VS Code 宿主与真实 VSIX smoke 已完成 | Composer 后续验收，不扩大当前实现承诺 |
| **进行中 / 建议** | [PROJECT_OPTIMIZATION_RECOMMENDATIONS.md](development-plans/PROJECT_OPTIMIZATION_RECOMMENDATIONS.md) | 核心状态拆分、缩小 Widget 重建范围和原生层测试；测试拆分与 CI 功能分片已交付 | 后续生产大型文件治理仍需逐域实施 |
| **性能基准** | [PROFILE_PERFORMANCE_BENCHMARK.md](development-plans/PROFILE_PERFORMANCE_BENCHMARK.md) | macOS Profile 下可重复测量侧栏、流式输出、后台完成、快速切换、unified Diff 解析、Flutter Git 审查画布和真实 WebView 展开/返回 | Profile driver 连接、原生宿主联动和 RSS 仍需进一步夹具 |
| **待开发** | [AGENT_DEFAULT_SETTINGS_PLAN.md](development-plans/AGENT_DEFAULT_SETTINGS_PLAN.md) | 对齐官方“智能体默认设置”：批准策略、沙盒、网页搜索、输出详细程度和推理摘要 | `ROADMAP.md` P1 设置一致性任务 |

### 待开发文档的使用规则

1. 先确认能力是否已进入 `ROADMAP.md`；未进入路线图的方案不能视为已承诺交付。
2. 开发时以文档中的安全边界和验收条件为约束，完成后把状态改为“已交付”或保留明确的“进行中”剩余项。
3. 实现、`README.md`、`ROADMAP.md` 和必要的 `RELEASE_NOTES.md` 必须同步，不能只更新方案文档。
4. 方案中的“后续阶段”是范围拆分，不等于当前版本已经支持。

### “与官网一致”的统一完成定义

项目只有在以下条件全部满足时，才可以将对应能力标记为“与官方客户端一致”：

1. 固定官方客户端版本、系统、账号能力和运行时版本已记录。
2. 官方行为矩阵已覆盖正常态、空态、加载态、失败态、禁用态、运行中和重启恢复。
3. App Server / CLI 协议字段、配置来源、作用域和失败语义已有公开证据或可重复实测证据。
4. 项目实现已通过对应的控制器、协议、Widget、窗口边界、键盘/焦点和异步生命周期测试。
5. 深色、浅色、窄窗口和关键菜单已完成截图并排或自动差异验收。
6. `README.md`、`ROADMAP.md`、`RELEASE_NOTES.md` 与实际行为同步。

只满足“界面上出现了同名设置”或“App Server 存在相似字段”，只能标记为“部分实现”或“待补证”，不能标记为完全一致。

## 已交付能力与当前规格

| 文档 | 用途 |
| --- | --- |
| [CODE_REVIEW_INTERFACE_DEVELOPMENT.md](development-plans/CODE_REVIEW_INTERFACE_DEVELOPMENT.md) | 右侧代码审查工作台的当前行为规格；首版已实现 |
| [IDE_CONTEXT_HOST_PROTOCOL.md](IDE_CONTEXT_HOST_PROTOCOL.md) | `codex_desk/ide_context` 宿主通道契约、断连语义和隐私边界 |
| [CODEX_COMPOSER_PARITY_PLAN.md](development-plans/CODEX_COMPOSER_PARITY_PLAN.md) | Composer、Goal/Plan、上下文、任务文件等当前实现、进行中改造及完成定义 |

## 开发计划目录

所有开发计划、技术方案和后续验收清单统一放在 [`development-plans/`](development-plans/)；新增功能计划应先放入该目录，再在 `ROADMAP.md` 建立对应任务。

## 参考与基线

| 文档 | 用途 |
| --- | --- |
| [CODEX_COMPOSER_PARITY_BASELINE.md](CODEX_COMPOSER_PARITY_BASELINE.md) | 固定版本 Codex 客户端、App Server Schema 和待实测证据基线 |
| [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md) | macOS 当前支持范围及 Windows / Linux 评估结论 |
| [AGENTS.md](../AGENTS.md) | 仓库协作、文档同步、验证和提交约定 |

## 项目入口与发布维护

| 文档 | 用途 |
| --- | --- |
| [README.md](../README.md) | 面向使用者和贡献者的项目概览、当前进度和限制 |
| [ROADMAP.md](../ROADMAP.md) | 项目唯一的后续任务清单和状态来源 |
| [RELEASE_NOTES.md](../RELEASE_NOTES.md) | 未发布版本的用户可感知变更记录 |
| [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) | macOS 构建、安装回归、签名和公证流程 |

## 如何判断该看哪份文档

- 想知道**现在有什么**：先看 [README.md](../README.md) 和 [CODEX_COMPOSER_PARITY_PLAN.md](development-plans/CODEX_COMPOSER_PARITY_PLAN.md)。
- 想知道**下一步做什么**：先看 [ROADMAP.md](../ROADMAP.md)，再进入本索引“待开发与进行中文档”对应方案。
- 想知道**某项能力如何验收**：查看对应开发文档；若是 Composer 官方一致性，使用 [CODEX_COMPOSER_PARITY_FOLLOWUP.md](development-plans/CODEX_COMPOSER_PARITY_FOLLOWUP.md)。
- 想准备**发布版本**：按 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) 执行，并同步 [RELEASE_NOTES.md](../RELEASE_NOTES.md)。
