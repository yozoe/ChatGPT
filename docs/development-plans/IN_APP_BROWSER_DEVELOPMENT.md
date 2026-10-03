# 内置浏览器开发说明

## 状态

本文档定义 Codex Desk 的 macOS 内置浏览器开发范围与验收标准。阶段 0 的 WebView 技术验证已完成；当前已加入右上角工作区入口、智能体按需唤起适配层和设置开关。设置中的“集成 > 浏览器”只管理能力说明和权限策略，不手动创建 WebView。适配层已接入明确的 `browser/open`、`browser/navigate`、App Server `thread/start.dynamicTools` 的客户端 `browser` namespace 注册，以及 `item/tool/call` 动态浏览器工具调用；网页链接偏好、历史、浏览数据清理、下载目录/记录和显式标签恢复已接入。真实 Flutter/WebKit 组合 smoke、Flutter 插件到 Dart 的 `onDownloadStartRequest` 回调、Dart 下载成功/取消/HTTP 失败组合、原生 `WKDownload` 委托和外部 AX 审计均已通过；`tool/macos_browser_ax_audit.swift` 从独立宿主递归观察到真实 integration WebView 的 `AXWebArea`、`AXGroup`、`AXStaticText` 和 `AXLink` 后代，浏览器闭关验收完成。

补充验收：`integration_test/browser_macos_test.dart` 通过受控本机 HTTP attachment 验证真实 WebKit platform view 的 `onDownloadStartRequest` 已抵达 Dart，并覆盖 Dart 传输成功、取消和 HTTP 失败；`integration_test/browser_ax_host_test.dart` 配合外部 AX 审计工具已验证真实网页后代节点可从系统宿主枚举。

系统 AX 审计命令：先执行 `CODEX_BROWSER_AX_HOLD=1 flutter test integration_test/browser_ax_host_test.dart -d macos`，该专用宿主会加载 `https://example.com` 并保持原生窗口；再定位其 `chatgpt` PID，执行 `swiftc -O -framework AppKit -framework ApplicationServices tool/macos_browser_ax_audit.swift -o /tmp/macos_browser_ax_audit`，随后运行 `/tmp/macos_browser_ax_audit --pid <应用 PID> --timeout 12 --max-depth 20`。审计宿主必须在“系统设置 > 隐私与安全性 > 辅助功能”中获准；成功时输出真实 WebKit 的 `AXWebArea` 及子树统计，失败时打印已观察到的宿主树和明确原因。工具已用 Chrome 页面和真实 Flutter/WebKit integration 宿主完成正向校验；真实页面输出包含 `AXWebArea children=7`、多个 `AXGroup`/`AXStaticText` 和 `AXLink` 后代。

首个交付目标是在 Codex Desk 内显示网页的浏览器工作区，可由用户从右上角工作区菜单直接打开，也可由智能体在任务执行中按需唤起。设置页只管理能力，不承担手动打开入口；浏览器不会替代 Chrome，也不会在用户未确认时执行高风险网页操作。

动态浏览器工具的受限名称兼容点号、斜杠、下划线、连字符和冒号分隔形式；该兼容层不改变 allowlist 边界，未知工具名、`computer-use` 活动和无 ID 通知仍不会获得导航权限。

## 目标与边界

### 首期目标

- 在 macOS 上使用原生 `WKWebView` 渲染 HTTP/HTTPS 页面。
- 提供地址栏、打开/关闭标签页、前进、后退、刷新、停止加载和在默认浏览器中打开。
- 将 HTTP/HTTPS Markdown 链接和应用内“打开网页”操作按用户偏好发送至内置浏览器或系统默认浏览器。
- 在设置的“集成 > 浏览器”页面管理启用状态、网页链接打开位置、本地服务器 URL 打开位置、历史、浏览数据和下载目录。
- 维持独立于系统浏览器的持久化网页数据、历史与下载记录，并提供明确的清除与删除操作。
- 沿用 Codex 桌面端的信息层级、键盘焦点、悬停反馈和深浅色表面节奏；浏览器内容本身保持网站原样，不注入应用主题。

### 首期不做

