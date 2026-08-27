// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_copy_command.dart';

class PullRequestsPage extends StatelessWidget {
  const PullRequestsPage({
    required this.controller,
    required this.onOpenGitProject,
    required this.onAskCodex,
  });
  final CodexController controller;
  final Future<void> Function() onOpenGitProject;
  final VoidCallback onAskCodex;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final status = controller.gitProjectStatus;
    return Column(
      children: [
        const SizedBox(
          height: 56,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Pull Request',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 7,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.code, size: 38, color: palette.trace),
                        const SizedBox(height: 22),
                        Text(
                          status?.isRepository == true
                              ? '管理 Pull Request'
                              : '安装 GitHub CLI',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          status?.isRepository == true
                              ? '查看当前项目的分支、变更和拉取请求创建流程。'
                              : '安装 GitHub CLI 以查看和管理你的 Pull Request',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.muted),
                        ),
                        const SizedBox(height: 20),
                        CopyCommand(command: 'brew install gh'),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: '刷新',
                              onPressed: controller.refreshGitProject,
                              icon: const Icon(Icons.refresh),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              key: const Key('pull-requests-open-git-project'),
                              onPressed: status?.isRepository == true
                                  ? () => onOpenGitProject()
                                  : onAskCodex,
                              child: Text(
                                status?.isRepository == true
                                    ? '打开 Git 项目'
                                    : '询问 Codex',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: palette.border),
              const Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    '选择要查看的 Pull Request',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
