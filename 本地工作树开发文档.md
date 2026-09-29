# Codex 风格本地工作树开发文档

> 状态：开发规格，尚未实现
> 适用范围：Codex Desk macOS Flutter 工作台
> 官方行为基线：[OpenAI Worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees)

## 1. 功能目标

本地工作树让用户在不影响原始项目目录的前提下，为一个 Codex 任务创建独立的 Git checkout。用户可以继续在原始目录开发，同时让一个或多个 Codex 任务在各自工作树中修改、测试和提交代码。

该能力解决以下问题：

- 用户与 Codex 同时修改同一仓库时互相覆盖文件；
- 多个后台任务的未提交改动混在同一个工作区；
- 实验性任务污染正在运行或调试的本地环境；
- 一个任务的暂存、提交和依赖缓存影响另一个任务；
- 用户无法整体保留、移交或丢弃某个任务的修改。

首版必须建立三个可靠边界：

1. 工作树由哪个项目和 Git 仓库创建；
2. 哪个任务绑定到哪个实际执行目录；
3. 工作树何时可以安全移交、删除或恢复。

工作树不是文件复制功能、临时沙箱或远端环境。它使用 Git worktree，共享仓库对象和提交历史，但拥有独立的工作目录、HEAD 和 index。

## 2. 术语与用户模型

| 术语 | 定义 |
|---|---|
| 本地（Local） | 用户最初添加到项目的主目录，即日常 IDE 和终端使用的 checkout |
| 托管工作树（Managed worktree） | Codex Desk 为单个任务创建并管理生命周期的临时工作树 |
| 永久工作树（Permanent worktree） | 用户从项目菜单显式创建、作为独立项目长期保留的工作树 |
| Handoff | 在本地 checkout 与同一任务绑定的工作树之间安全转移聊天和代码 |
| 基准提交（Base commit） | 创建工作树时所选分支的 `HEAD`，用于比较、快照和移交 |
| 执行目录（Execution directory） | 当前任务传给 App Server `thread/start.cwd` 与 `turn/start.cwd` 的真实目录 |
| 源项目（Source project） | 用户原始项目配置；工作树始终保留对其稳定项目 ID 的归属 |

用户界面只使用“本地”“工作树”“移交”等产品术语，不要求用户理解 `.git` 文件或 Git common directory。

## 3. 官方行为对齐

实现应对齐 Codex 桌面客户端的以下行为：

- 新任务可选择在“本地”或“新建本地工作树”中运行；
- 创建时选择起始分支，也允许从带有本地改动的当前分支开始；
- 托管工作树默认使用 detached HEAD，不自动污染分支列表；
- 一个托管工作树通常只绑定一个聊天，聊天再次返回工作树时复用同一目录；
- 用户可在工作树中“在此创建分支”，随后提交、推送和创建 PR；
- 用户可使用 Handoff 在本地与工作树之间移动聊天和代码；
- 永久工作树作为独立项目存在，不随聊天归档自动删除；
- `.worktreeinclude` 控制需要复制到托管工作树的忽略文件；
- 忽略的 `AGENTS.override.md` 自动复制，不要求写入 `.worktreeinclude`；
- 托管工作树默认保留最近 15 个，可在设置中调整或关闭自动清理；
- 置顶聊天、运行中聊天和永久工作树不能被自动清理；
- 删除托管工作树前保存可恢复快照；
- 同一 Git 分支不能同时在两个工作树中签出。

### 3.1 Codex Desk 的必要实现差异

Codex Desk 不得删除或接管其他客户端创建的工作树。默认目录使用：

```text
$CODEX_HOME/worktrees/codex-desk/<worktree-id>/
```

若无法可靠取得 `$CODEX_HOME`，回退到应用 Application Support 下的 `worktrees/`。每个目录包含一份便于诊断的所有权清单，但它不是删除授权的唯一来源。应用同时在工作树根目录之外的 `WorktreeMetadataStore` 保存权威所有权记录，并为每个工作树生成随机 nonce；目录内清单使用保存在 macOS Keychain 中的每安装密钥执行 HMAC-SHA256，覆盖 schema version、worktree ID、source project ID、canonical worktree path、canonical Git common directory 和 nonce。

`ready` 及之后状态的清理器仅在以下信息全部一致时处理该目录：外部权威记录、有效 HMAC、canonical path、Git common directory，以及 `git worktree list --porcelain` 中的精确记录。密钥不可用、记录缺失、路径经过符号链接跳转或任一字段不符时，工作树进入 `foreign`，只能由用户查看或手动处理，应用不得删除。目录内普通 JSON 清单即使可读写，也不能单独证明所有权。

`creating` 状态使用独立的恢复授权，因为进程可能在 `git worktree add` 成功后、目录清单写入前退出。只有启动前已提交的 provisional 记录仍为当前 operation、记录中的随机 nonce 和精确 canonical staging path 未变、common directory 匹配，并且启动对账能证明该路径是 operation 开始后新增的唯一 Git worktree 记录时，才允许补写 HMAC 清单或通过 `git worktree remove` 回滚；路径已预先存在、记录不唯一或任一证据不符时仍进入 `foreign`，不得删除。

这一差异只影响内部所有权隔离，用户可见行为保持与 Codex 一致。

## 4. 功能范围

### 4.1 首版交付

