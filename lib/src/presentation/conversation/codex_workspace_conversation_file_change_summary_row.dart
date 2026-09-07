// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_file_change_summary_row_state.dart';

class FileChangeSummaryRow extends StatefulWidget {
  const FileChangeSummaryRow({
    super.key,
    required this.change,
    this.fallbackDiff,
  });

  final CodexFileChange change;
  final String? fallbackDiff;

  @override
  State<FileChangeSummaryRow> createState() => FileChangeSummaryRowState();
}
