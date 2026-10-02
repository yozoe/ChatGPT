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
  draw,
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

/// Sorts a surface's shared command catalog without duplicating menu order.
List<ComposerSlashCommand> sortComposerCommands(
  Iterable<ComposerSlashCommand> commands,
  ComposerMenuSurface surface,
) {
  final indexed = commands.toList(growable: false).indexed.toList();
  indexed.sort((a, b) {
    final order = a.$2
        .orderFor(surface, a.$1)
        .compareTo(b.$2.orderFor(surface, b.$1));
    return order == 0 ? a.$1.compareTo(b.$1) : order;
  });
  return [for (final entry in indexed) entry.$2];
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
    this.surfaceOrder = const {},
  });

  final ComposerSlashCommandKind kind;
  final String label;
  final String description;
  final IconData icon;
  final List<String> aliases;
  final bool enabled;
  final Set<ComposerMenuSurface> surfaces;

  /// Stable position for each menu surface. Lower values appear first.
  final Map<ComposerMenuSurface, int> surfaceOrder;

  ComposerSlashCommand copyWith({
    String? label,
    String? description,
    bool? enabled,
    IconData? icon,
    List<String>? aliases,
    Set<ComposerMenuSurface>? surfaces,
    Map<ComposerMenuSurface, int>? surfaceOrder,
  }) => ComposerSlashCommand(
    kind: kind,
    label: label ?? this.label,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    aliases: aliases ?? this.aliases,
    enabled: enabled ?? this.enabled,
    surfaces: surfaces ?? this.surfaces,
    surfaceOrder: surfaceOrder ?? this.surfaceOrder,
  );

  bool supports(ComposerMenuSurface surface) => surfaces.contains(surface);

  int orderFor(ComposerMenuSurface surface, int fallback) =>
      surfaceOrder[surface] ?? fallback;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return label.toLowerCase().contains(normalized) ||
        description.toLowerCase().contains(normalized) ||
        aliases.any((alias) => alias.toLowerCase().contains(normalized));
  }
}
