// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_attachment.dart';

class ComposerSubmission {
  const ComposerSubmission({
    required this.attachments,
    required this.includeWorkspace,
    required this.goal,
    required this.planMode,
    required this.recordSkill,
    required this.skills,
  });

  final List<ComposerAttachment> attachments;
  final bool includeWorkspace;
  final String? goal;
  final bool planMode;
  final bool recordSkill;
  final List<CodexSkill> skills;

  bool get hasContext =>
      attachments.isNotEmpty ||
      includeWorkspace ||
      goal?.isNotEmpty == true ||
      planMode ||
      recordSkill ||
      skills.isNotEmpty;
}
