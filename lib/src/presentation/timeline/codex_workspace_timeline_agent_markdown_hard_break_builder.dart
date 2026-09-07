// Extracted class from codex_workspace_timeline.dart.
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class AgentMarkdownHardBreakBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => const SizedBox(width: double.infinity);
}
