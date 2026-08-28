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
  newChat,
}

/// Describes one Composer slash command and the text used to search for it.
class ComposerSlashCommand {
  const ComposerSlashCommand({
    required this.kind,
    required this.label,
    required this.description,
    required this.icon,
  });

  final ComposerSlashCommandKind kind;
  final String label;
  final String description;
  final IconData icon;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return label.toLowerCase().contains(normalized) ||
        description.toLowerCase().contains(normalized);
  }
}
