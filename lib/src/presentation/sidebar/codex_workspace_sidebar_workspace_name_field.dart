// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';

class WorkspaceNameField extends StatelessWidget {
  const WorkspaceNameField({
    required this.controller,
    this.hintText,
    this.borderColor,
  });

  final TextEditingController controller;
  final String? hintText;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Container(
      height: 80,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor ?? palette.active, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Center(
              child: Icon(
                Icons.folder_outlined,
                size: 20,
                color: palette.trace,
              ),
            ),
          ),
          Container(width: 1, height: double.infinity, color: palette.border),
          Expanded(
            child: TextField(
              key: const Key('workspace-project-name-field'),
              controller: controller,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                // The surrounding container owns the field border. Explicitly
                // override every themed state border so the TextField cannot
                // render a second outline when focused.
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: hintText,
                contentPadding: EdgeInsets.symmetric(horizontal: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
