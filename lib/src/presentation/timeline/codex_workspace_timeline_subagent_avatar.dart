import 'package:flutter/material.dart';

/// Stable, local avatar used to distinguish concurrently running subagents.
class SubagentAvatar extends StatelessWidget {
  const SubagentAvatar({super.key, required this.agentId, this.size = 16});

  static const _assets = <String>[
    'assets/subagents/subagent-01.png',
    'assets/subagents/subagent-02.png',
    'assets/subagents/subagent-03.png',
    'assets/subagents/subagent-04.png',
    'assets/subagents/subagent-05.png',
    'assets/subagents/subagent-06.png',
    'assets/subagents/subagent-07.png',
    'assets/subagents/subagent-08.png',
    'assets/subagents/subagent-09.png',
    'assets/subagents/subagent-10.png',
  ];

  final String agentId;
  final double size;

  /// Selects one of the supplied avatars from a stable child-thread identity.
  static String assetFor(String agentId) {
    var hash = 0;
    for (final unit in agentId.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return _assets[hash % _assets.length];
  }

  @override
  Widget build(BuildContext context) => Image.asset(
    assetFor(agentId),
    width: size,
    height: size,
    filterQuality: FilterQuality.none,
    excludeFromSemantics: true,
  );
}