- 新任务选择“本地”或“新建本地工作树”；
- 选择起始分支并创建 detached HEAD 托管工作树；
- 将任务永久绑定到真实执行目录；
- 从所选分支携带当前未提交改动；
- 支持 `.worktreeinclude` 和 `AGENTS.override.md`；
- 工作树状态、基准分支和路径可见；
- 在工作树中创建分支；
- 工作树继续支持现有审查、暂存、提交、推送和 PR；
- 归档后安全快照与清理；
- 工作树丢失时恢复快照；
- 默认最多保留最近 15 个托管工作树；
- 多附加目录项目明确显示隔离边界。

### 4.2 第二阶段

- Worktree → Local Handoff；
- Local → Worktree Handoff；
- 用户可配置工作树根目录与保留数量；
- 永久工作树创建、重命名和手动移除；
- 本地环境 setup 脚本。

### 4.3 后续能力

- 已安排任务自动使用专属后台工作树；
- 工作树磁盘占用统计和清理建议；
- 导入应用外已有的 Git worktree；
- 远端环境工作树。

### 4.4 明确不做

- 不把普通目录复制伪装成 Git worktree；
- 不支持非 Git 项目创建工作树；
- 不自动合并、rebase 或 force push；
- 不在存在冲突时覆盖本地文件；
- 不把所有附加目录隐式转换为工作树；
- 不自动复制 `.gitignore` 中的密钥或全部本地配置；
- 不删除应用无法证明所有权的目录；
- 不允许通过符号链接把复制或删除范围逃逸到工作树根目录外。

## 5. 用户入口与界面

### 5.1 新任务环境选择器

新对话的 Composer 附近提供环境选择器，默认显示“本地”。展开后显示：

```text
继续至
✓ 本地
  新建本地工作树 · <项目名>
  在 N 个其他文件夹中本地工作
```

规则：

- 非 Git 项目禁用“新建本地工作树”，并说明“工作树需要 Git 仓库”；
- 当前项目主目录必须解析到真实 Git 顶层目录；
- 已有历史任务不能通过该菜单直接改变执行目录，应使用 Handoff；
- 用户选择工作树后，第一条消息发送前显示待创建状态；
- 工作树只在第一次实际发送任务时创建，空白新对话不占磁盘；
- 创建失败时保留 Composer 文本、附件、目标、计划模式和技能选择。

### 5.2 起始分支选择

选择“新建本地工作树”后，在 Composer 下方显示起始分支：

- 默认使用当前本地分支；
- 可选择本地分支和可解析的远端跟踪分支；
- 若当前分支存在未提交改动，明确显示“包含当前本地改动”；
- 分支已被其他工作树签出不妨碍以其提交创建 detached HEAD；
- 分支在发送前被删除或移动时，重新校验并要求用户确认最新基准。

### 5.3 任务运行后的环境信息

任务顶部或右侧环境区显示：

- `本地` 或 `工作树`；
- 起始分支；
- detached HEAD 或当前工作树分支；
- 工作树路径的可复制详情；
- “打开”“后台终端”“移交”“在此创建分支”等可用操作。

审查界面的 Git 来源必须读取任务实际执行目录，不能继续读取源项目本地 checkout。

### 5.4 多目录项目

创建项目时，用户可先选择主目录，再继续添加一个或多个附加目录；弹窗中的首个目录固定作为主目录，其余目录随工作区配置保存，并可在提交前逐项移除。工作树实现必须沿用这组目录边界，不能把创建阶段的附加目录静默丢弃或改成新的项目。

当前 `WorkspaceConfiguration` 支持一个主目录和多个附加目录。首版只为主 Git 仓库创建工作树：

- 主目录替换为工作树路径并作为 App Server `cwd`；
- 其他附加目录继续使用原始本地路径，并继续传入 `runtimeWorkspaceRoots`；
- 选择器必须显示“在 N 个其他文件夹中本地工作”；
- 权限审批、文件变更和审查结果必须标注真实仓库来源；
- 用户需要完全隔离多个仓库时，应为每个仓库创建独立项目；首版不自动创建跨仓库工作树组。

这意味着附加目录中的改动仍会直接修改用户本地文件，不能用“工作树已隔离”笼统描述整个项目。

## 6. 状态与生命周期

### 6.1 工作树状态

```text
planned
  │ 首次发送
  ▼
creating ─────失败─────► failed
  │ 创建并初始化成功
  ▼
ready ─────任务执行────► active
  ▲                       │
  └────────任务结束───────┘
  │
  ├──创建分支────────────► ready / active
  ├──开始移交────────────► handingOff
  ├──开始快照────────────► snapshotting
  └──检测到目录缺失──────► missing

snapshotting ─成功─► removable ─删除─► removed
missing ─恢复快照─► restoring ─成功─► ready
任意可恢复状态 ─永久化─► kind = permanent / state = ready
```

### 6.2 状态约束

- `creating`、`handingOff`、`snapshotting`、`restoring` 期间禁止重复操作；
- `active`、置顶聊天和 `permanent` 不进入自动清理；
- 运行中任务不能 Handoff、删除、改变基准或永久化；
- 只有目录、Git common directory、外部权威记录、有效 HMAC 和 Git worktree 列表全部一致时才视为可用；
- 目录存在但清单不匹配时进入 `foreign`，仅允许“在 Finder 中显示”，不允许删除；
- App Server 启动或任务恢复时，执行目录必须与任务绑定一致，否则拒绝发送并提供恢复入口。

## 7. 数据模型

新增领域模型建议：

```dart
enum WorktreeKind { managed, permanent }

enum WorktreeState {
  planned,
  creating,
  ready,
  active,
  handingOff,
  snapshotting,
  removable,
  missing,
  restoring,
  failed,
  foreign,
  removed,
}

class LocalWorktreeRecord {
  final String id;
  final String sourceProjectId;
  final String sourceRepositoryPath;
  final String gitCommonDirectory;
  final String worktreePath;
  final String baseRef;
  final String baseCommit;
  final String? branch;
  final String? threadId;
  final WorktreeKind kind;
  final WorktreeState state;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final String? snapshotId;
  final String? lastError;
}
```