- 不读取、导入或复用 Chrome、Safari 或系统默认浏览器的 Cookie、密码、扩展、书签和历史。
- 不做密码管理器、联系人自动填充、浏览器扩展商店、多用户 Profile 或跨设备同步。
- 不自动把页面正文、Cookie、表单值、下载内容或截图发送给 Codex App Server。
- 不让任务在无用户确认的情况下点击、输入、上传文件、登录、支付、下载或访问内网资源。
- 浏览器导航请求须先显示与 Codex 风格一致的底部权限卡片；“允许一次”仅允许当前请求，“允许所有网站”才写入本地会话范围策略，拒绝或 `Esc` 均不加载页面。
- MCP 发起的 URL 访问确认复用同一 Browser 权限卡片；需要填写字段的 MCP 结构化表单不伪装成访问权限卡片。
- 不承诺 Windows/Linux 实现；在 macOS 版本稳定、并完成各平台 WebView 能力评估前，其他平台继续使用外部浏览器。

## 当前基础

| 位置 | 当前行为 | 对浏览器开发的影响 |
| --- | --- | --- |
| `lib/src/presentation/settings/codex_workspace_settings_page_state.dart` | “浏览器”仅显示智能体调用状态和能力边界 | 后续接入 Riverpod 偏好、历史和下载设置。 |
| `url_launcher` | 帮助、认证、Markdown 等链接使用 `LaunchMode.externalApplication` | 需收敛为统一的 `BrowserLinkOpener`，再按偏好决定内部或外部打开。 |
| `macos/Runner/Release.entitlements` | 声明网络客户端 entitlement，但应用未启用 App Sandbox | 加载远程网页不需新增网络 entitlement；下载目录选择不是操作系统强制的权限边界，必须由应用下载服务校验和限制。 |
| Application Support 与 Riverpod | 已用于偏好与加密对话历史 | 浏览器偏好、历史、下载元数据须有独立 store 与 Provider，不能混入对话缓存。 |

## 交互设计

### 设置页

“集成 > 浏览器”与官方 Codex 的浏览器设置保持相近信息层级，但只展示本应用真实支持的能力：

1. **允许智能体调用内置浏览器**：总开关。关闭时忽略浏览器调用事件，不创建或恢复 WebView；已有网页标签关闭前须二次确认。
2. **网页 URL 和链接打开位置**：`内置浏览器` 或 `系统默认浏览器`。默认值为系统默认浏览器，避免升级后突然改变用户的链接去向。
3. **本地 URL 打开位置**：对 `localhost`、回环 IP 与私网地址单独设置。默认系统默认浏览器，避免无意将开发环境页面放入应用浏览器。
4. **浏览数据**：显示独立数据空间的说明与“清除浏览数据”操作。清除前允许选择 Cookie/网站数据、缓存、历史和下载记录；不删除已实际保存的下载文件。
5. **浏览历史**：打开可搜索的浏览历史页；单条删除和清空均须确认。
6. **下载**：配置下载目录与“每次下载前询问保存位置”。默认每次询问；只有用户显式选中的目录才能成为记住的位置。所有下载目标只可由受控下载服务创建，必须在写入前后规范化、重新校验父目录与符号链接边界；不得接受 WebView、网页或任务直接传入的任意本地路径。

密码管理、联系人自动填充等官方界面项目在本应用未实现前不显示为可管理功能，也不应使用误导性的“管理”按钮。

### 浏览器工作区

- 从右上角工作区菜单或智能体浏览器调用打开时，在会话右侧工作区新增并选中“浏览器” Tab，不替换会话页；草稿、附件、滚动位置和运行中的任务保持不变。收起右栏或切换工作区 Tab 后 WebView 仍保活；未来接入链接和历史时沿用同一承载层。
- 保活的隐藏浏览器不参与焦点链，不响应地址栏输入或浏览器快捷键。
- 顶部工具栏顺序为：标签、后退/前进、刷新或停止、地址栏、在默认浏览器打开、更多菜单。控件拥有可见 tooltip、键盘焦点和语义标签。
- 地址栏仅接受 `http` 与 `https`；省略 scheme 的普通主机名可补全为 `https`，其他 scheme 交给系统默认应用并先显示说明。
- 所有主框架跳转与重定向都在 WebKit 放行前执行 URL 和 DNS 私网检查。
- 新窗口请求默认在当前浏览器工作区的新标签打开；无法安全处理的 scheme、认证回调或外部应用链接不在内置页静默打开。
- 加载错误显示页面内错误状态和“重试 / 在默认浏览器打开”，不把网络错误写入聊天时间线。

