// Extracted class from codex_workspace_extensions.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions_support.dart';

class ExtensionSettingsList extends StatelessWidget {
  const ExtensionSettingsList({
    required this.children,
    required this.emptyMessage,
    this.header,
    this.grouped = false,
  });

  final List<Widget> children;
  final String emptyMessage;
  final Widget? header;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 28),
      children: [
        if (header != null) ...[
          Padding(padding: const EdgeInsets.only(bottom: 12), child: header!),
        ],
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Center(
              child: Text(emptyMessage, style: TextStyle(color: palette.muted)),
            ),
          )
        else if (grouped)
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index < children.length - 1)
                    Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          )
        else
          ...children,
      ],
    );
  }
}