任务执行环境单独持久化：

```dart
enum ThreadEnvironmentKind { local, managedWorktree, permanentWorktree }

class ThreadEnvironmentBinding {
  final String threadId;
  final String projectId;
  final ThreadEnvironmentKind kind;
  final String executionPath;
  final String? worktreeId;
}
```

创建线程前还需持久化可恢复的启动意图：

```dart
class PendingInitialTask {
  final String operationId;
  final String projectId;
  final String worktreeId;
  final String executionPath;
  final DateTime startedAt;
  final int generation;
  final PendingInitialTaskPhase phase;
  final bool requestMayHaveBeenDispatched;
  final String? threadId;
  final String? turnId;
  final InitialTurnEnvelope initialTurn;
}
```

`PendingInitialTaskPhase` 至少区分 thread 请求准备、thread 可能已发送、thread 已绑定、turn 可能已发送和 turn 已接受。`InitialTurnEnvelope` 使用与对话历史相同级别的加密保护，完整保存文字、附件引用、目标、计划模式、技能、模型和发送时设置，直到服务器确认首轮 turn 后才删除。

Handoff 另存代次化检查点。检查点不只保存一个 `baseCommit`，还要保存本地与工作树在上次成功移交后的各自 tracked/untracked 内容清单、文件摘要及生成增量所需的受保护 preimage；两端基线允许包含不同的、不属于上次迁移的既有改动。托管工作树完成代码初始化后、允许任务修改文件前必须建立 generation 0：此时分别记录携带操作完成后的本地状态和工作树状态。两端当时应包含相同的已携带改动，但允许保留明确排除在迁移范围外的各自内容。

关键规则：

- 项目 ID、线程 ID 和工作树 ID 是身份；路径只是经过校验的属性；
- 不以路径相同推断两个项目或任务具有相同所有权；
- 历史缓存仍归属于源项目 ID，但每个线程保存自己的执行环境；
- 工作树变成永久项目时创建新的 `WorkspaceConfiguration.id`，同时保留 `sourceProjectId`；
- 旧版本没有环境绑定的线程必须按第 8.1 节依据最后已知 cwd 迁移或进入待对账，不能无条件按 `local` 处理。

## 8. 持久化与共享状态

新增统一的 `WorktreeMetadataStore`。它在一个版本化的加密数据库或单一原子替换文件中保存工作树记录、线程环境绑定、项目线程索引、pending initial task、Handoff 检查点、所有权记录和设置，并提供真正的单事务读写。`LocalWorktreeRepository`、`ThreadEnvironmentRepository`、`ProjectThreadIndexRepository` 和 `PendingInitialTaskRepository` 只是同一事务后端的领域视图，不能各自写独立文件。

代码快照及可能较大的 Handoff preimage 由 `WorktreeSnapshotStore` 单独保存。元数据事务先引用处于 `prepared` 状态且已经落盘并验证摘要的 blob，事务提交后再标记为 `committed`；未被已提交元数据引用的 blob 可在启动对账后回收。这样不要求跨多个大文件执行伪原子 rename。

跨项目、任务、Git 操作和异步生命周期共享的状态必须由 Riverpod 管理。建议 Provider：

```text
worktreeSettingsProvider
projectWorktreesProvider(projectId)
threadEnvironmentProvider(threadId)
worktreeOperationProvider(worktreeId)
worktreeDiskUsageProvider
```

`CodexController` 在迁移期保留 ChangeNotifier 桥接，但不能独占工作树状态。创建、恢复、Handoff 或清理的迟到结果必须通过操作代次、项目 ID、线程 ID 和工作树 ID 四重校验。

敏感性要求：

- 所有权清单不保存文件内容或凭据；
- 快照可能包含源代码和未跟踪文件，必须使用与对话历史相同级别的本机保护，并限制目录权限；
- `.worktreeinclude` 复制的密钥不得写入日志、诊断报告或普通 JSON 配置；
- 删除记录前先删除或安全转移其快照。

### 8.1 历史缓存迁移

`ConversationHistoryStore` 的 schema 必须显式升版，不能直接把现有以 workspace 路径为键的数据当作项目 ID 数据读取：

1. 迁移前在同一受保护存储中写入迁移标记和可回滚备份；
2. 将每个已知 `WorkspaceConfiguration` 的 canonical 主路径映射到稳定项目 ID；
3. 同一路径键与项目 ID 键同时存在时，按 thread ID 合并，保留更新时间较新的线程内容，并合并未读等不会互斥的元数据；
4. 无法映射的旧路径快照保留为只读 legacy entry，不静默丢弃，待用户重新添加目录后再归并；
5. 新快照、线程环境绑定与项目线程索引全部写入 `WorktreeMetadataStore` 的同一事务后，才提交新 schema；失败时继续读取旧 schema；
6. 迁移必须幂等，应用在任意步骤退出后可以从迁移标记恢复，不能生成路径键和项目 ID 键两份可变副本。

旧线程没有环境绑定时，仅在其最后已知 cwd 等于当时项目主目录后迁移为 `local`；cwd 指向已知工作树或无法确认时进入待对账状态，不能默认改到本地目录执行。

## 9. 服务拆分

### 9.1 `LocalWorktreeService`

只负责 Git 和文件系统原语：

