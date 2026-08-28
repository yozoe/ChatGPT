// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class AgentFileLink extends StatelessWidget {
  const AgentFileLink({
    required this.href,
    required this.reference,
    required this.workspacePath,
  });

  final String href;
  final WorkspaceFileReference reference;
  final String workspacePath;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final fileName = reference.path.split(Platform.pathSeparator).last;
    return Semantics(
      button: true,
      label: '打开文件 $fileName',
      excludeSemantics: true,
      child: Tooltip(
        message: reference.path,
        waitDuration: const Duration(milliseconds: 450),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            hoverColor: palette.raised,
            onTap: () => unawaited(
              openAgentMarkdownDestination(
                context,
                href: href,
                workspacePath: workspacePath,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: palette.active,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      fileName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.active,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
