# Android 屏幕桥接、Codex 识别与设备操作技术方案

## 1. 背景与结论

目标是在 Codex Desk 中连接 Android 设备，让 Codex 能够快速读取当前屏幕、执行用户授权的操作，并在每次操作后重新观察设备确认结果。应用内实时预览服务于用户监督，不是 Agent 识别和控制的唯一输入。

本方案建议把能力拆为三个相互独立的平面：

- **观察平面**：通过 ADB 按需抓取无损屏幕帧，并在可用时补充 Android UI 层级；复用 Codex Desk 已有的 `localImage` 输入、图片附件、时间线缩略图和 `turn/start` / `turn/steer` 链路。
- **操作平面**：通过带设备 serial、参数校验、权限门禁和结构化结果的工具执行点击、滑动、长按、系统键和有限文本输入。
- **监督平面**：使用 scrcpy 或应用内预览向用户显示实时画面、当前控制状态和待确认操作。流畅视频预览不阻塞首版观察—操作闭环。

设备权限的可信边界是应用持有的 Device Broker，而不是提示词、技能或通用命令审批。Codex 运行时只能通过受限工具 RPC 请求设备动作；它所在的命令沙箱不能直接访问 USB 设备、ADB Server、`adb`/scrcpy 控制入口或 Device Broker 之外的替代通道。若目标平台无法验证这一隔离，产品只能提供逐次人工确认的实验模式，不能宣称白名单和禁止动作不可绕过。

核心执行循环为“观察 → 决策 → 安全检查 → 操作 → 等待稳定 → 再观察 → 验证”。不建议把 30/60 FPS 原始视频逐帧提交给模型；模型侧只接收用户显式提交、交互完成后或画面实际变化时取得的关键帧。

## 2. 当前工程基础

Codex Desk 已具备以下可复用能力：

- Flutter macOS 桌面应用，应用级共享状态使用 Riverpod。
- `CodexAppServer.startTurn` 和 `steerTurn` 支持追加结构化输入。
- Composer 已把本地图片转换为 `{ "type": "localImage", "path": "..." }`。
- 本地图片已有附件缩略图、放大预览、时间线引用和临时文件生命周期管理。
- macOS 原生侧已有 `FlutterMethodChannel`，可以沿用相同模式封装宿主能力。
- 当前开发机已发现 ADB `36.0.2` 与 scrcpy `3.3.4`，但正式功能不能依赖这些固定安装路径或固定版本。

因此，第一阶段不需要改写模型协议，也不需要引入视频编解码依赖。主要工作是新增设备桥接服务、受控操作工具、Riverpod 状态、设备面板，以及把抓取结果接入现有图片提交链路。

## 3. 范围

### 3.1 第一阶段必须交付

- 自动发现 `adb`，并允许用户手动选择可执行文件作为兜底。
- 列出已连接设备，区分 `device`、`unauthorized`、`offline` 等状态。
- 多设备时显式选择目标设备，只有一个可用设备时自动选中。
- 在应用内显示按需刷新或低频更新的设备画面。
- 提供“截取当前屏幕”和“截屏并询问 Codex”。
- 将截图作为 `localImage` 发送到新任务，或作为 `turn/steer` 图片发送给当前运行任务。
- 在用户开启本次设备会话的控制权限后，支持点击、滑动、长按、返回、Home 和应用切换。
- 每个操作都绑定明确设备 serial，返回结构化结果，并在操作后自动抓帧验证。
- 为 Codex 提供受限的观察和操作工具；M0 可在独立测试环境中使用现有命令工具验证 ADB 动作，但 M1 必须通过参数化白名单接口和隔离后的 Device Broker。
- 截图只写入系统临时目录，不写入用户工作区。
- 断连、旋转、锁屏、ADB 未授权、操作失败和命令超时都有明确的可恢复状态。

### 3.2 后续阶段

- 低延迟连续预览。
- 完整 Unicode 文本输入、剪贴板同步和更低延迟的 scrcpy 控制通道。
- 画面变化检测与交互后自动抓取。
- 启动/停止指定应用和更丰富的设备诊断工具。
- 无线 ADB 配对和连接。

### 3.3 非目标

- 不把完整实时视频持续上传给模型。
- 不在首版采集音频。
- 不在首版模拟多点触控、传感器、摄像头或复杂手势。
- 不绕过 Android 的 USB 调试授权、设备策略或安全页面限制。
- 不默认开启自动控制，不在用户不知情时点击设备。
- 不允许 Codex 运行时直接访问任意 `adb shell`、ADB Server、USB 调试设备或 scrcpy 控制通道；产品接口只开放经过审核的动作白名单。

## 4. 总体架构

```text
┌──────────────── Android Device ────────────────┐
│ screencap / UI hierarchy      input / control │
└───────────────────┬───────────────────────▲───┘
                    │ ADB                   │
┌───────────────────▼───────────────────────┴───┐
│ Device Broker（应用持有 ADB 权限）             │
│ discovery · session · capture · control        │
│ timeout · process ownership · error mapping     │
└───────────────┬──────────────────────────┬─────┘
                │                          │
       latest frame / state          guarded actions
                │                          ▲
┌───────────────▼────────────┐  ┌──────────┴───────────┐
│ Riverpod device state      │  │ Agent Tool Gateway   │
│ device · session · frame   │  │ observe/tap/swipe/key│
│ permission · action log    │  │ wait/verify          │
└───────────────┬────────────┘  └──────────▲───────────┘
                │                          │
       Device Screen Panel          approved tool calls
                │                          │
┌───────────────▼──────────┐  ┌────────────┴────────────┐
│ User preview and consent │  │ Codex App Server        │
│ attach / ask / supervise │  │ sandboxed turn + tools  │
└───────────────┬──────────┘  └────────────▲────────────┘
                │ localImage               │
                └──────────────────────────┘

scrcpy external preview ───── user-only real-time supervision

Codex command sandbox ──X── ADB Server / USB / raw adb / scrcpy control
```

