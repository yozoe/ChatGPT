// Extracted class from codex_workspace_timeline.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ProviderChip extends StatelessWidget {
  const ProviderChip({super.key, this.label = 'OpenAI / App Server'});

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
