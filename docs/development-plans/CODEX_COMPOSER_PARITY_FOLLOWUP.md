# Codex Composer 一致性后续验收清单

> 状态：部分完成 / 待验收。VS Code 宿主源码、本地 Node/transport 测试及 VS Code 1.135.0 隔离 VSIX smoke 已完成；官方客户端实测、视觉对照、任务文件范围确认和官方客户端 IDE 语义尚未完成。

> 本轮范围：按用户要求暂缓所有必须依赖官方截图或官方窗口操作的验收；以下“待补证”项目仍不视为已对齐。

本文档承接 [CODEX_COMPOSER_PARITY_PLAN.md](CODEX_COMPOSER_PARITY_PLAN.md) 中不纳入当前开发目标的工作。当前仓库已实现并测试的 Composer、App Server 协议、任务文件持久化和 IDE 宿主边界不需要在本清单中重复开发。

当前验收矩阵已登记在 [CODEX_COMPOSER_BEHAVIOR_MATRIX.md](../CODEX_COMPOSER_BEHAVIOR_MATRIX.md)。矩阵严格区分协议证据、项目测试证据和官方桌面证据；在官方 Codex 桌面窗口可被自动化选择前，不把项目测试或 App Server 文档升级为桌面一致性结论。

## 官方客户端实测

以固定版本的 Codex 桌面客户端建立可复现的行为矩阵，记录版本、系统、运行时和能力开关：

- `@` 菜单的完整顺序、分组、文案、图标、筛选和隐藏条件。
- `/` 菜单的完整顺序、分组、文案、图标、筛选和禁用条件。
- 句首、句中、空白后和换行后的触发边界。
- 鼠标悬停、键盘方向键、Enter、Tab、Esc、输入法组合态和焦点转移。
- 新聊天、历史聊天、运行中、完成态、审查态、侧边聊天和服务端离线状态。

## 官方视觉并排验收

- 深色和浅色主题。
- 常规、窄窗口和边界尺寸。
- 菜单、Composer、任务文件卡片的几何、行高、圆角、阴影、图标、字体和间距。
- 使用官方截图进行自动差异和人工并排验收。

## 智能体默认设置验收

针对官方“配置 → 智能体默认设置”截图，补充固定版本的行为矩阵：

- 确认“用户配置”选择器的选项、作用域和切换后配置来源；
- 确认“打开 config.toml”打开的是用户配置还是其他生效配置，并记录不可写或受组织策略管理时的表现；
- 分别验证批准策略、沙盒设置、网页搜索、输出详细程度和推理摘要的默认值、可编辑状态和保存位置；
- 单独记录网页搜索的“已禁用、已缓存、已索引、实时”四个选项，不得在没有证据时合并；
- 验证设置变更只影响后续任务还是会影响运行中的 turn，以及项目切换、运行时重连和应用重启后的恢复；
- 记录配置被项目、组织或运行时参数覆盖时的 UI 提示、禁用状态和来源标签。

## 任务文件范围与生命周期

用同一套步骤在官方客户端验证并记录最终展示范围：

1. 第一轮修改文件。
2. 第二轮只追问、不修改文件。
3. 第三轮修改旧文件。
4. 第四轮修改新文件。
5. 审查、撤销、恢复、切换聊天、切换项目和应用重启。
6. 任务开始前已有 Git 工作树改动。

根据证据确定右侧任务文件使用最新 turn、整个 thread、Git 工作树，或其他组合语义，再回到实现和测试中更新对应行为。

## IDE 宿主与官方客户端语义

代码实现和项目侧宿主验收已完成；本节剩余内容仅指官方 Codex 客户端中的 IDE
菜单、生命周期和视觉语义，不把本地 Debug 客户端证据升级为官方一致性结论。

仓库现已提供首个独立 VS Code 宿主源码，见
[`integrations/vscode-codex-context`](../../integrations/vscode-codex-context)
和 [IDE_CONTEXT_HOST_PROTOCOL.md](../IDE_CONTEXT_HOST_PROTOCOL.md)。本地 Node
测试与纯 Dart transport 验证已覆盖编辑器事件、选区、可见 Tab、停用断连、发现文件
删除/恢复重连、工作区切换和请求边界；扩展声明支持未信任工作区，VS Code `1.135.0`
的隔离 VSIX 在未信任临时工作区中已实际激活，并通过 loopback 代理把快照转发到真实
Debug Codex Desk，确认 `/IDE 上下文` 从未连接变为可用。扩展不会随桌面应用自动安装，
也不会向远程主机发送编辑器内容。官方 Codex 客户端菜单、视觉和生命周期语义仍需
单独验收，不能由本地 Debug 客户端证据替代。

## 交付门槛

完成本清单后，补充官方行为矩阵、视觉证据、任务文件范围结论和官方客户端
IDE 语义记录，再决定是否重新扩大主计划的完成定义。

