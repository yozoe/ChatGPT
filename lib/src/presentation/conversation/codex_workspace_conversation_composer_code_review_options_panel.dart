import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// Lists the review scopes available after selecting the Composer review command.
class ComposerCodeReviewOptionsPanel extends StatelessWidget {
  const ComposerCodeReviewOptionsPanel({
    super.key,
    required this.baseBranches,
    required this.loading,
    required this.error,
    required this.reviewSubmissionPending,
    required this.onReviewUncommitted,
    required this.onReviewBranch,
  });

  final List<String> baseBranches;
  final bool loading;
  final String? error;
  final bool reviewSubmissionPending;
  final VoidCallback onReviewUncommitted;
  final ValueChanged<String> onReviewBranch;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final branchRows = loading || error != null || baseBranches.isEmpty
        ? 1
        : baseBranches.length;
    final listHeight = (78.0 + branchRows * 40.0).clamp(120.0, 344.0);
    return Semantics(
      container: true,
      label: '代码审查范围',
      child: Container(
        key: const Key('composer-code-review-options-panel'),
        constraints: const BoxConstraints(maxHeight: 360),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: palette.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.controlBorder),
        ),
        child: SizedBox(
          height: listHeight,
          child: ListView(
            children: [
              InkWell(
                key: const Key('composer-code-review-uncommitted'),
                borderRadius: BorderRadius.circular(10),
                onTap: reviewSubmissionPending ? null : onReviewUncommitted,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '审查未提交的更改',
                        style: TextStyle(color: palette.trace, fontSize: 13),
                      ),
                      if (reviewSubmissionPending) ...[
                        const SizedBox(height: 3),
                        Text(
                          '等待当前任务接收审查…',
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '对照基础分支审查',
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 4),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (error != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '无法读取 Git 分支：$error',
                    style: TextStyle(color: palette.fault, fontSize: 12),
                  ),
                )
              else if (baseBranches.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '当前项目没有可用的基础分支。',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                )
              else
                for (final branch in baseBranches)
                  InkWell(
                    key: ValueKey('composer-code-review-base-$branch'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onReviewBranch(branch),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Text(
                        branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.trace, fontSize: 13),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
