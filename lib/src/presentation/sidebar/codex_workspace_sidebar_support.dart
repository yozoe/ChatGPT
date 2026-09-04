// Shared declarations extracted from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
// ignore_for_file: use_key_in_widget_constructors

import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';

/// 右侧主区域当前显示的工作台目的地。
/// Destination currently shown in the right-side workbench area.
enum WorkspaceDestination {
  conversation,
  pullRequests,
  scheduledTasks,
  plugins,
  agents,
  settings,
}

enum SidebarHelpAction { chromeExtension, keyboardShortcuts, help }

/// 插件工作区内两个互斥的数据来源视图。
/// Mutually exclusive data-source views within the plugin workspace.
enum PluginLibraryTab { plugins, skills }

@immutable
/// Identifies a retained timeline viewport within its owning workspace.
/// 在所属项目范围内标识保留的时间线视口。
String workspaceDirectoryName(String path) {
  if (WorkspaceConfiguration.isUnrootedPath(path)) return '未命名项目';
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  final separator = normalized.lastIndexOf(Platform.pathSeparator);
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

/// 展示一个主目录或附加目录，并在窄窗口中安全截断路径。
/// Displays a primary or additional directory while safely truncating its path in narrow windows.

CodexThread? activeThreadFor(CodexController controller) {
  final activeThreadId = controller.activeThreadId;
  if (activeThreadId == null) return null;
  for (final thread in [...controller.threads, ...controller.archivedThreads]) {
    if (thread.id == activeThreadId) return thread;
  }
  return null;
}

/// Displays the active task name in the workbench header and turns it into an
/// inline editor on demand.
/// 在工作台顶部显示当前任务名称，并按需切换为行内编辑器。

/// 展示一个插件的来源、安装状态和可用操作。
/// Displays one plugin's source, install state, and available actions.
/// 展示 marketplace 来源、类型以及其允许的维护操作。
/// Displays a marketplace source, type, and available maintenance actions.

/// 在侧栏中以 Codex 风格的项目节点展示一个可切换工作区。
/// Displays one switchable workspace as a compact Codex-style project node.

/// 侧栏的低对比度分组标题，保留 Codex 的信息层级而不制造额外卡片。
/// A low-contrast sidebar section label that keeps Codex's hierarchy without extra cards.

enum WorkspaceAction { pin, edit, worktree, archive, remove }

/// Codex-style command surface for finding a task without permanently taking
/// space from the project tree.

/// A compact, text-first project-menu row matching the Codex desktop rhythm.

/// A lazily built sidebar row with a stable scroll extent. The task tree uses
/// a small set of fixed-height row types; keeping their extents explicit stops
/// a long list from revising its scroll geometry as more rows are built.

/// 连接时间线、审批、计划浮层和 Composer 的当前任务阅读/输入区域。
/// Focused-task reading and input area joining timeline, approvals, plan overlay, and composer.
