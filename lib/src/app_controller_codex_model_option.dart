// Extracted class from app_controller.dart.

/// App Server 模型目录中可供新任务选择的只读条目。
/// A read-only model-catalog entry that can be selected for new App Server threads.
class CodexModelOption {
  const CodexModelOption({
    required this.id,
    required this.displayName,
    required this.description,
    required this.isDefault,
  });

  final String id;
  final String displayName;
  final String description;
  final bool isDefault;
}
