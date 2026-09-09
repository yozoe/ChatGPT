import 'package:flutter/material.dart';

/// Identifies an action available from the Composer slash-command menu.
enum ComposerSlashCommandKind {
  workspaceContext,
  files,
  goal,
  planMode,
  recordSkill,
  mcpStatus,
  codeReview,
  sideChat,
  forkChat,
  compact,
  feedback,
  archive,
  reasoning,
  model,
  newChat,
}

/// Describes one Composer slash command and the text used to search for it.
class ComposerSlashCommand {
  const ComposerSlashCommand({
    required this.kind,
    required this.label,
    required this.description,
    required this.icon,
    this.aliases = const [],
    this.enabled = true,
  });

  final ComposerSlashCommandKind kind;
  final String label;
  final String description;
  final IconData icon;
  final List<String> aliases;
  final bool enabled;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return label.toLowerCase().contains(normalized) ||
        description.toLowerCase().contains(normalized) ||
        aliases.any((alias) => alias.toLowerCase().contains(normalized));
  }
}
