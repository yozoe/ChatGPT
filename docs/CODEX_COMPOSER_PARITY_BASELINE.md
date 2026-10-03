# Codex Composer 一致性基线

## 版本基线

### 项目实现基线（2026-09-09）

- 官方客户端：`com.openai.codex` 26.903.61454（build 8378）。
- 内置 Codex CLI：`codex-cli 0.153.4`。
- 操作系统：macOS，Asia/Singapore 时区。
- 公开文档：[Codex IDE extension slash commands](https://learn.chatgpt.com/docs/developer-commands?surface=ide)、[Codex App Server](https://learn.chatgpt.com/docs/app-server)。
- 协议证据：由该版本客户端内置 CLI 执行 `codex app-server generate-json-schema --experimental` 生成的 0.153.4 Schema。

### 当前官方证据基线（2026-09-13）

- 本机官方客户端：`com.openai.codex` 26.908.40834（build 8881）。
- 内置 Codex CLI：`codex-cli 0.154.0-alpha.6.2`。
- 协议证据：由该版本客户端内置 CLI 执行 `codex app-server generate-json-schema --out <dir> --experimental` 生成的 Schema，详见下方“官方 App Server 0.154.0-alpha 协议补充证据”。

两个版本不能混为同一基线：项目当前实现和测试仍以 0.153.4 为主，官网设置字段的最新协议证据来自 0.154.0-alpha；升级或兼容性验证完成前，项目不得默认使用 alpha 字段。

## 证据等级

- `已确认（文档）`：OpenAI 官方文档明确描述。
- `已确认（Schema）`：目标版本内置 App Server Schema 明确提供方法和字段。
- `已确认（客户端资源）`：目标版本客户端资源包含对应命令和文案。
- `待实测（桌面）`：必须在目标版本桌面 UI 中观察，公开文档或 Schema 无法证明精确行为。

桌面自动化连接在本轮采集时不可用，因此视觉尺寸、菜单精确顺序、焦点细节和任务文件跨轮展示仍为待实测项。不得用 CLI 行为替代桌面实测结论。

## 智能体默认设置截图证据

用户提供了一张 Codex 官方客户端“配置 → 智能体默认设置”的截图，当前可观察到的项目为：

- 批准策略；
- 沙盒设置；
- 网页搜索，菜单中分别出现“已禁用、已缓存、已索引、实时”；
- 输出详细程度；
- 推理摘要；
- “用户配置”入口和“打开 config.toml”入口。

该截图是视觉和文案证据，但未包含客户端版本、系统版本、账号能力、配置来源或每个选项的完整描述，也不能确认它与本文件“版本基线”章节记录的任一版本相同。因此它可以证明这些设置存在于某个官方客户端界面，不能单独证明 App Server 字段、默认值、作用域、持久化方式或是否影响运行中任务。以上未确认内容必须通过固定版本官方客户端实测或公开协议补证。

### 截图逐项对照

| 设置 | 截图可确认内容 | 当前项目状态 | 一致性结论 |
| --- | --- | --- | --- |
| 批准策略 | 存在设置行；截图显示当前值为“按请求” | 已有“请求批准 / 帮我批准”两种本地策略 | 交互和策略粒度仍待官方实测 |
| 沙盒设置 | 存在设置行；截图显示当前值为“只读” | 仅显示“由配置管理” | 未实现读取最终 sandbox 值 |
| 网页搜索 | 菜单明确区分“已禁用、已缓存、已索引、实时” | 只有网页搜索活动展示，暂无策略选择器 | Schema 已确认枚举；官方默认值、作用域和 UI 映射仍待实测 |
| 输出详细程度 | 存在设置行 | 仅显示“模型默认” | Schema 已确认 `low` / `medium` / `high`；官方默认值和作用域仍待实测 |
| 推理摘要 | 存在设置行 | 能渲染运行时摘要，但没有偏好控制 | Schema 已确认 `auto` / `concise` / `detailed` / `none`；官方展示和默认值仍待实测 |
| 用户配置 | 存在“用户配置”下拉入口 | 没有对应的配置 profile 选择器 | 作用域和切换行为待实测 |
| `config.toml` | 存在“打开 config.toml”入口 | 配置对话框提供系统默认应用打开用户 `config.toml`，写入仍只走受协议约束的 App Server API | 需要确认官方桌面端打开动作、编辑器选择和写入权限边界 |

表中的“当前项目状态”只描述仓库现状，不代表官方行为已被完整复制；只有“截图可确认内容”和固定版本交互矩阵共同通过后，才能更新为已对齐。

## 官方 App Server 0.154.0-alpha 协议补充证据

2026-09-13 从本机已安装的官方 `ChatGPT.app`（Bundle ID `com.openai.codex`，版本 `26.908.40834`，build `8881`）读取到内置 `codex-cli 0.154.0-alpha.6.2`，并执行 `codex app-server generate-json-schema --out <dir> --experimental`。该版本 Schema 明确提供：

- `config/read`：可按 `cwd` 解析项目配置，返回合并后的 `config`、`origins`，并可选返回 `layers`；
- `config/value/write` 和 `config/batchWrite`：支持 `keyPath`、`mergeStrategy`（`replace` / `upsert`）和可选 `expectedVersion`；`filePath` 省略时目标文件默认为用户 `config.toml`；批量写入还支持 `reloadUserConfig`，并以编辑数组保持一次提交的原子边界；
- `Config` 字段：`approval_policy`、`sandbox_mode`、`web_search`、`model_verbosity`、`model_reasoning_summary`；
- `AskForApproval`：`untrusted`、`on-request`、`never`，以及 `{granular: {...}}` 形式；granular 必须提供 `mcp_elicitations`、`rules`、`sandbox_approval`，`request_permissions` 与 `skill_approval` 为可选布尔字段（Schema 默认值为 `false`）；
- `SandboxMode`：`read-only`、`workspace-write`、`danger-full-access`；
- `WebSearchMode`：`disabled`、`cached`、`indexed`、`live`；
- `Verbosity`：`low`、`medium`、`high`；
- `ReasoningSummary`：`auto`、`concise`、`detailed`、`none`。

上述五个 `Config` 属性在 Schema 中都允许省略或显式为 `null`（不是 `required` 字段）；当返回明确枚举值时才表示该层配置有具体覆盖。客户端解析必须保留“缺失 / `null` / 明确值”的三态，不得把缺失或 `null` 误显示成某个具体默认选项。

同一 Schema 还提供实验性的 `turn/settings/update`，但它只针对指定的运行中 `threadId` / `turnId`，可更新 `model`、`effort`、`summary`、`serviceTier` 和 `approvalsReviewer`；它不代表未来任务默认配置，也不能用来热更新 sandbox、web search 或 verbosity。`config/batchWrite` 的 `reloadUserConfig` 描述明确指出，模型、推理强度、Plan 模式推理强度、服务等级和 personality 默认值不会热加载。

这份证据比仓库当前锁定的 0.153.4 Schema 更新，因此开发前必须先完成版本兼容矩阵；不能把 0.154 alpha 字段直接假定为 0.153.4 稳定运行时可用。

### 官方 `config/read` 默认值实测

在隔离的临时 `CODEX_HOME`（不读取用户现有配置）和 `/tmp` 工作目录启动同一官方 App Server，并发送 `initialize`、`config/read {cwd: "/tmp", includeLayers: true}` 后，得到以下可复现结论：

- `config` 返回完整字段集合；在空用户配置下，`approval_policy`、`sandbox_mode`、`web_search`、`model_reasoning_summary` 和 `model_verbosity` 均为 `null`，表示沿用运行时/模型默认值，而不是协议不支持；
- `layers` 返回用户层和系统层，均带有 `name`、`version` 和配置内容；`origins` 用于字段来源映射；
- `config/read` 不要求先创建 thread，也不要求把用户配置写入项目目录；
- 官方响应中的 `config` 还包含 `profile`、`features`、`permissions`、`tools` 等其他设置，不能只实现截图中的五行后就把它称为完整配置镜像。

这次实测验证了默认值和配置来源的协议形状，但没有验证官方桌面设置页如何把 `null` 显示成“按请求”“只读”“已缓存”等文案；这些仍需桌面 UI 实测。

### Schema 证据复现模板

在具备目标版本官方 CLI 的环境中，使用隔离配置目录生成协议文件，避免读取开发者个人配置：

```bash
SCHEMA_OUTPUT="$(mktemp -d)" \
CODEX_HOME="$(mktemp -d)" \
  codex app-server generate-json-schema \
  --out "$SCHEMA_OUTPUT" \
  --experimental
```

随后对输出 Schema 核对 `config/read`、`config/value/write`、`config/batchWrite`、`turn/settings/update`，以及 `Config` 中五个默认设置字段和对应枚举。命令只能证明该 CLI 版本的公开协议形状；仍需单独记录 CLI 版本、稳定版兼容性和桌面 UI 行为，不能将 Schema 生成成功视为官网界面验收完成。

### 官方公开文档复核（2026-09-13）

通过只读请求复核官方 App Server 文档后，页面明确列出 `config/read`、`config/value/write` 和 `config/batchWrite`，并说明这些方法用于读取或更新 `config.toml` 中的应用控制项；`config/read` 会返回解析配置层后的有效配置。该公开文档证据支持本基线对配置方法和分层读取的描述，但页面未直接证明桌面设置页的文案、默认值、作用域或热加载行为；这些仍须依赖 Schema 与固定版本客户端实测。

同一页面未直接出现 `origins`、`layers` 或 `reloadUserConfig` 这几个字段名；它们目前仅有目标版本 Schema 证据。项目不得把这些字段描述成公开文档承诺的跨版本稳定契约，兼容性仍需按实际 CLI/App Server 版本验证。

官方 developer commands 页面当前仍提供与本项目基线相关的命令入口，包括 `/archive`、`/compact`、`/feedback`、`/fork`、`/ide-context`、`/mcp`、`/model`、`/plan` 和 `/review`（2026-09-13 只读复核）。这只证明公开文档仍列出这些能力，不证明桌面客户端的菜单顺序、禁用条件或具体生命周期已经一致。

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