## 技术方案

### 分层

```text
链接 / 地址栏 / 历史
          │
BrowserLinkOpener ── BrowserPreferencesNotifier (Riverpod)
          │                         │
          │                         └── BrowserPreferencesStore
          ▼
BrowserWorkspace ── BrowserTabController ── BrowserWebViewPort
                                                   │
                                      macOS WKWebView adapter
                                                   │
                              WKNavigation / WKDownload / WKWebsiteDataStore
```

- 跨组件的偏好、启用状态、加载/错误、标签与历史状态由 Riverpod 管理；单个地址栏的临时编辑文本、悬停与局部动画可留在 Widget 状态。
- 遵循仓库约定：每个新增 Dart 类单独放入公开命名的文件；不新增私有类或 `part` library。
- `BrowserWebViewPort` 隔离 Flutter UI 与平台 WebView，以便 Widget 测试使用 fake 实现，并为 Windows/Linux 预留替换空间。
- 浏览器偏好、可搜索历史和下载元数据存入独立的 Application Support store；历史与下载元数据沿用本应用本地历史的 AES-GCM 加密存储和密钥边界。网页 Cookie、缓存和网站存储只通过 `WKWebsiteDataStore` 管理，不由 Dart 自行复制、解析或上传。

### WebView 实现决策

先完成一个 macOS 技术验证，比较具有 macOS 支持的 WebView 插件与项目内原生平台视图桥接。选择必须同时满足：稳定的 `WKNavigationDelegate`、新窗口拦截、下载回调、Cookie/数据清除、错误回传、键盘焦点及可测试的控制器生命周期。

若插件无法覆盖下载、数据清除或生命周期需求，则实现薄的原生 `WKWebView` adapter；Flutter 层不得直接依赖具体插件 API。任何新增第三方依赖都须锁定版本、完成许可证检查，并在 macOS Debug 构建中验证。

### 数据与隐私

- 该浏览器是应用独立 Profile，不共享 Chrome/Safari 的身份状态，也不尝试绕过网站的登录或 MFA 流程。
- 历史只保存用户可见标题、`origin + path`、访问时间和可选 favicon 引用；不保存页面正文、表单内容、Cookie、query 或 fragment。标题与路径本身仍可能透露用户访问过的资源，属于加密的本地浏览历史而非无敏感数据。
- 写入历史前一律移除 query 与 fragment，而不是维护不完整的敏感参数黑名单。完整导航 URL 只在 WebKit 进程的当前导航内存中使用，不写入应用日志、历史元数据或下载记录。
- “清除浏览数据”调用 WebKit 数据存储的删除 API 并删除相应应用元数据；失败时必须保留并显示原因，不能在未成功清除时声称已清除。
- 下载开始前显示来源主机、建议文件名和目标位置。用户取消保存即取消下载；下载记录不等于文件拥有权，删除记录绝不删除下载文件。

下载服务必须自行创建最终目标：规范化用户选择的目录和建议文件名，拒绝绝对路径、`..`、NUL、目录穿越和符号链接逃逸，并在下载完成前再次检查目标仍位于获准目录内。由于 macOS 桌面构建未启用 App Sandbox，这一策略是产品代码必须执行的约束，不能依赖 `files.user-selected.read-write` entitlement。

### URL 与本地地址分类