设备桥接不能直接并入 `CodexController`。Device Broker 在 Codex 命令沙箱之外持有 ADB 权限；Riverpod Notifier 管理其异步状态、进程生命周期、控制权限、缓存和错误恢复。Composer 只消费已经产生的图片附件，Agent Tool Gateway 只接受白名单动作。全局“帮我批准”只能处理普通 Codex 权限请求，不得授予或扩大设备控制租约。

## 5. 核心技术决策

### 5.1 第一阶段使用 ADB 截图，不解析 scrcpy 视频协议

抓帧命令：

```bash
adb -s <serial> exec-out screencap -p
```

Dart 侧必须以二进制形式读取标准输出，例如为 `Process.run` 设置 `stdoutEncoding: null`，校验 PNG 签名后再落盘。不能把 PNG 标准输出按文本解码。

选择该路径的原因：

- 直接得到与现有 `localImage` 链路兼容的 PNG。
- 对文字、按钮和错误提示保真度高。
- 无需维护 scrcpy 内部握手、socket 和视频协议兼容性。
- 不需要在首版引入 FFmpeg、VideoToolbox 或 Flutter Texture。
- 失败边界清晰，容易做超时、重试和测试替身。

首版应用内“预览”可以使用最近一帧，以手动刷新为主；启用低频预览时建议 1～4 FPS，并在前一抓帧未完成时丢弃下一次调度，禁止并发堆积。

### 5.2 第一阶段通过 ADB 参数化动作控制设备

第一阶段不让 Agent 用宿主鼠标点击 scrcpy 窗口。窗口坐标会受位置、缩放、标题栏、遮挡、焦点和多显示器影响，无法稳定映射到手机像素。设备操作直接面向明确 serial 执行：

```bash
adb -s <serial> shell input tap <x> <y>
adb -s <serial> shell input swipe <x1> <y1> <x2> <y2> <duration-ms>
adb -s <serial> shell input keyevent KEYCODE_BACK
adb -s <serial> shell input keyevent KEYCODE_HOME
```

这些命令只用于说明底层实现，产品中的 Agent 不直接拼接命令字符串。`AgentToolGateway` 接收强类型参数，校验 serial、动作类型、设备尺寸、坐标和持续时间后，再调用 Device Broker。Device Broker 使用参数数组及 `runInShell: false` 避免宿主 Shell 解析；但 `adb shell` 仍会经过 Android 设备端 Shell，因此所有进入远端 Shell 的值还必须采用动作级严格白名单，不能把 `runInShell: false` 当作远端注入防护。

选择 ADB 作为第一阶段控制后端的原因：

- 与截图使用同一设备选择和连接状态，闭环短。
- 不依赖 scrcpy 窗口焦点，也不要求应用内已经完成视频解码。
- 点击、滑动和系统键协议稳定，易于构造测试替身。
- 每个动作都能设置超时、记录结果并在完成后触发新截图。

M1 发布前必须完成权限隔离验证：从普通 Codex 命令工具尝试直接执行绝对路径 `adb`、复制后的 adb、连接默认或自定义 ADB Server 端口以及访问 Device Broker socket，除已注册工具 RPC 外均应失败。全局自动审批不得改变该结果。

### 5.3 scrcpy 作为实时监督界面，不作为首版控制依赖

如果用户需要立即获得流畅预览，可以由应用启动已安装的 scrcpy，并显式标识为“在独立窗口打开”。应用只管理自己启动的子进程，不关闭用户原本运行的 scrcpy，也不停止全局 ADB Server。

scrcpy CLI 使用 SDL 创建独立窗口，不能稳定地直接嵌入 Flutter Widget 树。通过窗口坐标覆盖、macOS 窗口抓取或辅助功能 API 伪装嵌入会引入焦点、缩放、权限和生命周期问题，不采用这些方案。

scrcpy 的价值是让用户低延迟监督 Agent 正在做什么。后续若 ADB 文本输入或动作延迟无法满足需求，可以实现固定版本的 scrcpy control socket，但不能通过模拟宿主鼠标键盘间接控制 scrcpy 窗口。

### 5.4 真正的内嵌连续视频放在独立里程碑

内嵌 30/60 FPS 预览有两个可实施方向，进入该里程碑前先做技术验证：

1. **原生 H.264 采集插件（推荐验证方向）**：通过 ADB 启动 Android `screenrecord --output-format=h264` 流，macOS 使用 VideoToolbox 解码，通过 Flutter Texture 或原生 Platform View 渲染。控制仍走独立 ADB 命令。
2. **实现固定版本的 scrcpy client protocol**：随应用固定 scrcpy server 版本，接收视频和控制 socket，再用原生解码器渲染。能力更完整，但与 scrcpy 内部协议耦合，升级、打包和兼容测试成本更高。

技术验证需要测量首帧时间、端到端延迟、旋转恢复、连续运行、CPU/内存和进程回收后再决定。不得先把 scrcpy 可执行文件窗口当作嵌入方案。

### 5.5 模型只接收关键帧

支持三种提交语义：

- **附加当前屏幕**：截图进入 Composer，用户可预览、移除，再随下一条消息提交。
- **截屏并询问 Codex**：立即创建新任务并携带截图；默认提示词为“请分析当前 Android 屏幕，说明页面状态和可执行操作”。
- **根据当前屏幕调整方向**：任务运行时把截图放入现有待发送方向栏，用户点击“调整方向”后通过 `turn/steer` 提交。

不允许仅因预览刷新就自动创建 turn 或 steer。持续预览和模型提交必须解耦。

## 6. 模块设计

建议新增以下边界；实际文件名可以在实现时按仓库命名习惯微调：