- 检查 Git 仓库与 common directory；
- 列出可用分支；
- 创建 detached worktree；
- 读取工作树状态；
- 在工作树中创建分支；
- 生成、校验和应用迁移 patch；
- 读取 `.worktreeinclude`；
- 删除应用拥有的工作树；
- 执行 `git worktree prune` 的受限清理。

所有命令使用 `Process.start` / `Process.run`、参数数组和 `runInShell: false`。每个读写操作设置超时，超时后终止子进程。用户路径只作为 `--` 后的参数或 `workingDirectory`，不拼接 Shell 字符串。

### 9.2 `WorktreeCoordinator`

负责编排：

- 创建前预检；
- 创建与初始化；
- 绑定任务执行目录；
- Handoff；
- 快照、清理和恢复；
- 与任务运行状态、置顶状态和归档状态协调；
- 向 Riverpod 发布加载、错误和恢复状态。

### 9.3 现有模块调整

- `WorkspaceConfiguration`：保持源项目结构，永久工作树另建项目记录；
- `CodexAppServer`：协议无需新增字段，但调用方必须传线程绑定的 `cwd`；
- `CodexController.sendPrompt()`：从当前线程环境读取执行目录，不再总用 `workspacePath`；
- `refreshThreads()`：分别以源项目本地目录和其所有仍存在的工作树目录调用 `thread/list`，再与 `ProjectThreadIndexRepository` 合并并按线程 ID 去重；`missing`、`removable` 和 `removed` 工作树的历史线程即使 cwd 已不可查询，也必须通过项目线程索引继续出现在原项目，不能继续只查询 `workspacePath` 或只保留“有效目录”的结果；
- `resumeThread()`：恢复任务前校验环境绑定，目录缺失时先进入恢复流程；
- `GitProjectService`：所有 Git 状态和写操作改为接收当前任务的 repository context；
- `ConversationHistoryStore`：快照增加线程环境绑定版本；
- `ScheduledTask`：后续增加工作树策略和工作树 ID；
- 审查界面：仓库名、分支、Diff 和操作均跟随任务执行目录。

App Server 进程不因选择托管工作树而重启。当前 stdio App Server 可以在 `thread/start` 和 `turn/start` 接收每个任务自己的 `cwd`；运行时连接继续由源项目持有，任务和 Git 路由由线程环境绑定决定。读取 Codex 配置、技能或项目级能力时，也必须使用对应任务执行目录，不能沿用源项目缓存冒充工作树配置。

项目栏的任务归属使用稳定源项目 ID，而不是要求线程 cwd 等于源目录。每次 `thread/start`、`thread/list`、恢复或历史迁移发现线程时，都通过 `WorktreeMetadataStore` 的事务更新项目线程索引。后台任务刷新、归档列表、搜索聊天、未读状态和缓存淘汰必须合并该索引与可查询 cwd；清理工作树只把索引中的环境标记为 `removed`，不删除线程条目。用户重新打开该聊天时，先显示恢复入口，再以快照恢复原工作树身份。永久工作树成为独立项目后，才由新的项目 ID 拥有其后续聊天。

## 10. 创建流程

### 10.1 预检

发送第一条消息前依次验证：

1. 源目录存在且不是符号链接逃逸路径；
2. `git rev-parse --show-toplevel` 成功；
3. 解析并保存 Git common directory；
4. 起始 ref 可解析为提交；
5. 工作树根目录可写且不位于源仓库内部；
6. 目标目录不存在；
7. 磁盘空间满足最低安全余量；
8. 当前没有针对同一 planned record 的创建操作。

任何一步失败都不得创建服务器线程或清空 Composer。

### 10.2 创建 Git worktree

核心命令等价于下面这样；需要携带本地改动时 `<target-or-staging-path>` 为 `<worktree-id>.preparing`，否则可直接使用最终路径：

```text
git worktree add --detach <target-or-staging-path> <base-commit>
```

执行命令前，先在工作树根目录之外写入 `creating` 状态的 provisional 权威记录、operation ID、canonical 目标路径预期、Git common directory、随机 nonce、创建前 `git worktree list --porcelain` 摘要和事务日志；这样即使进程在 Git 命令期间退出，启动对账仍能识别并验证唯一的 Codex Desk 创建操作。创建成功后立即重新读取：

- worktree 顶层路径；
- Git common directory；
- 当前 HEAD；
- detached 状态；
- `git worktree list --porcelain` 中对应记录。

所有结果与预期一致后，为当前 canonical path 生成带 HMAC 的目录清单，状态保持 `creating`。完成本地改动及环境文件初始化、移动到最终路径并为新路径重新签名后，才原子提交最终记录并进入 `ready`。初始化失败时只能依据 provisional 记录清理精确 staging worktree。代码初始化成功后立即在同一元数据事务中建立 Handoff generation 0 双端基线，再允许首轮任务开始；因此创建时已经携带的本地改动不会在首次 Handoff 中再次迁移。

### 10.3 携带当前未提交改动

用户选择带本地改动的当前分支时，初始化在配置根目录下不可见的 `<worktree-id>.preparing` 路径完成；只有整组文件通过校验后，才使用 `git worktree move` 发布到最终路径、重新校验 Git 元数据并写入 `ready`，不能用文件系统 rename 绕过 Git worktree 元数据更新。事务流程如下：

