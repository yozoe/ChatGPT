// Codex Desk 的主要工作台：组合项目导航、可保活任务时间线、输入区和检查器。
// Main Codex Desk workbench composing project navigation, retained timelines, composer, and inspector.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_state.dart';

/// 仅根据常见扩展名决定附件是否应按图片预览；不读取文件内容。
/// Determines whether an attachment should use image preview from its extension without reading file contents.
bool isImagePath(String path) {
  final lower = path.toLowerCase();
  return const [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  ].any(lower.endsWith);
}

/// 按项目读取悬停卡片所需的异步任务数量，并随卡片作用域自动释放。
/// Reads the async task count for a project hover card and disposes it with that card's scope.
final workspaceTaskCountProvider = FutureProvider.autoDispose
    .family<int, WorkspaceTaskCountRequest>(
      (ref, request) => request.controller.readWorkspaceTaskCount(request.path),
    );

/// 应用主工作台；显式注入控制器仅用于嵌入式调用和 Widget 测试。
/// Main application workbench; explicit controller injection is only for embedding and widget tests.
class CodexWorkspace extends ConsumerStatefulWidget {
  const CodexWorkspace({
    this.controller,
    this.themeMode = ThemeMode.dark,
    this.themePreset = YeknomColorPreset.midnight,
    this.onThemeModeChanged,
    this.onThemePresetChanged,
    super.key,
  });

  /// 测试或嵌入式场景可显式注入控制器；正常运行时从 Riverpod 读取共享实例。
  /// Tests and embedded callers may inject a controller; normal execution reads the shared Riverpod instance.
  final CodexController? controller;
  final ThemeMode themeMode;
  final YeknomColorPreset themePreset;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<YeknomColorPreset>? onThemePresetChanged;

  /// 创建承载工作区页面状态的 State 对象。
  /// Creates the State object that owns workspace-page state.
  @override
  ConsumerState<CodexWorkspace> createState() => CodexWorkspaceState();
}