```text
lib/src/domain/android_device.dart
lib/src/domain/device_action.dart
lib/src/domain/device_screen_state.dart
lib/src/services/android_debug_bridge.dart
lib/src/services/android_ui_hierarchy_reader.dart
lib/src/services/device_broker.dart
lib/src/services/device_frame_store.dart
lib/src/services/device_agent_tool_gateway.dart
lib/src/services/device_tool_transport.dart
lib/src/device_screen_controller.dart
lib/src/presentation/device_screen_panel.dart
test/android_debug_bridge_test.dart
test/device_agent_tool_gateway_test.dart
test/device_screen_controller_test.dart
test/device_screen_panel_test.dart
```

### 6.1 `AndroidDebugBridge`

职责：

- 查找和验证 `adb` 可执行文件。
- 执行 `adb devices -l` 并解析设备列表。
- 对所有命令强制携带已解析的明确 serial。
- 抓取二进制 PNG。
- 封装受允许的控制动作。
- 统一超时、退出码、stderr 脱敏和错误映射。
- 记录并终止本服务启动的子进程，不使用按名称全局杀进程。

建议接口：

```dart
abstract interface class AndroidDebugBridge {
  Future<AdbProbeResult> probe();
  Future<List<AndroidDevice>> listDevices();
  Future<Uint8List> capturePng(String serial);
  Future<AndroidUiHierarchy?> readUiHierarchy(String serial);
  Future<DeviceActionResult> tap(String serial, int x, int y);
  Future<DeviceActionResult> swipe(
    String serial,
    int startX,
    int startY,
    int endX,
    int endY,
    Duration duration,
  );
  Future<DeviceActionResult> pressKey(String serial, AndroidKey key);
  Future<DeviceActionResult> inputText(String serial, String text);
}
```

M1 开放 `probe`、`listDevices`、`capturePng`、`tap`、`swipe` 和限定系统键；UI 层级读取为尽力而为，失败时回退到纯视觉识别。`inputText` 到 M2 才开放严格字符白名单，完整 Unicode 输入留给后续 scrcpy 控制通道。

### 6.2 `DeviceFrameStore`

职责：

- 使用系统临时目录，例如 `<tmp>/CodexDeskDeviceBridge/<session-id>/`。
- 写入 `frame-<monotonic-sequence>.png.part`，校验后原子改名为 `.png`。
- 保留 `latestFrame` 和最多 3 个未被引用的历史帧，避免无限增长。
- 使用引用计数租约管理 `preview`、`composer`、`timeline`、`toolCall` 和 `actionVerification` 五类消费者；任何租约存续时都不得清理对应帧。
- Agent 工具返回图片前先取得 `toolCall` 租约，保持到工具结果被 App Server 确认消费、turn 结束或显式释放；异常退出使用有上限的过期回收作为兜底。
- 动作的前置帧和后置帧取得 `actionVerification` 租约，至少保持到该动作验证完成，不能受“三个未引用帧”环形清理影响。
- 被 Composer 或时间线引用的帧沿用现有附件生命周期，释放引用后才能清理。
- 应用启动时只清理自己的过期目录，并校验规范化路径，不能递归清理宽泛目录。

工具协议优先返回图像 content block 和不透明 `frameId`，不向模型暴露宿主临时路径。若所选 App Server 扩展暂不支持图像 content block，才返回工具专属临时路径，并保证该路径处于运行时允许读取的目录且持有相同消费租约。

### 6.3 `DeviceScreenController`

使用 Riverpod AsyncNotifier/Notifier 管理：

- ADB 探测结果。
- 设备列表与当前 serial。
- `disconnected / unauthorized / ready / capturing / error` 会话状态。
- 最新帧路径、像素尺寸、方向、采集时间和内容哈希。
- 低频预览 Timer 与生命周期。
- 正在抓帧、正在附加或正在发送状态。
- 控制权限开关及其当前会话有效期。

状态转换必须带 session epoch。用户切换设备、设备断连或 Provider 被释放时递增 epoch；旧命令迟到返回时不得覆盖新设备的画面和错误状态。

### 6.4 `DeviceScreenPanel`

遵循 Codex Desk 现有信息层级，建议作为右侧检查器中的独立“设备”页或工作台工具面板，而不是常驻大型浮窗。

面板内容：

- 顶部：设备选择器、连接状态、刷新设备。
- 中部：保持手机比例的屏幕画布；空态、未授权、离线和错误显示在同一区域。
- 底部主操作：“附加当前屏幕”“截屏并询问 Codex”。
- 次操作：“刷新画面”“在 scrcpy 中打开”。
- 控制模式开启时显示清晰的“正在控制设备”状态和立即关闭入口。

快捷键只在面板聚焦时生效，不能抢占 Composer 的 Enter、复制粘贴和应用全局快捷键。

### 6.5 `DeviceAgentToolGateway`

职责：

- 向 Codex 暴露参数化的观察、操作、等待和验证动作，不暴露任意 shell。
- 检查设备会话、控制授权、session epoch 和目标 serial。
- 给每次动作分配 `actionId`，串行执行同一设备的操作。
- 执行动作前保存基准帧，动作后等待画面稳定并返回新帧。
- 根据可信的本地策略决定直接执行、请求逐次确认或拒绝；不接受 Agent 自报的风险等级作为授权依据。
- 返回结构化结果，不让 Agent 通过解析自然语言判断底层命令是否成功。

建议工具集合：