## 证据登记表

以下登记表是“与官网一致”声明的必要证据。只有“官方证据”和“项目验证”两列都完成，状态才可改为已对齐；截图单独存在不能替代交互或协议证据。

| 项目 | 官方证据 | 项目验证 | 状态 |
| --- | --- | --- | --- |
| 批准策略 | 0.154 alpha Schema 已补充编码证据；仍需固定版本桌面确认完整选项、默认值、作用域和运行中任务行为 | 对应 App Server 请求、持久化、失败回滚和权限 UI 测试，并验证 0.153.4 降级 | 桌面/兼容性待补证 |
| 沙盒设置 | 0.154 alpha Schema 已补充模式枚举；仍需固定版本确认配置来源、覆盖优先级和不可编辑条件 | resolved config 读取、项目切换隔离和安全边界测试，并验证旧运行时行为 | 桌面/兼容性待补证 |
| 网页搜索 | 0.154 alpha Schema 已补充“disabled / cached / indexed / live”；仍需确认四项独立含义和默认值 | 四种状态的协议映射、网络权限和浏览器隔离测试 | 桌面/项目映射待补证 |
| 输出详细程度 | 0.154 alpha Schema 已补充 `low / medium / high`；仍需确认默认值、模型限制和生效时机 | 新任务参数、重启恢复和不支持时的只读降级测试 | 桌面/兼容性待补证 |
| 推理摘要 | 0.154 alpha Schema 已补充 `auto / concise / detailed / none`；仍需确认展示和持久化规则 | 摘要流、模型切换、运行中任务和设置 UI 测试 | 桌面/兼容性待补证 |
| 用户配置 / `config.toml` | `config/read`、`config/value/write` 和 `config/batchWrite` 已补充协议证据；仍需确认 profile、文件入口和用户/项目作用域 | 路径边界、读写权限、敏感字段脱敏和错误回滚测试 | 桌面/项目映射待补证 |
| 官方视觉 | 深浅色、窗口边界、行高、菜单、焦点和禁用态截图 | 自动差异 + 人工并排记录 | 待补证 |

在官方客户端自动化或人工实测环境恢复前，以上状态必须保持“待补证”，不得仅依据当前仓库测试或 App Server Schema 改为已对齐。

## 最近一次文档审计记录

审计日期：2026-09-13。

- 已核对 [README.md](../../README.md)、[ROADMAP.md](../../ROADMAP.md)、[RELEASE_NOTES.md](../../RELEASE_NOTES.md)、本目录下的 Composer/浏览器/工作树计划，以及 [CODEX_COMPOSER_PARITY_BASELINE.md](../CODEX_COMPOSER_PARITY_BASELINE.md) 的状态用语；已将“完整复刻”“完全一致”等无直接证据的表述收紧为“接入公开协议”“采用 Codex 风格”或“待官方验收”。
- 已核对浏览器边界：只有可回复的 `browser/open`、`browser/navigate` 请求和受限命名的 `item/tool/call` 动态浏览器工具在用户批准后才会导航；`computer-use` 活动和无 ID 通知只展示状态，不会自动打开网页。
- 已核对录制技能边界：当前运行时没有公开录制协议，入口保持禁用，不使用 `skill-creator` 加提示词模拟录制。
- 已执行 `git diff --check` 和仓库 Markdown 本地链接检查，当前均通过。
- 当前 shell 未发现可直接执行的 `codex` CLI（`command -v codex` 无结果）；因此基线中的 0.154 alpha Schema 仍作为已登记证据保留，但本轮没有声称完成新的协议复现或稳定版兼容性验证。
- 本轮在允许只读外网请求后复核了基线引用的官方文档 URL：`https://learn.chatgpt.com/docs/app-server` 与 `https://learn.chatgpt.com/docs/developer-commands?surface=ide` 均返回 HTTP 200（2026-09-13）；该结果只证明链接当前可访问，不替代版本化内容、稳定运行时兼容性或桌面 UI 验收。
- 官方桌面自动化仍不可用（CUA 环境返回 `CUA_REPL_ENABLED_SURFACES is required`）。因此菜单顺序、焦点、视觉尺寸、默认值、配置保存/热加载和任务文件最终展示范围仍未获得直接官方客户端证据，状态不得推进为“已对齐”。

## 恢复官方验收的前置条件

解除上述阻塞后，必须先固定并记录以下环境信息，再开始更新状态：