- 以 `baseCommit` 为基准生成包含二进制信息的 tracked patch；
- 单独列出未跟踪且未忽略文件；
- 在事务日志中记录 staging worktree 的 canonical path、Git worktree 记录、预期文件清单和操作代次；
- 在 staging worktree 中执行 tracked patch dry-run，并在临时准备目录完整复制所有 untracked 文件；
- untracked 文件复制前逐项验证目标仍在工作树内、来源不是符号链接且最终目标不存在；复制完成后校验数量、长度、mode 和内容摘要；
- 所有准备和校验成功后应用 tracked patch，再以仅创建、不覆盖的原子 rename 将准备好的 untracked 文件发布到 staging worktree；
- 重新读取 Git 状态并与源内容摘要一致后，才把 staging worktree 移到最终路径并提交记录；最终路径在此之前对任务不可见；
- 暂存状态首版不迁移，携带后的文件统一作为未暂存改动，并在确认文案中说明；
- 任一步失败时依据事务日志，只对通过外部所有权记录、canonical path、common directory 和 Git worktree 列表联合校验的精确 staging worktree 执行受控回滚；目录清单已创建时还必须验证 HMAC，尚未创建时必须满足第 3.1 节 `creating` 状态的 provisional 恢复授权；不得假定它仍为空；
- 回滚必须确认 staging 目录和 Git worktree 记录都已移除。若回滚未完成，将 staging 记录标记为 `failed` 并隔离，显示手动处理路径，不创建服务器线程，也不把部分结果当作成功工作树。

源本地 checkout 始终保持不变。

### 10.4 复制忽略文件

创建完成后读取仓库根目录 `.worktreeinclude`：

- 使用 `.gitignore` 风格匹配；
- 只复制 Git 确认已忽略且规则明确匹配的文件；
- 自动加入忽略的 `AGENTS.override.md`；
- 不复制源符号链接；
- 不覆盖已存在目标；
- 目录递归时每个子项重新做边界和符号链接检查；
- 复制结果不进入普通运行日志，只记录数量和失败的相对路径；
- 任一敏感文件失败不回滚代码工作树，但在首次任务启动前明确警告环境可能不完整。

### 10.5 绑定并启动任务

完成 Git 与文件初始化后：

1. 在 `WorktreeMetadataStore` 的一个事务中保存工作树记录、完整 `InitialTurnEnvelope`、带操作代次的 pending initial task 和项目线程索引占位；
2. 将 phase 与 `requestMayHaveBeenDispatched` 原子更新为 thread 可能已发送后，以工作树路径调用 `thread/start.cwd`；同一 pending operation 未完成或对账前禁止再次调用；
3. 收到线程 ID 后，在同一个元数据事务中把 ID 写入 pending record、`ThreadEnvironmentBinding`、工作树记录和项目线程索引，并把 phase 更新为 thread 已绑定；
4. 将 phase 原子更新为 turn 可能已发送后，以同一路径和持久化的 `InitialTurnEnvelope` 调用 `turn/start.cwd`；
5. App Server 返回已接受的 turn ID 后，在一个事务中记录该 ID、更新线程状态并删除 pending initial task；随后才清空 Composer 并进入 `active`。

应用启动时必须先对账未完成的 pending initial task，再允许重试发送。thread 阶段以其 cwd 调用 `thread/list`，排除已经绑定的线程，并使用 startedAt、工作树 ID 和“托管工作树只绑定一个聊天”的约束查找候选：唯一候选则补齐绑定；多个候选时阻止发送并要求用户选择，不得猜测或静默新建。若 thread 请求可能已发送但没有候选，必须在 App Server 重连完成后再次查询并确认列表游标已经覆盖 `startedAt`，才允许沿用原 operation 重试；查询失败、结果可能截断或覆盖范围无法证明时继续阻止发送。

turn 阶段必须读取已绑定线程的 turns/items：若已经存在与 operation、时间和持久化输入摘要唯一匹配的首轮 turn，则补记 turn ID 并完成事务；若可以证明请求从未发送，才使用原 envelope 发送；若请求可能已发送但无法确认结果，则继续阻止输入并提供“检查任务/确认重试”，不能静默重发。若协议提供幂等键，`operationId` 必须作为 `thread/start` 和 `turn/start` 的稳定幂等键；协议不提供时以上述对账作为保守边界。

如果 `thread/start` 已成功但本地持久化失败，必须阻止继续发送并保留 pending 与工作树记录，不能退回源目录或立即重复创建线程。

## 11. 在工作树中创建分支

托管工作树默认 detached。用户点击“在此创建分支”时：

- 校验任务不在运行；
- 校验名称符合 `git check-ref-format --branch`；
- 校验分支不存在且未被其他 worktree 占用；
- 显式展示将要创建的分支名；
- 执行等价于 `git switch -c <branch>`；
- 成功后刷新审查、分支状态和工作树记录；
- 失败时保留 detached HEAD 和全部文件改动。

应用不能为避免占用错误而私自切换其他工作树的分支。

## 12. Handoff 设计

Handoff 是代码与任务执行环境的迁移，不是单纯修改界面标签。

每个聊天的 Handoff 使用单调递增的 `generation` 和双端检查点：generation 0 在工作树初始化完成且任务尚未开始时建立；以后 `localBaseline` 记录上次成功移交后的本地 checkout 状态，`worktreeBaseline` 记录同一时刻的工作树状态。检查点保存 tracked/untracked 清单、摘要和生成下一次增量所需的受保护 preimage。两份基线不要求整个仓库内容相同，因此本地原有且未参与迁移的改动不会在返程时被误当成任务改动。

### 12.1 通用前置条件

- 绑定源目录或目标目录的所有任务均已停止；开始写入前按 canonical path 排序同时取得两端 Handoff/Git 写锁，并持有到元数据提交或目标回滚验证结束；
- 源与目标属于同一 Git common directory；
- 源基准提交仍可访问；
- 没有正在进行的 Git 写操作；
- 目标目录状态已重新读取，不能使用缓存状态；
- 不存在未完成的 Handoff 事务，且当前检查点 generation 与操作开始时一致；
- 用户确认忽略文件不会随 Handoff 自动移动，除非它们受 `.worktreeinclude` 管理。