| 工具 | 参数 | 返回 |
| --- | --- | --- |
| `device_observe` | `serial`、是否读取已脱敏 UI 层级 | 图像 content、frame id、尺寸、旋转、哈希、可用控件摘要 |
| `device_tap` | `serial`、frame id、设备像素坐标或 node id、意图说明 | 动作结果、前后帧、是否变化 |
| `device_swipe` | `serial`、frame id、起止坐标、持续时间、意图说明 | 动作结果、前后帧、是否变化 |
| `device_long_press` | `serial`、frame id、坐标、持续时间、意图说明 | 动作结果、前后帧、是否变化 |
| `device_key` | `serial`、frame id、受限键名、意图说明 | 动作结果、前后帧、是否变化 |
| `device_input_text` | `serial`、frame id、受限文本 | 已输入字符范围、失败原因、后置帧 |
| `device_wait_for_change` | `serial`、基准哈希、超时 | 稳定帧或超时状态 |

`意图说明` 只用于展示和审计，不决定授权等级。视觉坐标、无法重新确认的 node、跨 package 操作以及任何本地策略无法确定为安全的动作都强制逐次确认。

### 6.6 `DeviceToolTransport`

M0 必须在真实 App Server turn 中选定并验证一种产品传输，M1 不保留运行期二选一：

1. 首选 App Server 已验证稳定的本地工具扩展。
2. 若该接口不可用，则固定使用随应用签名和发布的 MCP 伴随进程；App Server 从受信任的插件清单启动它，伴随进程只通过权限受限的本地 IPC 连接 Device Broker，自身不持有 ADB 权限。

两种传输都使用相同工具 schema、设备租约和审批语义。M0 需要记录最终选择、版本约束、插件发现方式、进程归属、IPC 路径权限、图像 content 支持、App Server 重启恢复和打包签名方式。不得使用通用 shell、自动发送 steer 或解析自然语言输出作为产品传输。

## 7. 详细数据流

### 7.1 发现与选择设备

1. 面板首次打开时探测 ADB。
2. 执行 `adb devices -l`，解析 serial、transport 状态和可用描述。
3. 没有设备时显示连接引导；`unauthorized` 时提示在手机确认 RSA 授权。
4. 只有一个 `device` 状态的设备时自动选中。
5. 多个设备时要求显式选择，并把 serial 保存为应用偏好；下次启动只有该 serial 仍存在才恢复。

不得把 `adb devices` 输出中的展示名称当作命令目标，所有操作只使用 serial。

### 7.2 抓帧并附加

1. Controller 为当前选择创建 capture token，进入 `capturing`。
2. Bridge 执行带 5 秒超时的 `screencap`。
3. 校验返回非空、PNG 签名正确且尺寸处于合理上限。
4. Frame Store 原子写入临时文件并返回路径。
5. Controller 检查 session epoch 与 capture token；过期结果立即释放，不更新 UI。
6. 用户选择“附加”时，将该路径转换为现有 `_ComposerAttachment`。
7. 最终发送继续走已有 `localImage` 路径，不新增私有模型协议。

### 7.3 低频预览

- 默认关闭；用户打开设备面板后可选择启动。
- 推荐默认 2 FPS，上限 4 FPS。
- 同一时刻只允许一个抓帧请求。
- 计算缩小灰度图的感知哈希；画面未变化时只更新时间，不创建新附件文件。
- 面板隐藏、窗口最小化、应用进入后台或设备断连时暂停。
- 连续失败 3 次后停止自动刷新，进入可手动重试状态。

### 7.4 观察—操作—验证闭环

每个 Agent 操作必须执行完整闭环，不能连续盲点：

1. **观察**：抓取当前 PNG，记录尺寸、旋转、帧哈希；尽力读取 UI 层级。
2. **定位**：优先使用 UI 节点边界的中心点；节点不可用时才使用视觉像素坐标。
3. **安全检查**：确认 serial、控制会话、动作白名单，并由本地策略计算风险等级。
4. **执行**：为动作分配 `actionId`，同一设备串行发送一个参数化指令。
5. **等待**：先等待短暂渲染窗口，再按 100～250 毫秒间隔采样；不使用无条件长时间 `sleep`。
6. **稳定判断**：连续两帧的感知哈希变化低于阈值，或达到 2 秒上限时结束等待。
7. **验证**：把后置帧与目标状态交给 Codex；未达到目标时重新观察和规划，最多自动修正一次。

动作返回建议结构：

```json
{
  "actionId": "action-42",
  "serial": "RFCX114X8ZD",
  "type": "tap",
  "status": "completed",
  "durationMs": 184,
  "screenChanged": true,
  "beforeFrameId": "frame-41",
  "afterFrameId": "frame-42",
  "settled": true
}
```

底层命令退出码为 0 只表示 Android 接受了输入，不表示业务目标已经实现；只有后置观察符合预期，Agent 才能把该步骤视为成功。

### 7.5 坐标与 UI 节点定位

- 所有工具坐标使用**当前设备截图的物理像素坐标**，不能使用 scrcpy 宿主窗口坐标。
- 每个坐标动作同时携带基准帧 ID 或帧尺寸；当前设备旋转或尺寸变化后，旧坐标立即失效并要求重新观察。
- 应用面板中的点击先去除 letterbox 区域，再将 Widget 局部坐标按截图尺寸缩放。
- 坐标必须满足 `0 <= x < width`、`0 <= y < height`，持续时间限制在安全范围内。
- UI 层级可用时，工具返回文本、resource id、class、clickable、enabled 和 bounds；Agent 优先按 node id 操作，Gateway 在执行前重新确认节点仍存在。
- Compose、自绘 Canvas、游戏、WebView 或安全页面可能没有可靠节点，此时回退到视觉定位并加强操作后验证。

UI 层级读取只能使用本次会话的 shell 临时文件或标准输出，读取完成后立即清理；不得把完整层级写入普通日志。`password=true` 节点的文本必须在 Device Broker 内脱敏，原文不得进入工具结果。默认工具结果不包含普通节点原始文本，只返回 resource id、class、状态和 bounds；用户为当前 Provider 明确开启“共享界面文字”后才返回普通文本。

### 7.6 支持的基础操作

