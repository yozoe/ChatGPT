// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';

class GitDiffViewer extends StatelessWidget {
  const GitDiffViewer({
    required this.change,
    required this.diff,
    required this.loading,
    required this.truncated,
  });

  final GitProjectChange? change;
  final String? diff;
  final bool loading;
  final bool truncated;

  /// 构建所选 Git 文件的加载、空状态或可复制 Diff 内容。
  /// Builds loading, empty, or copyable diff content for the selected Git file.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (change == null) return const Center(child: Text('从左侧选择一个文件查看 Diff。'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          change!.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (truncated) ...[
          Container(
            key: const Key('git-diff-truncated-warning'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.warning),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Diff 过大，当前仅显示前 120,000 个字符。')),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: diff == null
                ? const Center(child: Text('正在准备 Diff。'))
                : diff!.isEmpty
                ? const Center(child: Text('Git 未返回可显示的 Diff。'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        diff!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