### 12.2 Worktree → Local

1. 从 generation 0 开始始终计算工作树当前状态相对 `worktreeBaseline` 的增量，不再以 `baseCommit` 的完整 Diff 代替首次增量，也不再次发送较早 generation 已迁移的变化；
2. 普通 ignored 文件不进入增量；
3. 使用 `localBaseline` 检测本地从上次成功移交后发生的变化，并与本次源增量按路径和文件类型求交集；
4. 有重叠或任一基线摘要不可信时停止并列出冲突文件，不覆盖、不 stash、不 reset；
5. 为所有待修改目标记录受保护的 preimage 和事务日志，准备 tracked patch 与 untracked 文件，并完成完整 dry-run、边界及摘要校验；
6. 应用增量。中途失败时按 preimage 回滚本次已写入的精确路径并验证目标回到 `localBaseline` 对应状态；回滚无法验证则进入 `failed` 并禁止发送；
7. 迁移结果作为本地未暂存改动，不自动提交；
8. 重新读取两端状态，验证本次迁移路径内容一致；
9. 在一个存储事务中写入 `generation + 1`、新的 `localBaseline`、新的 `worktreeBaseline` 和指向 `local` 的线程环境绑定；
10. 事务提交后 App Server 后续 turn 才使用本地路径；原工作树保留到用户确认或清理策略处理。

### 12.3 Local → Worktree

目标是该聊天原有托管工作树；若目录已清理，先从快照恢复同一个工作树身份。以本地当前状态相对 `localBaseline` 计算增量，并以 `worktreeBaseline` 检测目标在上次成功移交后的独立变化；只有无重叠时才应用。成功后同样原子递增 generation、更新双端基线并切换绑定。不能重新应用首次相对 `baseCommit` 的完整 Diff，也不能为同一聊天静默创建第二个工作树。

### 12.4 失败原则

- dry-run 失败：两边均不修改；
- 应用阶段异常：保留源并按事务 preimage 回滚目标；无法验证回滚时目标进入需要人工检查的 `failed` 状态；
- 代码成功但绑定更新失败：继续绑定源目录并禁止发送，提供“完成移交”恢复操作；
- 绑定与新检查点必须在同一事务提交；重启时根据 Handoff 日志、目标摘要和 generation 决定完成提交或回滚，不能重复应用增量；
- 不使用 `git reset --hard`、`git clean -fd` 或自动 stash 解决冲突；
- 不在用户不知情时创建合并提交。

## 13. 快照、清理与恢复

### 13.1 自动清理资格

托管工作树同时满足以下条件才可清理：

- 没有运行中任务；
- 关联聊天未置顶；
- 不是永久工作树；
- 不处于创建、Handoff、快照或恢复状态；
- 已归档，或数量超过用户配置的保留上限；
- 所有权清单、记录和 Git worktree 列表一致。

### 13.2 删除前快照

快照至少包含：

- worktree ID、项目 ID、线程 ID；
- base ref、base commit 和当前 HEAD；
- 当前分支或 detached 状态；
- 可独立校验的 Git bundle，或由应用持有的隐藏引用 `refs/codex-desk/snapshots/<snapshot-id>`，确保从 base commit 到 current HEAD 的提交图在快照有效期内可达；
- 仅表示 current HEAD 之后 staged/unstaged 状态的 tracked binary patch；
- 未跟踪文件清单和内容；
- `.worktreeinclude` 来源清单；
- 文件数量、总字节数和内容摘要；
- 创建时间和应用版本。

快照完整性校验成功并持久化后，状态才可进入 `removable`。仅记录提交哈希不算完成快照；必须验证 bundle 可以读取对应提交，或隐藏引用准确指向 current HEAD。分支引用本身仍存在时也保留提交图保护，避免恢复逻辑依赖用户随后是否删除该分支。

### 13.3 删除

- 只允许删除配置根目录下，且外部权威记录、HMAC 清单、canonical path、common directory 与 Git worktree 列表全部匹配的精确工作树路径；
- 优先使用 `git worktree remove <path>`；
- 有未提交改动时，只有快照验证成功后才允许受控强制移除；
- 删除后确认目标目录不存在，再对已知记录执行受限 prune；
- 删除失败保留记录和快照，不循环重试破坏现场；
- 不递归删除 `$CODEX_HOME`、工作树根目录、项目根目录或解析后的空路径。

### 13.4 恢复

重新打开目录已删除的聊天时：

1. 显示“工作树已清理，可恢复”；
2. 校验源仓库、base commit 和快照中的提交图；Git 对象已经缺失时从 bundle 导入；
3. 以相同 worktree ID、快照 current HEAD 和原 branch/detached 语义创建新目录；若原分支已被其他 worktree 占用，保持 detached 并明确提示，不抢占分支；
4. 只应用 current HEAD 之后的 staged/unstaged patch 和未跟踪文件，并校验摘要；
5. 恢复线程环境绑定；
6. 成功后才允许继续任务。

源仓库或基准提交缺失时，不伪造恢复成功；允许用户导出快照或重新定位源仓库。

## 14. 永久工作树

项目更多菜单提供“新建永久工作树”：