| 动作 | ADB 后端 | 第一阶段限制 |
| --- | --- | --- |
| 点击 | `input tap x y` | 必须位于当前帧边界内 |
| 滑动 | `input swipe x1 y1 x2 y2 ms` | 持续时间和距离设上限 |
| 长按 | 起止点相同的 `input swipe` | 默认 600ms，超长需拒绝 |
| 返回 | `input keyevent KEYCODE_BACK` | 允许；执行后重新观察 |
| Home | `input keyevent KEYCODE_HOME` | 允许；UI 明确显示离开当前 App |
| 应用切换 | `input keyevent KEYCODE_APP_SWITCH` | 允许但不自动选择其他 App |
| 输入文本 | `input text` + 独立空格 keyevent | M2 仅允许 `[A-Za-z0-9._@-]`；空格单独发送；其他字符全部拒绝 |
| 启动应用 | `am start` 指定组件 | 后续开放；不接受任意 shell 参数 |

`adb shell` 参数仍受 Android 远端 Shell 解释，因此 M2 不允许把任意 ASCII 直接传给 `input text`。Gateway 只接受完全匹配 `[A-Za-z0-9._@-]+` 的非空片段；空格拆成 `KEYCODE_SPACE`，任何 `%`、引号、反斜杠、控制字符和 Shell 元字符都拒绝。完整 Unicode、输入法组合文本和剪贴板粘贴后续通过固定版本的 scrcpy control socket 实现 `set clipboard + paste`，或引入用户明确安装和启用的专用输入法；不得静默安装辅助 APK 或切换系统输入法。

### 7.7 Agent 连续操作规则

- 默认一次只规划和执行一个会改变设备状态的动作，然后重新观察。
- 视觉坐标点击、无法重新确认的 node、文本输入和跨 package 动作始终逐次确认，不能进入连续控制。
- 连续控制只对用户显式选择的 package/activity 和本地确定性控件白名单开放；白名单使用稳定 resource id、动作类型和允许的目标状态，不以 Agent 自报意图或视觉文字作为依据。
- 对白名单内无副作用的翻页或导航，可在用户开启“连续控制”后执行有限步数；单批不超过 5 步。
- 任何新弹窗、权限页、账号切换、验证码、支付、删除、发布或提交动作都会中断连续控制。
- 画面没有按预期变化时，不在同一坐标反复点击；重新抓屏并判断按钮是否禁用、被遮挡或页面仍在加载。
- 设备断连、serial 变化、窗口旋转、锁屏或控制授权撤销时，取消队列中的全部后续动作。
- 用户在手机上手动操作导致画面偏离基准时，Agent 放弃旧计划，从新画面重新开始。
- 每次批准绑定 `sessionId + serial + actionId + frameId + 精确参数`；其中任一值变化都必须重新批准。

## 8. Agent 可见性边界

“画面出现在应用里”不等于“Codex 在当前 turn 中自动看见画面”。方案提供两条路径：

- **对话输入路径**：用户把截图作为 `localImage` 随新 turn 或 `turn/steer` 显式提交，适合询问和一次性分析。
- **Agent 工具路径**：运行中的 Codex 调用 `device_observe` 获取最新帧，调用白名单动作操作手机，再使用返回的后置帧验证，适合连续任务。

当前 Codex 命令工具已经能够在独立测试环境和逐次审批下执行 ADB，因此 M0 可以验证底层闭环。该验证不构成产品控制路径。M1 的 Codex 命令沙箱必须失去对 ADB/USB/控制 socket 的直接访问，所有设备动作只能进入 `DeviceAgentToolGateway`。

工具边界要求：

- 应用提供权限受限的本地 Device Broker；只有已签名、已注册的工具传输可以连接。
- 工具优先返回带租约的图像 content、frame id、设备元数据和结构化动作结果，不返回裸临时路径。
- Codex 通过明确的内置技能或插件遵循观察—操作—验证协议。
- 控制工具按动作拆分，继续受 Codex Desk 现有审批策略和设备会话授权约束。
- 端点使用随机会话令牌、Unix domain socket 或仅当前用户可读的权限，应用退出即失效。
- Agent 不能选择未在应用中授权的设备，不能扩大允许的动作集合。
- 用户可以随时撤销控制租约；撤销后正在执行的单个命令允许安全结束，队列中的后续动作全部取消。
- 全局命令自动审批与设备审批相互独立；前者不能创建控制租约、批准敏感动作或改变设备沙箱权限。

具体传输必须在 M0 按 6.6 节选定并冻结。不得通过自动发送 steer、通用命令/CLI、解析 Codex 自然语言输出或模拟点击 scrcpy 窗口来伪造产品 Agent 工具调用。

## 9. 性能与资源预算

第一阶段建议验收目标：

- USB 已连接且设备就绪时，点击到预览出现的 P95 小于 1.5 秒。
- 截图完成到进入 Composer 的 P95 小于 300 毫秒。
- 基础 ADB 动作提交到命令完成的 P95 小于 500 毫秒。
- 单步“操作完成 → 新帧稳定”的 P95 小于 2 秒；页面自身网络加载时间单独展示。
- Agent 每步必须重新观察，正常导航闭环目标为每步 1～3 秒，不以牺牲验证换取连点速度。
- 单帧最长边默认限制在 1440 像素；保留原始帧仅在用户明确选择时开放。
- 自动预览默认 2 FPS，上限 4 FPS，抓帧不得并发。
- 面板关闭后 2 秒内停止调度，不保留活动 Timer。
- 设备切换后旧帧不得出现在新设备会话中。
- 未被 Composer 或时间线引用的临时帧最多保留 3 张。

模型提交不按固定 FPS 触发。若后续提供变化检测，只有感知哈希超过阈值且用户开启相应模式时才生成候选关键帧。

## 10. 安全与隐私

### 10.1 屏幕数据边界

设备帧分为两类，状态和 UI 必须明确区分：