“本地 URL 打开位置”只决定用户点击链接时使用内置还是系统浏览器，不能作为访问控制或受控浏览器的安全边界。分类器必须在输入、重定向和新窗口请求时重复运行，并至少识别：`localhost` 及 `.localhost`、IPv4 回环 `127.0.0.0/8`、IPv6 回环 `::1`、IPv4 私网 `10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、共享地址 `100.64.0.0/10`、IPv4/IPv6 链路本地地址，以及 IPv6 唯一本地地址 `fc00::/7`。IP 字面量按地址而非字符串前缀判定；主机名先规范化再由系统解析，并在每次重定向后重新判定。

DNS 结果可能在导航后变化，WebView 的主机名分类无法可靠防御 DNS rebinding。因此，v1 只把该分类用于打开位置和用户提示；未来受控浏览器在没有可验证的网络层目标地址限制前，一律不允许任务访问本地、私网或解析到这些地址的站点。

### 任务与浏览器操控边界

内置浏览器渲染不等于“Codex 可操控浏览器”。后者是单独的高风险能力，必须在 v1 稳定后设计并交付：

- 仅在用户为当前任务显式开启、且当前标签可见时建立受限控制会话。
- 页面读取、点击、文本输入、文件上传、下载、导航到私网、登录/MFA、支付和任何提交表单都应有分级可见提示与确认；默认拒绝高风险操作。对本地、私网和解析到保留地址的站点，在具备可验证的网络层限制前一律拒绝。
- Cookie、密码字段、支付信息、下载文件内容和本地文件路径不得作为普通任务上下文自动发送。
- 每次受控动作记录最小可审计信息（时间、标签、域名、动作类型、用户决定），不记录输入内容、Cookie 或页面正文；支持立刻断开控制。

是否能连接官方 Codex 的浏览器控制协议，须以目标版本 App Server/CLI 的公开能力和授权模型为准；不能把截图中的官方开关假定为本项目可直接复用的 API。

## 交付阶段与验收

### 阶段 0：技术验证

验证 WKWebView 可在 Flutter macOS 窗口中创建、获得键盘焦点、加载测试页、处理重定向/新窗口/加载失败、返回导航状态，并能在退出或标签关闭后释放。输出依赖选型与最小集成测试结论。

### 阶段 1：智能体唤起的内置浏览器

浏览器在右栏收起、切换工作区 Tab 或进入其他一级页时仍保持挂载；默认应用重启会清除页内标签，用户开启恢复开关后只恢复安全网页地址和标题。服务端重定向会以最终 URL 收敛加载状态；同一标签的用户与智能体导航共享请求版本，并且侧栏动画的极窄阶段不会布局完整浏览器 chrome。

审批通过但工作区正在切换或重新挂载时，已批准的 URL 会暂存到当前运行时，并在浏览器工作区 handler 重连后回放；关闭浏览器能力或运行时退出会清理暂存请求。

状态覆盖更新：真实插件下载的成功、取消和 HTTP 失败组合已由 macOS integration 验收；Flutter 语义树、原生 accessibility contract 和独立系统 AX 宿主对子孙节点的完整审计也已覆盖。

已交付受限的 App Server/browser 请求适配、设置总开关、网页链接打开位置偏好、右上角工作区入口，以及接近 Codex 客户端的多标签浏览器工作区。工作区提供标签新建/切换/关闭、地址或搜索输入、网页标题、前进/后退、刷新/停止、外部打开、网页新窗口转标签、错误反馈、取消导航过滤和 macOS 常用快捷键；标签只在当前应用生命周期内保活。新线程通过 `thread/start.dynamicTools` 注册客户端拥有的 `browser` namespace（`open`、`navigate`），随后对可回复的 `browser/open`、`browser/navigate` 和明确的 `item/tool/call` 浏览器动态工具请求显示权限卡片；`item/started`、无 ID 的通知及 `computer-use` 活动只作状态展示，绝不据此加载网页。动态工具调用按 `browser`、`browser.open`、`browser.navigate` 及等价分隔符命名识别，也支持 `namespace: browser` 配合 `tool: open|navigate` 的协议形状，并以 `arguments`/嵌套 URL 提取地址（包括 JSON 字符串参数）；批准后以动态工具响应确认并导航。选择“允许所有网站”后，后续明确的浏览器请求仅在当前运行时会话内自动批准；运行时退出、关闭浏览器能力或重新连接后会清除授权。用户点击回复中的 HTTP/HTTPS 链接默认交给系统浏览器，也可在设置切换为内置浏览器，项目内文件链接继续使用原有工作区边界。验收：设置页不直接创建 WebView；智能体触发的请求只有在功能已启用且用户已允许时才会加载，用户也可从工作区入口主动浏览；会话与运行中任务不受切换影响。Chrome 导入条目前只解释独立 Profile 边界，不读取外部浏览器数据。RunnerTests 已验证真实 `WKWebView` 的 HTML 加载、`reload()` 二次导航、停止加载、delegate 解除、视图卸载、accessibility role smoke test 和本机 HTTP attachment 的 `WKDownload` 委托回调；`integration_test/browser_macos_test.dart` 已验证真实 macOS Flutter/WebKit platform view 创建以及本机 HTTP attachment 到 Dart `onDownloadStartRequest` 的成功、取消和 HTTP 失败回调；外部 AX 宿主已验证真实网页的 `AXWebArea`、文本和链接后代。

### 阶段 2：持久化与下载

补充状态：真实 Flutter/WebKit 下载成功、取消和 HTTP 失败组合已经由 macOS integration 验收；系统 AX 宿主对子孙节点的完整审计也已完成。

真实 macOS integration 已补齐下载闭环：WebKit attachment 回调抵达 Dart 后，成功保存、取消传输、HTTP 失败和临时文件清理均在本机 HTTP fixture 上验证。

下载保存确认已接入浏览器工作区：下载会显示来源主机和建议文件名；默认通过原生保存对话框选择目标，也可在设置中选择默认目录并关闭每次询问，记住的默认路径必须解析为真实目录而不能是普通文件。下载横幅可中止进行中的 HTTP 传输，取消会中止请求并删除临时 `.part` 文件；重定向重新执行 URL 安全校验，临时文件完成后才原子移动到目标，重名、取消、目录变化和网络失败不会覆盖已有文件。真实本机 HTTP 传输测试已覆盖失败、取消、重定向、重名保护和目录类型边界；真实 Flutter/WebKit integration 还覆盖 attachment 回调抵达 Dart 后的成功、取消、HTTP 失败和临时文件清理。下载记录独立加密保存，支持查看、单条删除和清空，删除记录不会删除实际文件，HTTP 失败或取消不会提交记录。回复中的 HTTP/HTTPS Markdown 链接也会优先复用保活浏览器 Tab，浏览器能力关闭时回退系统默认应用。浏览历史现已独立加密保存，写入前移除 query/fragment，按最近访问去重，并在浏览器更多菜单提供查看、单条删除和清空确认；更多菜单的“清除浏览数据”允许分别选择 Cookie/网站存储、缓存、浏览/导航历史和下载记录，只有对应清理成功才删除对应应用元数据，下载文件不会被删除。标签跨重启恢复为显式开关，默认关闭；恢复的安全地址和标题会在 WebView 创建后逐个执行安全检查并实际导航，不恢复 Cookie、网站存储或登录状态。验收：重启后按设置恢复允许恢复的浏览状态；清除动作只清除用户勾选范围；下载取消、目标不可写、重名文件和断网均有明确反馈；用户未授权时不写入任意目录。

### 阶段 3：安全强化与可访问性

本轮收尾验证已覆盖真实 WebKit attachment 到 Dart 的下载成功、取消和 HTTP 失败路径；原生 RunnerTests 新增 accessibility tree contract smoke，确认 WebView 暴露 role/children 能力并保持可访问元素。外部 AX 宿主进一步在真实 integration WebView 上递归观察到 `AXWebArea`、`AXGroup`、`AXStaticText` 和 `AXLink` 后代，系统进程边界内的完整网页可访问树已获得实证。
- 原生 contract 进一步验证窗口级 AX children 实际包含 `WKWebView`；外部宿主则验证其下的 WebKit `AXWebArea` 及网页后代可枚举。
- `tool/macos_browser_ax_audit.swift` 通过 `AXUIElementCreateApplication` 读取窗口、内容和可见子树，`integration_test/browser_ax_host_test.dart` 提供可重复的真实页面宿主；一次审计输出包含 `AXWebArea children=7`、多个 `AXGroup`/`AXStaticText` 和 `AXLink "Learn more"`。

Flutter 侧现已遍历浏览器语义树，核对工作区、标签、地址栏、导航按钮、网页内容以及可点击节点的标签/tooltip；错误和下载状态另有 live-region 断言。原生 WebKit contract smoke 与独立 AX 宿主递归审计共同覆盖宿主和 WebKit 子孙树。

因此，阶段 3 的 Flutter 插件下载组合和系统 AX 宿主子孙节点验收均已完成。

已完成 URL/scheme 策略、IPv4/IPv6 本地地址分类、重定向复核、私网提示、错误反馈、常用键盘快捷键、隐藏工作区焦点释放，以及工作区、标签、地址栏、网页内容和下载状态的辅助技术语义；Widget 回归已覆盖 `Esc`、`Cmd+L`、`Cmd+T`、`Cmd+W`、窄窗口、标签关闭、关闭标签后的导航/标题/历史/错误迟到回调、异步导航和工作区切换，平台 contract 测试确认 `Cmd+R` 会调用活动 WebView controller 的 `reload()`，并确认媒体权限回调默认返回拒绝。标签关闭会失效对应导航代次、WebView 身份和下载操作，避免迟到事件写回已关闭标签。RunnerTests 已在真实 WebKit 上覆盖 HTML 加载、底层 `reload()`、停止加载、不可达地址错误回传、delegate 解除、视图卸载、测试 Cookie 的写入/读取和定向删除、accessibility role smoke test、accessibility tree contract 及本机 HTTP attachment 的 `WKDownload` 委托回调；`integration_test/browser_macos_test.dart` 已覆盖真实 Flutter/WebKit platform view 创建、attachment 到 Dart 回调以及下载成功/取消/HTTP 失败组合；外部 AX 宿主已覆盖 `AXWebArea` 及网页文本/链接后代。Flutter 语义树已遍历核对工作区关键节点和可点击标签。验收：快捷键行为与焦点边界明确；窄窗口、标签关闭、异步加载完成和工作区切换不会造成 setState-after-dispose 或错误标签更新。

### 阶段 4：受控浏览器（独立立项）

只有在官方协议可用、权限模型确定、红队式安全评审与逐动作确认测试完成后，才评估交付。它不属于内置浏览器 v1 的发布条件。

## 测试与发布前检查

- 单元测试：URL 分类/脱敏、偏好默认与迁移、历史排序和删除、下载目标验证、链接路由决策。
- Widget 测试：设置开关、外部/内部路由、错误和空历史状态、键盘焦点、标签关闭确认。
- macOS 集成测试：`flutter test integration_test/browser_macos_test.dart -d macos` 验证真实 `MacOSInAppWebViewPlatform` platform view 创建、attachment 到 Dart 回调及下载成功/取消/HTTP 失败组合；`integration_test/browser_ax_host_test.dart` 与 `tool/macos_browser_ax_audit.swift` 额外验证真实网页的 `AXWebArea`、文本和链接后代；RunnerTests 继续覆盖导航、新窗口、重定向、WebView 销毁、网站数据清除、原生 `WKDownload` attachment 回调、无网络与权限失败，并通过 AXUIElement 验证宿主窗口层级。
- 回归：在浏览器与会话间切换时，Composer 草稿、附件、运行中的任务、审查工作区及窗口大小保持正确；异步导航结果不得写回已关闭的标签或已离开的工作区。
- 每次实现变更前后运行 `dart format`、`flutter analyze`、相关 `flutter test`；涉及原生桥接时额外运行 `flutter build macos --debug`。

## 已知决策点

1. 是否在 v1 恢复上次标签：默认不恢复，除非在隐私评审后增加显式开关。
2. 是否允许私网地址在内置浏览器打开：默认外部打开；如需允许，应显示域名/地址确认。该选择不构成安全放行，受控浏览器在具备网络层限制前仍拒绝这些地址和其解析结果。
3. 浏览器入口已由右上角工作区菜单提供；后续若增加链接或历史入口，仍复用同一保活工作区。
4. 是否以及如何接入官方受控浏览器：等待公开 API、权限范围和数据处理约定确认，不预埋未经证实的协议实现。

## 相关文件

- `README.md`：当前能力和安全边界。
- `ROADMAP.md`：唯一任务清单与优先级。
- `lib/src/presentation/settings/codex_workspace_settings_page_state.dart`：设置导航占位入口。
- `lib/src/presentation/timeline/codex_workspace_timeline_support.dart`：当前 Markdown 外部链接打开路径。
- `macos/Runner/Release.entitlements`：macOS 网络与文件访问边界。
