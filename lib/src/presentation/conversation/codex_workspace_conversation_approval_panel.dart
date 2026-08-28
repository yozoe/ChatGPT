// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:async';
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class ApprovalPanel extends StatelessWidget {
  const ApprovalPanel({
    required this.approval,
    required this.taskLabel,
    required this.enabled,
    required this.onAccept,
    required this.onAllowSimilar,
    required this.onDecline,
  });

  final PendingApproval approval;
  final String? taskLabel;
  final bool enabled;
  final Future<void> Function() onAccept;
  final Future<void> Function() onAllowSimilar;
  final Future<void> Function() onDecline;

  /// 构建当前服务器审批请求及其允许、拒绝操作。
  /// Builds the current server approval request with allow and decline actions.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (enabled) unawaited(onDecline());
        },
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: const Key('approval-panel'),
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 720),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.controlBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal, size: 15, color: palette.muted),
                    const SizedBox(width: 7),
                    Text(
                      approval.kind == ApprovalKind.permissions
                          ? '权限请求'
                          : approval.title,
                      style: TextStyle(
                        color: palette.trace,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (taskLabel case final label?) ...[
                          const SizedBox(height: 4),
                          Text(
                            '来自后台任务：$label',
                            style: TextStyle(color: palette.signal),
                          ),
                        ],
                        if (approval.reason case final reason?) ...[
                          const SizedBox(height: 9),
                          SelectableText(reason),
                        ],
                        if (approval.command case final command?) ...[
                          const SizedBox(height: 9),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: palette.module,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              command,
                              style: TextStyle(
                                color: palette.trace,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        if (approval.params['grantRoot'] case final root?) ...[
                          const SizedBox(height: 7),
                          Text(
                            '授权目录：$root',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (approval.params['networkApprovalContext']
                            case final network?) ...[
                          const SizedBox(height: 7),
                          Text(
                            '网络访问：$network',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (approval.reason == null &&
                            approval.command == null &&
                            approval.params['grantRoot'] == null &&
                            approval.params['networkApprovalContext'] == null &&
                            approval.detail.isNotEmpty) ...[
                          const SizedBox(height: 9),
                          SelectableText(approval.detail),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      key: const Key('approval-decline'),
                      onPressed: enabled ? onDecline : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.muted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('拒绝  Esc'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      key: const Key('approval-allow-once'),
                      onPressed: enabled ? onAccept : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.field,
                        foregroundColor: palette.trace,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('允许一次'),
                    ),
                    if (approval.kind != ApprovalKind.fileChange)
                      PopupMenuButton<String>(
                        key: const Key('approval-more-options'),
                        tooltip: '更多允许选项',
                        enabled: enabled,
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 17),
                        onSelected: (_) => onAllowSimilar(),
                        itemBuilder: (context) => const [
                          PopupMenuItem<String>(
                            value: 'similar',
                            child: Text('允许类似操作'),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