- **本地预览帧**：仅供应用或 scrcpy 显示，永不进入 Codex turn、工具结果或模型 Provider。
- **模型分析帧**：通过 `localImage` 或 `device_observe` 提交给当前 Codex 配置实际使用的模型 Provider；可能离开本机，并受该 Provider 的数据处理和保留策略约束。

首次使用模型分析前必须显示当前 Provider 名称、将发送的数据种类（截图，以及用户可选的已脱敏 UI 文字）和本地保留策略，并取得绑定 `device serial + Provider id + account/config identity` 的会话授权。Provider、账号或有效配置变化时授权立即失效；本地预览不会自动获得模型分析授权。

`device_observe` 只有在模型分析授权有效时才能返回图像 content。默认不共享 UI 节点原始文本；密码节点始终脱敏。用户可以维护禁止模型观察的 package 列表，进入锁屏、系统凭据、支付或禁止 package 时 Gateway 停止返回帧并要求用户手动继续。界面和 README 必须说明：即使图片不写入日志，提交给模型仍属于向当前 Provider 发送数据。

### 10.2 动作授权

动作风险分级：

| 等级 | 示例 | 策略 |
| --- | --- | --- |
| 只读 | 抓屏、读取 UI 层级、查询尺寸 | 设备会话授权后直接执行 |
| 普通导航 | 点击普通导航、滑动、返回、Home | 默认逐次批准；只有确定性 package/node 白名单可在有限步内连续执行 |
| 敏感确认 | 权限授予、删除、发布、提交表单、切换账号、安装/卸载 | 无论当前模式都暂停并逐次确认 |
| 禁止自动执行 | 输入密码/验证码/助记词/私钥、支付确认、恢复出厂设置、修改 USB 调试信任 | Agent 不执行，交给用户在手机上手动完成 |

- 首次开启设备能力时说明屏幕可能包含通知、聊天、验证码、账号和支付信息。
- 默认只读；控制权限必须由用户在每次设备会话中主动开启，应用重启后恢复为关闭。
- 控制权限绑定 serial 和随机 session id，设备切换、断连或应用休眠后自动撤销。
- 支持“仅观察”“每步确认”“连续控制”三级模式；默认“仅观察”，“连续控制”必须显示常驻状态和停止入口。
- 动作批准绑定当前帧和精确参数；Agent 提供的意图说明、按钮文字或风险声明不产生授权效力。
- 不把截图写入项目目录、Git 工作树、普通运行日志或诊断信息。
- 历史时间线引用的截图属于对话数据，应沿用现有本地历史与清理策略，并在文档中明确其保留边界。
- 日志记录命令类型、耗时、退出码和脱敏后的错误，不记录输入文本、完整通知内容或图片二进制。
- 所有外部进程使用解析后的绝对路径、参数数组和 `runInShell: false`。
- 对 serial、文件路径和文本输入执行独立校验，不拼接 shell 字符串。
- 只终止本应用启动并持有句柄的进程；不执行全局 `killall`，不主动执行 `adb kill-server`。
- 任何自动控制涉及付款、删除、权限授予、隐私授权或凭据提交时，必须停下并按风险策略确认或拒绝。
- 验证码、助记词、私钥、密码和支付信息不能写入动作日志，也不能通过自动文本输入提交。

### 10.3 Codex 命令隔离

- Device Broker 独占 ADB 和 USB 调试权限，Codex 命令沙箱只允许访问已注册工具传输所需的最小 IPC。
- 普通命令、全局自动审批、技能和项目指令都不能扩展 Device Broker 权限。
- M1 必须包含绕过测试：直接/复制/重命名 adb、连接 ADB Server、调用 scrcpy 控制、访问原始 Broker socket 和通过其他解释器发起等价连接都应失败。
- 如果某个平台无法建立并验证该隔离，禁用 Agent 连续控制；只保留应用 UI 发起、用户逐次确认的动作。

## 11. 错误模型与恢复

对用户暴露稳定、可行动的错误类别：

| 类别 | 识别条件 | 用户动作 |
| --- | --- | --- |
| ADB 未找到 | 探测不到可执行文件 | 安装 Android Platform Tools 或手动选择路径 |
| 未连接设备 | 列表中没有目标 | 检查 USB、数据线和 USB 调试 |
| 未授权 | 状态为 `unauthorized` | 在手机上确认 RSA 提示后刷新 |
| 设备离线 | 状态为 `offline` | 重新连接设备；不自动重启全局 ADB |
| 抓帧超时 | 5 秒内未完成 | 取消当前命令，允许手动重试 |
| 返回帧无效 | 非 PNG、空数据或尺寸异常 | 丢弃临时数据并显示错误 |
| 设备已切换 | epoch/token 不匹配 | 静默丢弃迟到结果 |
| 控制未授权 | 会话无控制租约或租约已撤销 | 用户明确开启本次会话控制 |
| 模型观察未授权 | 当前 device/Provider 无有效数据授权 | 展示 Provider 和数据范围后由用户授权 |
| Provider 已变化 | Provider、账号或有效配置与授权不匹配 | 撤销观察与控制，重新取得授权 |
| 坐标已过期 | 帧尺寸、旋转或基准帧不匹配 | 重新观察后定位 |
| 帧租约已失效 | 工具引用的 frame id 已释放或过期 | 重新观察，不复用旧路径 |
| 操作无变化 | 命令成功但后置帧未变化 | 重新分析，不自动重复点击 |
| 高风险动作 | 命中确认或禁止规则 | 请求用户确认或拒绝执行 |
| App Server 发送失败 | `turn/start` / `turn/steer` 失败 | 保留截图附件，允许再次发送 |

自动重试只用于短暂抓帧失败，采用有上限的退避；`unauthorized` 和“ADB 未找到”不做无意义重试。

## 12. 测试策略

### 12.1 单元测试

