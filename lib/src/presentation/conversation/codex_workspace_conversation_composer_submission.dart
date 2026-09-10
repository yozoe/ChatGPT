// Extracted class from codex_workspace_conversation.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_attachment.dart';

class ComposerSubmission {
  const ComposerSubmission({
    required this.prompt,
    required this.attachments,
    this.pastedTexts = const [],
    required this.includeWorkspace,
    required this.goal,
    required this.planMode,
    required this.skills,
  });

  /// The immutable composer text captured when the user submits.
  final String prompt;
  final List<ComposerAttachment> attachments;
  final List<String> pastedTexts;
  final bool includeWorkspace;
  final String? goal;
  final bool planMode;
  final List<CodexSkill> skills;

  bool get hasContext =>
      attachments.isNotEmpty ||
      pastedTexts.isNotEmpty ||
      includeWorkspace ||
      goal?.isNotEmpty == true ||
      planMode ||
      skills.isNotEmpty;
}
