# Profile 性能基准

该基准用于比较状态边界和 Widget 重建范围的变化，不把一次本地运行结果直接当成优化结论。

## 运行方式

在 macOS Profile 模式运行：

```bash
flutter drive \
  --profile \
  -d macos \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/profile_performance_benchmark_test.dart
```

通过 integration test driver 收集 `reportData` 中的 `performance` 和各场景 timeline。运行前关闭其他高负载应用，并记录 Flutter、macOS、机器型号、显示刷新率和窗口尺寸。相同环境至少运行三次，使用中位数比较。

macOS CI 会运行 `flutter test integration_test/profile_performance_benchmark_test.dart -d macos` 作为夹具烟测；该步骤只验证场景和宿主生命周期，不生成 Profile 优化结论。

## 当前可执行场景

- `sidebar_1000_threads`：1,000 条任务的侧栏在连续控制器通知下的帧时间。
- `streaming_deltas`：240 次 Agent 文本增量及 Composer/时间线更新。
- `background_completion_notifications`：63 个后台任务完成通知的时间线与侧栏更新。
- `rapid_task_switching`：两个 250 条任务的工作区之间快速切换。
- `large_diff_parsing`：500 个文件、每个 24 行的 unified Diff，重复解析 8 次并记录输入字节数与 Dart 解析耗时。
- `large_git_review_canvas`：使用 500 个 Git 工作区变更实际渲染 `CodeReviewPanel`，往返滚动 Diff 画布并开合文件导航，覆盖画布布局、粘性文件标题和导航树的组合帧时间。
- `native_webview_workspace_expand_return`：使用 loopback 固定 HTML 真实挂载 macOS WebKit，在 360px 与 900px 工作区宽度之间往返，覆盖原生 WebView 重排和工作区展开/返回。

基准只记录测量数据，不修改业务状态契约，也不要求 App Server 真实联网。

当前环境验证：`flutter test integration_test/profile_performance_benchmark_test.dart -d macos` 已通过 7/7 场景，证明夹具、真实审查画布、真实 macOS WebKit 和生命周期可执行。`flutter drive --profile` 已成功构建 Profile 应用，但 Flutter 3.47.1 的本地 driver 随后报告 `HttpException: Connection closed before full header`；该问题发生在 driver 连接层，尚未取得可用于比较的 Profile 帧数据，因此不能把这次构建视为性能结果。

## 尚未自动化的宿主场景

完整 Git 审查工作区的原生宿主联动仍需要 macOS 原生宿主夹具；当前已把 Flutter `CodeReviewPanel` 画布、文件导航、真实 unified Diff 解析以及 loopback 页面上的真实 WebView 展开/返回纳入报告，但不把 RSS 峰值模拟成已完成。

## 结果记录

每次结果至少记录：Profile 构建版本、提交、窗口尺寸、刷新率、平均/95 分位/最差帧时间、掉帧数量、场景耗时和常驻内存。夹具会在 `reportData` 中额外记录任务切换、Git 画布和 WebView 展开/返回的 `elapsedMicros`，以及文件/行数或宽度等输入规模。只有同一环境下重复观察到的回归才进入后续优化任务。