- 解析单设备、多设备、无设备、`unauthorized`、`offline` 和异常 ADB 输出。
- 二进制 PNG 签名、空输出、超大输出和 stderr 处理。
- 命令超时与进程回收。
- Frame Store 原子写入、引用保留、环形清理和路径边界。
- preview/composer/timeline/toolCall/actionVerification 租约的取得、转移、释放和异常过期回收。
- 工具结果消费前帧不会被环形清理，turn 结束后无泄漏。
- 感知哈希去重。
- session epoch 防止旧设备结果覆盖新设备。
- 连续失败后暂停低频预览。
- 动作白名单、参数边界、过期坐标和错误 serial 拒绝。
- 同一设备动作串行化、授权撤销后取消排队动作。
- 后置帧稳定判断、无变化结果和最多一次自动修正。
- 风险分类：只读、普通导航、逐次确认和禁止动作。
- Agent 自报低风险不会降低本地策略等级；视觉坐标和非白名单节点始终逐次确认。
- 文本输入严格字符白名单、空格 keyevent 拆分，以及所有 Shell 元字符拒绝。
- Provider/账号/配置变化会撤销模型观察授权，禁止 package 和 password 节点不泄漏内容。
- 全局自动审批不能授予设备租约或放宽 Device Broker 沙箱。

测试不得依赖真实 ADB 或真实手机，通过可注入的 Process Runner 和临时目录完成。

### 12.2 Widget 测试

- 所有设备状态的面板空态和操作可用性。
- 多设备选择、刷新、附加与发送 loading 状态。
- “仅观察”“每步确认”“连续控制”的状态切换和常驻停止入口。
- Agent 操作进行中、已完成、等待确认和验证失败的反馈。
- 图片加入 Composer 后可预览、移除，发送失败后仍保留。
- 运行中任务使用待发送方向栏，而不是直接自动 steer。
- 切换项目或任务不会错误带入另一设备会话的截图。
- 窄窗口、面板边界、悬停延迟、窗口关闭和异步回调后的生命周期。

### 12.3 集成与人工验证

- 至少覆盖一个 Android 13～15 真机；有条件时增加不同厂商设备。
- USB 断开、重新插入、屏幕旋转、锁屏和解锁。
- 同时连接两个设备并切换。
- 运行 30 分钟低频预览，检查 CPU、内存、临时文件和僵尸进程。
- 从抓屏到 `localImage` 提交，再确认模型能识别页面文字和控件。
- 完成“观察 → 用户批准点击 → 后置截图 → Codex 验证”的端到端闭环。
- 使用视觉坐标和 UI 节点各完成一组导航，并验证旋转后旧坐标被拒绝。
- 操作过程中由用户手动改变页面，确认 Agent 能放弃旧计划并重新观察。
- 在全局“帮我批准”开启时运行直接 adb、复制/改名 adb、ADB Server 连接、scrcpy 控制和 Broker socket 绕过测试，全部失败。
- 切换模型 Provider 后，旧观察授权失效；本地预览继续工作但模型无法取得新帧。
- 连续执行超过 10 个动作，确认 Agent 前后帧在消费前可读、turn 结束后得到释放。

按仓库约定，实施提交前运行：

```bash
dart format .
flutter analyze
flutter test
```

涉及面板布局、悬停和异步更新时，必须补充窗口边界、生命周期与迟到结果测试。

## 13. 分阶段交付

### M0：真实设备闭环验证

- 验证 ADB 路径发现和多设备解析。
- 在 Dart 中抓取二进制 PNG，测量 30 次 USB 抓帧延迟。
- 验证图片通过现有 `localImage` 在新 turn 和 steer 中可识别。
- 在用户逐步确认下，通过现有 Codex 命令工具完成一次无风险的点击或返回操作。
- 操作后自动重新抓屏，验证 Codex 能判断页面是否按预期变化。
- 在真实 App Server turn 中验证本地工具扩展能力；若不可用，验证签名 MCP 伴随进程方案。
- 按 6.6 节选定并记录唯一产品传输，包括工具发现、IPC、图像 content、审批、重启和打包方式。
- 验证 Codex 命令沙箱可以阻止绕过 Device Broker；若无法阻止，停止 M1 Agent 连续控制设计并降级为 UI 逐次操作。
- 输出实测数据，不做正式 UI。

退出条件：连续 30 次抓帧无损坏；设备切换和超时可正确回收；模型可读取截图；至少一条“观察 → 操作 → 再观察 → 验证”链路成功；产品工具传输已冻结；绕过测试证明通用命令无法直接获得设备权限。

### M1：受控识别与基础操作

- 新增 Bridge、Frame Store 和 Riverpod Controller。
- 新增 Device Agent Tool Gateway 与操作白名单。
- 按 M0 冻结的 DeviceToolTransport 接入真实 App Server，不保留运行期传输二选一。
- 新增设备面板、设备选择、当前帧和错误空态。
- 支持附加当前屏幕、截屏并询问、运行中调整方向。
- 支持点击、滑动、长按、返回、Home 和应用切换；默认仅观察，控制权限按设备会话开启。
- 每次动作后自动等待画面稳定、返回后置帧并由 Codex 验证。
- 提供“每步确认”和明确的停止控制入口；不开放任意 `adb shell`。
- 独立处理设备审批；全局“帮我批准”不能代替设备确认。
- 增加 Provider 数据授权、禁止观察 package 和 UI 文字脱敏。
- 完成临时文件生命周期与全套测试。
- 同步更新 `README.md`、`ROADMAP.md` 和未发布 `RELEASE_NOTES.md`。

退出条件：达到第 9 节性能目标；所有错误状态可恢复；错误坐标和未授权动作不会发送；单设备可稳定完成至少 10 步观察—操作循环；Provider 切换会撤销观察授权；通用命令绕过设备策略的测试持续通过。

