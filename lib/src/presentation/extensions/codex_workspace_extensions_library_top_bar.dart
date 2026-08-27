// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';

class LibraryTopBar extends StatelessWidget {
  const LibraryTopBar({
    required this.createLabel,
    required this.onCreate,
    this.actions = const [],
    this.leading = const [],
    this.createControl,
  });
  final String createLabel;
  final VoidCallback onCreate;
  final List<Widget> actions;
  final List<Widget> leading;
  final Widget? createControl;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Row(
      children: [
        const SizedBox(width: 20),
        ...leading,
        const Spacer(),
        ...actions,
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child:
              createControl ??
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: Text(createLabel),
              ),
        ),
      ],
    ),
  );
}
