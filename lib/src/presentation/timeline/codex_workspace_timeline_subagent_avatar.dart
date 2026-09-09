import 'package:flutter/material.dart';

/// 按子线程身份稳定选择的本地头像，用于区分并发运行的子智能体。
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

  /// 根据稳定的子线程身份从头像集合中选择一个资源。
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
