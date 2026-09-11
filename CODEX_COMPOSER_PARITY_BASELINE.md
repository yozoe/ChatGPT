# Codex Composer 一致性基线

## 固定版本

- 官方客户端：`com.openai.codex` 26.903.61454（build 8378）。
- 内置 Codex CLI：`codex-cli 0.153.4`。
- 操作系统：macOS，Asia/Singapore 时区。
- 基线建立日期：2026-09-09。
- 公开文档：[Codex IDE extension slash commands](https://learn.chatgpt.com/docs/developer-commands?surface=ide)、[Codex App Server](https://learn.chatgpt.com/docs/app-server)。
- 协议证据：由上述客户端内置 CLI 执行 `codex app-server generate-json-schema --experimental` 生成的 0.153.4 Schema。

## 证据等级

- `已确认（文档）`：OpenAI 官方文档明确描述。
- `已确认（Schema）`：目标版本内置 App Server Schema 明确提供方法和字段。
- `已确认（客户端资源）`：目标版本客户端资源包含对应命令和文案。
- `待实测（桌面）`：必须在目标版本桌面 UI 中观察，公开文档或 Schema 无法证明精确行为。

桌面自动化连接在本轮采集时不可用，因此视觉尺寸、菜单精确顺序、焦点细节和任务文件跨轮展示仍为待实测项。不得用 CLI 行为替代桌面实测结论。

## `/` 命令基线

| 能力 | 官方证据 | App Server 协议 | 当前实现状态 |
| --- | --- | --- | --- |
| IDE 上下文 | 已确认（文档）：`/ide-context` 切换自动 IDE 上下文；CLI `/ide` 包含打开文件和当前选区 | App Server 0.153.4 的 `turn/start.additionalContext` 与 `turn/steer.additionalContext` 可携带按不透明来源键组织的 `{kind: untrusted/application, value: string}` 文本片段；官方文档仍未给出 IDE 宿主连接、来源键和序列化格式 | 已提供 `codex_desk/ide_context` 通用宿主通道并接入当前文件、选区、打开标签；有效快照到达后入口启用，显式选择后以 JSON 字符串发送，断连/切换项目清除选择。仓库没有具体 IDE 插件端，独立运行时仍禁用；当前项目路径从 `@`/添加菜单单独提供 |
| MCP | 已确认（文档） | `mcpServerStatus/list`、`mcpServerStatus/updated` | 已接入当前线程实时连接、认证与工具状态；待桌面实测 |
| 代码审查 | 已确认（文档）：未提交改动或相对基础分支 | `review/start`，目标支持 `uncommittedChanges`、`baseBranch`、`commit`、`custom` | 已改用结构化 `review/start` |
| 侧边聊天 | 已确认（文档）：临时聊天，不中断主聊天；审查模式和嵌套侧边聊天中不可用 | `thread/fork` + `ephemeral: true`；分页线程使用 `excludeTurns: true` | 已接入独立侧栏 UI，审查/嵌套/重复创建均禁用，迟到结果按任务丢弃；精确布局仍待桌面实测 |
| 创建聊天分支 | 已确认（文档、客户端资源） | `thread/fork`，可选 `lastTurnId` | 已接入持久分支并切换到返回线程；工作树选择待实测 |
| 压缩 | 已确认（文档）：确认后压缩，使用摘要替换早期上下文 | `thread/compact/start`，进度通过 `contextCompaction` item | 已接入真实协议；确认交互待补 |
| 反馈 | 已确认（文档）：反馈对话框，可选择包含日志 | `feedback/upload` | 已接入真实反馈对话框，日志默认不勾选 |
| 归档 | 已确认（文档） | `thread/archive` | 已有真实实现，待桌面实测 |
| 推理 | 已确认（文档） | 模型与 collaboration mode 配置 | 已有真实实现，待桌面实测 |
| 模型 | 已确认（文档） | `model/list` 与线程模型配置 | 已有真实实现，待桌面实测 |
| 新聊天 | 已确认（文档） | `thread/start` 在首次发送时创建 | 已有真实实现，待桌面实测 |

## `@` 与上下文基线

| 能力 | 已确认内容 | 尚待确认 |
| --- | --- | --- |
| 文件和文件夹 | 官方文档确认 `@` 可搜索工作区文件并把路径加入提示；App Server 0.153.4 Schema 明确提供 `fuzzyFileSearch {query, roots, cancellationToken}` 和带文件/目录类型、根目录、分数与匹配索引的结果，并支持 `mention {name, path}` | 已接入 Schema 证明的实时工作区搜索和结构化提交，保留系统选择器作为浏览更多入口；桌面端精确分组、排序和视觉仍待实测 |
| IDE 上下文 | 官方文档确认 IDE 可提供打开文件、当前选区及其他编辑器上下文；App Server Schema 确认 `turn/start.additionalContext` 是公开的客户端上下文载体 | 桌面端精确字段、宿主桥接与来源格式、断连降级；不得依赖未公开的扩展 IPC |
| Skill | App Server 文档确认文本中的 `$skill-name` 应与结构化 `skill` 输入同时发送 | 官方桌面端是否把 Skill 放在 `@` 菜单、分组与排序 |
| Goal | App Server 提供持久目标生命周期 | 官方桌面端 `@` 入口、徽标和草稿恢复细节 |
| Plan | 官方文档确认 `/plan` 和 collaboration mode | 官方桌面端 `@` 入口及运行中状态 |
| 录制技能 | 客户端存在技能创建/录制相关产品入口；尚无证据证明本地“附加 skill-creator + 提示词”完全等价 | 精确名称、采集过程、保存与失败生命周期；当前入口按未知协议禁用 |

### 上下文用量协议（Codex 0.153.4）

App Server Schema 明确提供 `thread/tokenUsage/updated`，通知包含 `threadId`、`turnId`、`tokenUsage.last`、`tokenUsage.total` 和可空的 `modelContextWindow`。Composer 使用 `last.totalTokens` 作为最近一次模型上下文占用，并按 thread/turn 严格归属；`total.totalTokens` 仅保留为累计统计，不用于上下文百分比。缺少有效窗口或 usage 时显示等待状态，不使用字符数估算或固定窗口值。

### 文件搜索协议（Codex 0.153.4）

App Server Schema 明确提供一次性 `fuzzyFileSearch`，请求包含查询词、按顺序传入的工作区根目录和可选取消令牌，响应区分文件与目录并返回所属根目录、路径、分数和匹配索引。当前 Composer 只在非空 `@` 查询且运行时可用时调用该接口；查询或工作区变化会使旧结果失效，返回路径还会经过存在性、符号链接和所属根目录校验。Schema 不能证明官方桌面端的精确分组、行高、排序二次处理或是否同时保留系统选择器，这些仍属于桌面实测项。

## 任务文件专项基线

App Server 已确认：

- `turn/diff/updated` 是一个 turn 内所有文件变更的最新聚合统一 Diff。
- `fileChange` item 属于 turn，包含 `{path, kind, diff}`。
- 历史线程可通过 turn 和 item 分页接口恢复逐轮数据。

Schema 进一步确认 `turn/diff/updated` 是“该 turn 内所有 file change 的最新聚合 Diff”，而 thread/read、thread/resume 和 thread/turns/list 返回的历史项仍按 turn 保存 Diff。以上证据只能证明协议是逐 turn 的，不能证明官方桌面端右侧“任务文件”采用哪种展示范围。以下项目必须桌面实测：

| 场景 | 官方桌面结果 |
| --- | --- |
| 第一轮创建文件，第二轮只追问 | 待实测 |
| 后续轮次再次修改同一文件 | 待实测 |
| 多轮分别修改不同文件 | 待实测 |
| 任务开始前已有 Git 改动 | 待实测 |
| 撤销当前变更 | 待实测 |
| 切换聊天后返回 | 待实测 |
| 重启客户端后恢复 | 待实测 |

在这些结果完成前，本地采用防止用户数据消失的保守过渡语义：同一 thread 的后续回合保留既有任务文件摘要，无文件事件的追问不会清空；同一 turn 内的 Diff 更新仍按 turn 替换，跨轮累计摘要没有完整任务级 Diff 时禁用撤销。该行为不得宣称已与官方桌面端一致，最终范围仍以专项实测结果为准。

## 桌面实测清单

- [ ] 记录 `/` 菜单完整顺序、分组、禁用和隐藏条件。
- [ ] 记录 `@` 菜单完整顺序、分组和触发范围。
- [ ] 记录方向键、Enter、Tab、Esc、鼠标悬停与焦点恢复。
- [ ] 记录新聊天、历史聊天、运行中、审查模式、侧边聊天中的命令差异。
- [ ] 完成任务文件七个专项场景。
- [ ] 固定浅色、深色及窄窗口截图。
- [ ] 记录几何差异和人工验收结论。

## 当前实施门槛

可以继续实现 Schema 已确认且不依赖未知视觉语义的协议和生命周期。以下内容仍不得凭推测定案：

- 侧边聊天的精确面板布局与焦点切换。
- IDE 上下文宿主桥接字段。
- `@` 中 Skill、Goal、Plan 和录制技能的官方桌面排序与名称。
- 任务文件是最新 turn、thread 累计还是 Git 工作树范围。
- 像素级视觉验收。