1. CUA 提供可选择的官方 Codex 桌面客户端 surface，并能读取窗口、菜单和设置页面状态。
2. 官方客户端版本、macOS 版本、账号能力、工作区路径和 App Server/CLI 版本与本基线中的目标版本明确对应；若版本变化，先建立新的基线，不覆盖旧证据。
3. 可执行的官方 `codex` CLI 位于已记录路径，能够重新生成对应版本 Schema；重新生成失败时只能保留历史证据，不能标记协议兼容已验证。
4. 按本清单的官方行为矩阵、智能体默认设置验收和任务文件生命周期步骤完成截图/操作记录，再同步更新基线、项目测试和 `README.md` / `ROADMAP.md` / `RELEASE_NOTES.md`。

### 重新验收周期（2026-09-13）

本周期首次检查仍返回 `CUA_REPL_ENABLED_SURFACES is required`，未获得官方桌面 surface。虽然临时 schema 校验产物仍可确认 `config/read`、`config/value/write`、`config/batchWrite`、`turn/settings/update` 及五个智能体默认设置字段存在，并再次核对 `sandbox_mode` 的 `read-only / workspace-write / danger-full-access`、`web_search` 的 `disabled / cached / indexed / live`、`model_verbosity` 的 `low / medium / high` 和 `model_reasoning_summary` 的 `auto / concise / detailed / none` 枚举，但这只补强协议字段证据，不改变上表任何“待补证”状态，也不把历史 Schema 升级为当前稳定运行时兼容性证据。

本轮用脚本将上述四组枚举与临时 Schema 做自动比对，均通过；该检查只证明文档枚举没有超出已登记 Schema，不证明稳定运行时兼容或桌面 UI 映射。

### 重新验收周期（2026-10-04）

- 已读取当前官方 [Codex App Server 文档](https://learn.chatgpt.com/docs/app-server)，确认线程/回合生命周期、`turn/steer`、Goal、Plan、审批、文件系统、`config/read`、`config/value/write` 与 `config/batchWrite` 的公开协议说明；对应证据已拆入 [CODEX_COMPOSER_BEHAVIOR_MATRIX.md](../CODEX_COMPOSER_BEHAVIOR_MATRIX.md)。
- 已检查本地 Debug 客户端窗口并取得当前深色工作台截图，作为项目侧视觉基线；这不是官方 Codex 客户端截图，不能用于宣称视觉一致。
- CUA 当前仍无法选择官方 Codex 桌面客户端窗口，因此官方菜单顺序、焦点路径、默认文案、配置页行为和任务文件最终范围仍保持“待补证”。
- 当前工作区已提交行为矩阵文档，未对未经官方桌面证据支持的 UI 结论降级为“已对齐”。
- VS Code 1.135.0 隔离 VSIX smoke、本地 Node/transport 测试和真实 Debug Codex Desk discovery 链路已完成；剩余 IDE 项仅为官方 Codex 客户端语义验收。

### 重新验收周期（2026-10-05）

- CUA 应用清单可以看到正在运行的官方 `ChatGPT`（`com.openai.codex`）；不过 `cua.getApp("ChatGPT")` 会解析到本项目的 `chatgpt`（`com.yozoe.chatgpt`，AX 标题为“Codex Desk”），按官方安装路径 `/Applications/ChatGPT.app` 绑定则被当前 Computer Use 安全策略拒绝。因此没有获得官方窗口状态。
- 因此本周期没有取得官方窗口状态、客户端版本、窗口尺寸、主题或截图，不能推进官方行为矩阵、视觉并排或任务文件范围结论。
- 项目侧 VS Code 宿主、隔离 VSIX smoke 和真实 Debug Codex Desk discovery 证据不受影响，仍保持“已完成”；官方 Codex 客户端 IDE 语义继续保持“待补证”。
- 本周期重跑项目侧验证：`integrations/vscode-codex-context` 的 Node 测试 2/2 通过，`dart run tool/verify_ide_context_host_transport.dart` 通过；这些结果只证明项目侧宿主链路，不替代官方客户端证据。
- 官方 [Computer Use 文档](https://learn.chatgpt.com/docs/computer-use.md) 明确说明该功能不能自动化 ChatGPT 本身；因此为 `com.openai.codex` 开启 Screen Recording、Accessibility 或 Always allow 也不能解除当前官方客户端限制。后续只能由用户提供官方截图/操作记录，或在允许的独立目标应用中完成验证。
- 跳过截图依赖后，本周期完成代码侧闭环：`flutter analyze` 无问题，`dart format --set-exit-if-changed lib test` 报告 500 个文件、0 个改动，完整 `flutter test` 749/749 通过；截图依赖的官方交互、视觉和任务文件最终范围仍不改变状态。
- 清理主计划中残留的合并冲突标记，并统一后续验收文档链接到当前英文文件名；这只修正文档一致性，不改变任何官方验收状态。
- 复核主计划后，已将 VS Code 宿主的真实连接证据从“待完成集成”改写为“项目侧已完成、官方客户端来源格式待补证”，并把代码审查、侧边聊天和聊天分支的项目侧协议/测试结果与官方桌面语义分开记录。
