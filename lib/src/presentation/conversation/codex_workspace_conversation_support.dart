// Shared declarations extracted from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_diff_stats.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_diff_preview_line.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_local_image_preview.dart';

/// Keeps the scrolling transcript and floating Composer on one centered rail.
const double conversationContentHorizontalInset = 24;

/// Lets the timeline occupy the full conversation viewport while the composer
/// floats above it. The measured bottom inset keeps the final message fully
/// reachable even though intermediate content can pass behind the composer.
/// 让时间线铺满会话视口并把输入区悬浮在其上；动态测量的底部留白保证最后一条
/// 消息仍可完整滚出输入区，同时中间内容可以从输入区后方经过。

/// Keeps a concurrent-writer conflict non-blocking so the user can close the
/// other session and retry without dismissing a dialog.

/// Codex-style inline recovery surface kept next to the composer so a failed
/// turn remains actionable without interrupting the conversation with a modal.
/// Codex 风格的行内恢复提示：紧邻输入框，不用弹窗打断当前会话。

/// Read-only Codex-style inspector for one App Server child thread.
/// App Server 子线程的只读 Codex 风格检查器。

String subagentStatusLabel(String status) => switch (status) {
  'completed' => '已完成',
  'failed' => '失败',
  'stopped' => '已停止',
  _ => '正在处理',
};

/// A locally queued direction renders as a composer header rather than a
/// conversation bubble. Its action intentionally sends directly.
/// 本地暂存的方向显示为 Composer 顶部栏而非会话气泡；点击操作会直接发送。

/// Immutable rendering inputs for one retained task timeline.
/// 单个保活任务时间线的不可变渲染输入。

/// A task timeline that remains mounted inside the page cache.
/// 在页面缓存中持续挂载的任务时间线。

/// Codex-style quiet loading surface: a centered, monochrome knot with no
/// text or animated layout movement while a task history is being restored.
/// Codex 风格的安静加载画面：居中的单色结标志，不引入文字或布局动画。

DiffStats diffStats(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+++') || line.startsWith('---')) continue;
    if (line.startsWith('+')) additions++;
    if (line.startsWith('-')) deletions++;
  }
  return DiffStats(additions, deletions);
}

String diffCountLabel(String prefix, int count, {required bool unknown}) =>
    unknown ? '$prefix?' : '$prefix$count';

/// Reports whether the available Diff can support an honest line-count total.
/// A header-only, binary, or metadata-only Diff describes a file change but
/// does not provide countable added or deleted lines.
bool fileChangeStatsUnknown(List<CodexFileChange> changes, String? turnDiff) {
  final hasMissingDiff = changes.any((change) => change.diff.trim().isEmpty);
  final fallback = turnDiff?.trim();
  if (hasMissingDiff && (fallback == null || fallback.isEmpty)) return true;
  final source = hasMissingDiff
      ? fallback!
      : changes.map((change) => change.diff).join('\n');
  final stats = diffStats(source);
  return stats.additions == 0 && stats.deletions == 0;
}

List<DiffPreviewLine> previewLines(String diff) {
  final hunkPattern = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
  var inHunk = false;
  var oldLine = 0;
  var newLine = 0;
  return diff
      .split('\n')
      .map((line) {
        final hunk = hunkPattern.firstMatch(line);
        if (hunk != null) {
          inHunk = true;
          oldLine = int.parse(hunk.group(1)!);
          newLine = int.parse(hunk.group(2)!);
          return DiffPreviewLine(line, null);
        }
        if (!inHunk) return DiffPreviewLine(line, null);

        if (line.startsWith('+') && !line.startsWith('+++')) {
          return DiffPreviewLine(line, newLine++);
        }
        if (line.startsWith('-') && !line.startsWith('---')) {
          return DiffPreviewLine(line, oldLine++);
        }
        if (line.startsWith(' ')) {
          final number = newLine++;
          oldLine++;
          return DiffPreviewLine(line, number);
        }
        return DiffPreviewLine(line, null);
      })
      .toList(growable: false);
}

/// 输入框右下角的新任务模型与推理强度双拨盘。
/// A paired new-task model and reasoning-effort control in the composer's lower-right corner.

/// 管理未发送文本、附件与临时上下文的 Composer 外壳。
/// Composer shell managing unsent text, attachments, and transient context.

/// 仅保存单个输入区的交互状态；提交后的共享状态由控制器接管。
/// Holds only one composer's interaction state; shared state moves to the controller after submission.

/// 原生附件选择器的目标类型，决定允许的系统选择能力。
/// Native attachment-picker target, which determines permitted system selection capability.
enum AttachmentPickerKind { files, folder }

/// Composer “添加”菜单产生的结构化上下文类型。
/// Structured context types emitted by the composer add menu.
enum AddMenuActionKind { files, workspace, goal, plan, recordSkill, skill }

/// 将菜单项类型与可选负载组合，避免菜单直接依赖 Composer 私有状态。
/// Couples a menu action kind with optional payload without exposing Composer private state.

/// 单个待发送附件；临时图片会在不再被时间线引用后由原生侧回收。
/// One pending attachment; native temporary images are reclaimed after no timeline references remain.

/// 一次 Composer 提交的不可变快照，供新 turn 与 turn/steer 共用。
/// Immutable Composer submission snapshot shared by new turns and turn/steer.

/// 为 Composer 附件和会话图片打开同一套沉浸式本地图片预览。
/// Opens the same immersive local-image preview for Composer and timeline images.
Future<void> showLocalImagePreview(BuildContext context, String path) async {
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭图片预览',
    barrierColor: Colors.black.withValues(alpha: 0.88),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        LocalImagePreview(
          key: const Key('composer-image-preview-dialog'),
          path: path,
          onOpenExternally: () => openLocalImageExternally(context, path),
          onSaveCopy: () => saveLocalImageCopy(context, path),
        ),
  );
}

Future<void> openLocalImageExternally(BuildContext context, String path) async {
  try {
    final opened = await launchUrl(
      Uri.file(path),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法在默认应用中打开图片。')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法在默认应用中打开图片。')));
    }
  }
}

Future<void> saveLocalImageCopy(BuildContext context, String path) async {
  try {
    final extension = path.split('.').last.toLowerCase();
    final segments = path
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final location = await getSaveLocation(
      suggestedName: segments.isEmpty ? path : segments.last,
      acceptedTypeGroups: [
        XTypeGroup(
          label: '图片',
          extensions: isImagePath(path) ? [extension] : const [],
        ),
      ],
      confirmButtonText: '保存图片',
    );
    if (location == null) return;
    await XFile(path).saveTo(location.path);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片已保存。')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法保存图片。')));
    }
  }
}

/// Codex 风格的沉浸式本地图片预览，缩放状态只属于当前预览生命周期。
/// Codex-style immersive local-image preview whose zoom state is local to this route.

/// An explicit, host-rendered response to a server-initiated MCP elicitation.
/// URLs are shown for review only: this panel never opens them automatically.

String fileChangeCountLabel(int count) => count == 0 ? '暂无' : '$count 个';

/// Full-screen scheduled-task hub modeled after the Codex desktop library.