- 创建时要求名称和起始分支；
- 默认仍以 detached HEAD 开始，用户可随后创建分支；
- 创建后作为独立 `WorkspaceConfiguration` 出现在项目栏；
- 可以启动多个聊天；
- 不受最近 15 个托管工作树的清理上限影响；
- 归档其中的聊天不删除工作树；
- 手动移除项目前显示 Git 状态、路径和磁盘占用；
- 从项目栏移除默认只移除配置，不删除磁盘；“删除工作树”作为单独的破坏性操作二次确认。

## 15. 错误与恢复状态

| 场景 | 用户反馈 | 可用操作 |
|---|---|---|
| 非 Git 项目 | 工作树需要 Git 仓库 | 返回本地 |
| 创建目录不可写 | 显示目标根目录与原因 | 更改设置、重试 |
| 分支失效 | 起始分支已变化 | 重新选择 |
| 携带本地改动冲突 | 工作树未绑定，源目录未改变 | 查看文件、重试 |
| setup/忽略文件缺失 | 环境可能不完整 | 查看详情、仍然继续 |
| 工作树目录丢失 | 工作树已被外部删除 | 从快照恢复 |
| 所有权不匹配 | 目录不再由 Codex Desk 管理 | Finder 中显示 |
| 分支被占用 | 分支已在另一工作树中使用 | 创建其他分支、Handoff |
| Handoff 有重叠修改 | 列出冲突路径 | 返回处理，不自动覆盖 |
| 快照失败 | 保留工作树 | 重试、导出诊断 |
| 清理失败 | 保留记录和快照 | Finder 中显示、重试 |

错误提示必须包含下一步，不能仅展示 Git stderr。诊断日志需要脱敏工作树中通过 `.worktreeinclude` 复制的凭据路径和内容。

## 16. 并发与一致性

- 同一工作树同一时刻只允许一个结构性操作；
- 创建、恢复、Handoff、删除使用以 worktree ID 为键的互斥锁；
- 同一源仓库可以并行创建不同 worktree ID，但 `git worktree` 写操作应串行，避免 `.git/worktrees` 竞争；
- 工作树内普通 Git 写操作继续复用现有全局 Git 操作锁，并按执行目录隔离；
- 任务开始后固定执行目录，窗口切换、项目刷新或设置更新不能中途改变；
- 线程恢复、后台通知和审批必须根据线程环境绑定路由；
- 旧操作完成时若项目、线程、worktree ID 或操作代次不匹配，丢弃 UI 回写但完成必要的资源登记；
- 应用退出时不强杀仍在执行的 Git 写操作；若无法等待完成，记录恢复状态供下次启动对账。

## 17. 实施文件规划

建议新增：

```text
lib/src/domain/local_worktree_record.dart
lib/src/domain/thread_environment_binding.dart
lib/src/domain/worktree_settings.dart
lib/src/services/local_worktree_service.dart
lib/src/services/worktree_metadata_store.dart
lib/src/services/local_worktree_repository.dart
lib/src/services/thread_environment_repository.dart
lib/src/services/project_thread_index_repository.dart
lib/src/services/pending_initial_task_repository.dart
lib/src/services/worktree_snapshot_store.dart
lib/src/services/worktree_handoff_store.dart
lib/src/application/worktree_coordinator.dart
lib/src/presentation/worktree/worktree_picker.dart
lib/src/presentation/worktree/worktree_status.dart
lib/src/presentation/worktree/worktree_handoff_dialog.dart
lib/src/presentation/worktree/worktree_settings.dart
```

现有大文件不继续堆积完整工作树逻辑。`codex_workspace.dart` 只组合入口和界面，`app_controller.dart` 只桥接当前任务环境与 App Server。

## 18. 实施顺序

### WT-1：身份、存储与 Git 原语

- 建立工作树与线程环境模型；
- 实现仓库、common directory、分支和 worktree 列表读取；
- 实现 detached worktree 创建；
- 实现所有权清单与持久化；
- 实现历史 schema 迁移、`ProjectThreadIndexRepository` 和 pending initial task 对账；
- 覆盖路径、符号链接、空格和 Git 错误测试。

### WT-2：新任务入口与执行目录绑定

- 增加本地/工作树选择器；
- 增加起始分支选择；
- 首次发送时按需创建；
- 将 `thread/start`、`turn/start`、历史和审批绑定到执行目录；
- 创建失败完整恢复 Composer。

### WT-3：本地改动与环境文件

- 安全携带 tracked、binary 和 untracked 改动；
- 实现 `.worktreeinclude`；
- 自动复制忽略的 `AGENTS.override.md`；
- 显示多附加目录的非隔离边界。

### WT-4：工作树内完整任务流

- 审查和 Git 操作切换到任务执行目录；
- 增加路径、分支、打开和后台终端操作；
- 实现在此创建分支；
- 验证提交、推送和 PR。

### WT-5：快照、清理与恢复

- 实现受保护快照；
- 实现默认最近 15 个保留策略；
- 归档触发清理；
- 缺失工作树恢复；
- 应用启动时对账外部删除与 Git stale record。

### WT-6：Handoff

- Worktree → Local；
- Local → 原工作树；
- 重叠改动检测；
- 双端检查点与增量 generation；
- 原子绑定迁移和失败恢复。

### WT-7：永久工作树与设置

- 项目菜单创建永久工作树；
- 独立项目记录；
- 工作树根目录和保留数量设置；
- 磁盘占用、手动移除和删除确认。

## 19. 测试清单

### 19.1 单元测试

