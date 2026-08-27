// Extracted class from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_support.dart';

class ProviderChip extends StatelessWidget {
  const ProviderChip({this.label = 'OpenAI / App Server'});

  final String label;

  /// 构建 Provider 或运行时边界的紧凑说明标签。
  /// Builds a compact label for a provider or runtime boundary.
  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
