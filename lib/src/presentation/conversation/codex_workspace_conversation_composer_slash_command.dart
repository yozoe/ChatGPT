import 'package:flutter/material.dart';

/// Identifies the Composer surface that can expose a command.
enum ComposerMenuSurface { slash, mention, add }

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
    this.surfaces = const {ComposerMenuSurface.slash},
  });

  final ComposerSlashCommandKind kind;
  final String label;
  final String description;
  final IconData icon;
  final List<String> aliases;
  final bool enabled;
  final Set<ComposerMenuSurface> surfaces;

  ComposerSlashCommand copyWith({
    String? label,
    String? description,
    bool? enabled,
    IconData? icon,
    List<String>? aliases,
    Set<ComposerMenuSurface>? surfaces,
  }) => ComposerSlashCommand(
    kind: kind,
    label: label ?? this.label,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    aliases: aliases ?? this.aliases,
    enabled: enabled ?? this.enabled,
    surfaces: surfaces ?? this.surfaces,
  );

  bool supports(ComposerMenuSurface surface) => surfaces.contains(surface);

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return label.toLowerCase().contains(normalized) ||
        description.toLowerCase().contains(normalized) ||
        aliases.any((alias) => alias.toLowerCase().contains(normalized));
  }
}