- 普通仓库、子目录、裸仓库和非 Git 目录识别；
- 当前分支、远端 ref、detached HEAD 和失效 ref；
- common directory 与工作树路径校验；
- 目标路径包含空格、中文、连字符和换行拒绝策略；
- tracked、staged、unstaged、binary、rename、delete 和 untracked 携带；
- `.worktreeinclude` 匹配、否定规则、目录、符号链接和越界；
- 所有权清单伪造、缺失和版本迁移；
- Keychain 密钥缺失、外部权威记录不匹配和 HMAC 校验失败时拒绝删除；
- 保留上限、置顶、运行中、永久和归档清理资格；
- 快照摘要、损坏检测和恢复；
- detached HEAD 多提交经过 Git GC 后仍可从 bundle/隐藏引用恢复原提交图；
- Handoff 重叠文件、无重叠文件、目标变化和部分失败；
- 创建时携带的本地改动不会在首次 Worktree → Local Handoff 中重复应用；
- Handoff 往返只迁移上一 generation 后的增量，重复恢复事务不会再次应用；
- 同一分支占用与 detached 分支创建。

### 19.2 Controller / Provider 测试

- 首次发送成功后 `thread/start.cwd` 与 `turn/start.cwd` 均为工作树；
- 创建失败不发送线程、不清空 Composer；
- 项目任务列表聚合本地目录、现存工作树 cwd 和项目线程索引，并按线程 ID 去重；
- 工作树清理并重启后，其聊天仍显示在源项目且可进入快照恢复；
- 后台、归档和搜索结果中的工作树线程仍归属于稳定源项目 ID；
- 历史任务恢复到原工作树而不是当前本地项目；
- 切换任务后迟到创建结果不污染当前任务；
- 工作树任务的审批、Git 刷新和审查均路由到正确目录；
- Handoff 成功前继续绑定源目录；
- 快照或删除中禁止重复操作；
- 运行中、置顶和永久工作树不被自动清理；
- 应用重启后恢复工作树记录与线程绑定；
- 在 `thread/start` 成功到绑定提交之间退出后，对账并恢复原线程，不创建重复线程；
- 在 `turn/start` 调用前后退出时恢复原输入并对账已有 turn，不丢失或重复首轮任务；
- Handoff 期间源或目标目录存在运行任务时拒绝开始，两端锁释放前不能启动新任务；
- 旧版本无绑定历史安全迁移为 Local；
- 路径键历史迁移到稳定项目 ID 时可合并、可回滚且重复执行结果一致。

### 19.3 Widget 测试

- 非 Git 项目禁用工作树入口；
- 新任务切换本地/工作树时保留 Composer 内容；
- 多目录项目显示仍在本地工作的目录数量；
- 创建、初始化、失败和重试状态不造成布局跳动；
- 任务顶部正确显示本地、工作树、分支和 detached 状态；
- 运行中禁用 Handoff、删除和创建分支；
- Handoff 冲突展示具体文件；
- 工作树缺失显示恢复入口；
- 永久工作树出现在项目栏且不与源项目历史混淆；
- 窄窗口、键盘焦点、tooltip 和语义标签完整。

### 19.4 真实 Git 集成测试

必须在临时目录创建真实仓库验证：

- 两个工作树同时修改不同文件，彼此不可见；
- 同一源仓库并发创建多个 detached 工作树；
- 从含本地改动的分支创建且源目录不变；
- 工作树创建分支后原 checkout 无法同时签出；
- 路径包含空格和 Unicode；
- binary 与未跟踪文件快照恢复；
- 删除工作树后 `git worktree list --porcelain` 无陈旧项；
- 外部手动删除目录后的启动对账；
- 超时进程被终止且记录可恢复。

## 20. 验收标准

- 用户可在同一仓库同时运行至少两个工作树任务，而文件、index 和 HEAD 互不干扰；
- 用户在原本地目录继续编辑、构建和提交时，工作树任务不会改变其文件；
- 每个任务的 App Server cwd、Git 审查和 Git 写操作始终指向同一执行目录；
- 从带未提交改动的分支创建工作树时，源目录零写入且工作树内容完整；
- `.worktreeinclude` 只复制明确允许的忽略文件，不复制符号链接或泄露内容；
- 任何 Handoff 冲突都在写入前发现，不覆盖本地改动；
- Local ↔ Worktree 往返只迁移上一代检查点之后的增量，不重复应用已经同步的 Diff；
- 自动清理不会删除运行中、置顶、永久或非本应用拥有的工作树；
- 工作树清理和应用重启后，聊天仍保留在源项目并可触发快照恢复；
- 删除前快照可在全新目录恢复并通过摘要校验；
- 多目录项目清楚说明只有主仓库被隔离；
- 深浅主题和窄窗口下入口、状态、错误与恢复操作均可读可达；
- 完整 `flutter analyze`、`flutter test` 和真实 Git 集成测试通过后才可标记交付。

## 21. 风险与发布策略

主要风险：

- Git worktree 元数据损坏或外部删除；
- Handoff 覆盖本地未提交改动；
- `.worktreeinclude` 复制敏感文件；
- 工作树依赖与构建缓存占用大量磁盘；
- 线程历史按源项目或路径归属错误；
- 多附加目录造成“已隔离”的错误安全感；
- 清理器误删其他客户端或用户创建的工作树。

发布采用功能开关：

1. 内部开发版仅开放 WT-1 至 WT-4，不启用自动清理和 Handoff；
2. 真实仓库回归稳定后开放快照恢复和手动清理；
3. 验证跨重启、冲突和异常终止后开放自动清理；
4. Handoff 独立灰度，不与基础工作树创建同时首次发布；
5. 永久工作树和已安排任务最后开放。

首版即使未开放 Handoff，也必须允许用户在 Finder/IDE 中打开工作树、创建分支、提交和推送，确保任务结果不会被锁在应用内部。