### M2：Agent 连续控制与 UI 辅助定位

- 接入 UI 层级读取，在可用时优先按节点操作。
- 增加有限步数的“连续控制”，每个动作仍强制后置观察。
- 增加画面变化等待、页面偏离检测和最多一次自动修正。
- 增加受限 ASCII 文本输入；敏感字段和高风险动作必须中断。
- 沿用 M0 已冻结的工具传输，不在该阶段切换协议。

退出条件：用户手动干预、旋转或弹出意外对话框时能停止旧计划；连续控制可随时撤销且无迟到动作。

### M3：低频应用内预览与 scrcpy 监督

- 增加 1～4 FPS 预览、去重、后台暂停与故障熔断。
- 支持在独立 scrcpy 窗口中监督 Agent 操作，并只管理应用自身启动的进程。
- 完成 30 分钟资源与生命周期测试。
- 保持预览刷新与模型提交完全解耦。

退出条件：无并发抓帧堆积、无临时文件增长、面板关闭后无活动调度。

### M4：流畅内嵌预览与增强控制

- 对原生 H.264 插件和固定版本 scrcpy protocol 完成技术选型。
- 实现 Flutter Texture/Platform View 的低延迟预览。
- 需要时用固定版本 scrcpy control socket 改善 Unicode、剪贴板和输入延迟。

退出条件：连续运行、旋转、断连、休眠恢复和应用退出都能正确回收资源；增强控制继续遵守相同审批与隐私边界。

## 14. 验收场景

M1 完成时，下列场景必须成立：

1. 用户连接一台已授权 Android 手机，打开设备面板后能看到设备名称和当前屏幕。
2. 点击“附加当前屏幕”后，Composer 出现可预览、可删除的图片附件。
3. 点击“截屏并询问 Codex”后，时间线显示该截图，Codex 能说明当前页面及可选操作。
4. Codex 正在运行时抓屏不会自动干扰任务；截图进入待发送方向，用户确认后才 steer。
5. 手机断开后，面板停止抓帧并显示可恢复提示；迟到帧不会覆盖断连状态。
6. 同时连接两台设备时，所有命令都携带所选 serial，不会操作另一台设备。
7. 退出应用后，本应用创建的临时帧和子进程得到回收；对话仍引用的图片按现有历史策略处理。
8. 用户开启“每步确认”后，Codex 能从当前帧定位普通按钮，待用户批准后点击，并用后置帧确认页面变化。
9. 截图尺寸或方向变化后，基于旧帧产生的坐标操作会被拒绝，Codex 必须重新观察。
10. ADB 返回成功但画面未变化时，动作结果明确标记 `screenChanged: false`，不会自动重复点击。
11. 用户撤销控制、切换设备或断开 USB 后，排队动作立即取消，迟到结果不更新当前会话。
12. 密码、验证码、支付确认和恢复出厂设置等禁止动作不会由 Agent 执行；删除和系统权限确认等敏感动作必须逐次确认。
13. 本地预览不会自动把画面提交给模型；首次模型观察会显示当前 Provider 和数据范围，Provider 变化后必须重新授权。
14. 视觉坐标、非白名单节点和跨 package 操作即使在“连续控制”中也会暂停并逐次确认。
15. 全局“帮我批准”开启时，Codex 仍不能通过通用命令、ADB Server 或 scrcpy 绕过 Device Broker。
16. 包含 Shell 元字符、任意 Unicode 或未支持字符的文本输入会被 Gateway 拒绝，不会到达 Android 远端 Shell。
17. 工具返回的前后帧在 App Server 消费前不会被清理，turn 结束或明确释放后能够回收。

## 15. 风险与待验证事项

- `screencap` 在部分厂商设备或高分辨率设备上可能超过目标延迟，需要用实测决定是否默认缩放。
- Android 安全页面、DRM 内容或企业策略可能返回黑屏，这是平台限制，界面必须如实提示。
- 文本输入的 Unicode、输入法和 shell 转义跨设备差异较大，应晚于只读与点击能力交付。
- `uiautomator` 层级可能过时、缺失或不包含自绘内容，不能把节点存在视为操作成功证明。
- ADB 输入命令的退出码不能证明目标控件收到事件，必须依赖后置画面验证。
- 同一 macOS 用户下隔离 ADB Server、USB 与工具 IPC 需要真实沙箱验证；静态命令字符串拦截不能视为安全边界。
- 视觉或 UI 节点无法可靠判断动作业务风险，因此连续控制只适用于确定性本地白名单，其他动作保持逐次确认。
- 模型分析帧和可选 UI 文字会发送给当前 Provider；Provider 的实际数据处理和保留策略必须在授权界面如实展示或链接说明。
- `screenrecord` 原始流可能存在时长限制、旋转重启和首帧延迟；M4 之前必须验证，不能把它视为已确定方案。
- scrcpy server protocol 不是 Codex Desk 的稳定公共依赖；若选择该方向必须固定版本并建立兼容测试。
- App Server 本地工具扩展或 MCP 伴随进程必须在 M0 完成验证和冻结；验证失败会阻塞 M1 Agent 控制能力。

## 16. 最终建议

先交付 M0 的两项硬门槛：冻结真实 App Server 工具传输，并证明 Codex 通用命令无法绕过 Device Broker。通过后再进入 M1，用 ADB 打通“观察当前帧 → Codex 判断 → 用户授权操作 → 后置截图验证”的最短可靠路径。任何一项隔离验证失败，都只交付本地预览和 UI 逐次操作，不开放 Agent 连续控制。

随后增加 UI 层级辅助、有限步连续控制和低频监督预览。只有在真实使用证明需要更高帧率、Unicode 或更低输入延迟时，再投入原生视频解码与固定版本 scrcpy 控制协议。该顺序优先交付 Agent 真正可用的手机操作闭环，同时保留升级为完整设备工作台的架构空间。
