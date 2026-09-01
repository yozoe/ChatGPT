// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_subagent_avatar.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_subagent_thread_error.dart';

class SubagentThreadPanel extends StatelessWidget {
  const SubagentThreadPanel({
    required this.controller,
    required this.threadId,
    required this.fallbackTitle,
    required this.onOpenSubagent,
    required this.onClose,
  });

  final CodexController controller;
  final String threadId;
  final String fallbackTitle;
  final ValueChanged<TimelineEntry> onOpenSubagent;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final view = controller.subagentThreadView(threadId);
    final title = view?.title.isNotEmpty == true ? view!.title : fallbackTitle;
    final entries = view?.entries ?? const <TimelineEntry>[];
    final elapsed = entries.where(
      (entry) => entry.kind == TimelineKind.elapsed,
    );
    final status = subagentStatusLabel(view?.status ?? 'working');
    return ColoredBox(
      key: const Key('subagent-thread-panel'),
      color: palette.module,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 47,
            child: Row(
              children: [
                IconButton(
                  key: const Key('subagent-thread-close'),
                  tooltip: '返回主任务',
                  onPressed: onClose,
                  icon: const Icon(Icons.arrow_back, size: 18),
                ),
                SubagentAvatar(agentId: threadId, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: palette.trace,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭子智能体',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 17),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (view?.status == 'working') ...[
                      SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: palette.muted,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      elapsed.isEmpty ? status : elapsed.last.title,
                      key: const Key('subagent-thread-status'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right, size: 14, color: palette.muted),
                  ],
                ),
                if (view?.prompt.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  Text(
                    view!.prompt,
                    key: const Key('subagent-thread-prompt'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.trace,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, indent: 24, endIndent: 24, color: palette.border),
          Expanded(
            child: view?.error != null
                ? SubagentThreadError(
                    message: view!.error!,
                    onRetry: () => unawaited(
                      controller.loadSubagentThread(
                        threadId: threadId,
                        title: title,
                        prompt: view.prompt,
                        status: view.status,
                        force: true,
                      ),
                    ),
                  )
                : entries
                      .where((entry) => entry.kind != TimelineKind.elapsed)
                      .isEmpty
                ? Center(
                    child: Text(
                      view?.loading == true ? '正在读取子线程…' : '子智能体尚未产生可显示内容',
                      style: TextStyle(color: palette.muted),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.separated(
                        key: const Key('subagent-thread-timeline'),
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                        itemCount: entries
                            .where(
                              (entry) => entry.kind != TimelineKind.elapsed,
                            )
                            .length,
                        separatorBuilder: (_, _) => const SizedBox(height: 18),
                        itemBuilder: (context, index) {
                          final visibleEntries = entries
                              .where(
                                (entry) => entry.kind != TimelineKind.elapsed,
                              )
                              .toList(growable: false);
                          return CodexTimelineEntry(
                            visibleEntries[index],
                            workspacePath: controller.workspacePath,
                            onOpenSubagent: onOpenSubagent,
                          );
                        },
                      ),
                      if (view?.loading == true)
                        const Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: LinearProgressIndicator(minHeight: 1),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
