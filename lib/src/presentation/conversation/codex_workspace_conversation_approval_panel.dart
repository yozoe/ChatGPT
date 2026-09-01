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

/// 展示 App Server 的待审批请求，并提供一次性或持久化的允许/拒绝操作。
/// Presents an App Server approval request with allow-once, allow-similar, and decline actions.
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
    final isBrowser = approval.kind == ApprovalKind.browser;
    final icon = switch (approval.kind) {
      ApprovalKind.browser => Icons.language,
      ApprovalKind.command => Icons.terminal,
      ApprovalKind.fileChange => Icons.edit_note,
      ApprovalKind.permissions => Icons.lock_outline,
    };
    final displayTitle = switch (approval.kind) {
      ApprovalKind.browser => 'Browser',
      ApprovalKind.command => 'Terminal',
      ApprovalKind.fileChange => '文件变更',
      ApprovalKind.permissions => '权限请求',
    };
    final browserUrl = _browserUrlFromParams(approval.params);
    final reason = approval.reason;
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
            constraints: const BoxConstraints(maxWidth: 600),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
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
                    Icon(icon, size: 15, color: palette.muted),
                    const SizedBox(width: 7),
                    Text(
                      displayTitle,
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
                        if (isBrowser && browserUrl != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '允许 ChatGPT 访问 $browserUrl？',
                            style: TextStyle(
                              color: palette.trace,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (!isBrowser && reason != null) ...[
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
                        if (!isBrowser &&
                            approval.reason == null &&
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
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isBrowser)
                      TextButton(
                        key: const Key('approval-allow-all-sites'),
                        onPressed: enabled ? onAllowSimilar : null,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.muted,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('允许所有网站'),
                      ),
                    OutlinedButton(
                      key: const Key('approval-decline'),
                      onPressed: enabled ? onDecline : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.muted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('拒绝  Esc'),
                    ),
                    FilledButton(
                      key: const Key('approval-allow-once'),
                      onPressed: enabled ? onAccept : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.field,
                        foregroundColor: palette.trace,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: Text(isBrowser ? '允许一次  ↵' : '允许一次'),
                    ),
                    if (approval.kind != ApprovalKind.fileChange && !isBrowser)
                      PopupMenuButton<String>(
                        key: const Key('approval-more-options'),
                        tooltip: '更多允许选项',
                        enabled: enabled,
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 17),
                        onSelected: (_) => onAllowSimilar(),
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'similar',
                            child: Text(isBrowser ? '允许所有网站' : '允许类似操作'),
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

  /// Extracts the same supported browser URL shapes accepted by the
  /// controller, including nested App Server payloads.
  String? _browserUrlFromParams(Object? value) {
    if (value is String) {
      final uri = Uri.tryParse(value.trim());
      if (uri != null &&
          uri.hasAuthority &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        return uri.toString();
      }
      return null;
    }
    if (value is! Map) return null;
    const directKeys = [
      'url',
      'uri',
      'href',
      'targetUrl',
      'target_url',
      'initialUrl',
      'initial_url',
    ];
    for (final key in directKeys) {
      final candidate = _browserUrlFromParams(value[key]);
      if (candidate != null) return candidate;
    }
    for (final key in ['action', 'request', 'input', 'payload', 'item']) {
      final candidate = _browserUrlFromParams(value[key]);
      if (candidate != null) return candidate;
    }
    return null;
  }
}
