import '../services/codex_app_server.dart';

class CodexThread {
  const CodexThread({
    required this.id,
    required this.preview,
    required this.createdAt,
    required this.updatedAt,
    this.modelProvider,
    this.model,
    this.name,
    this.status,
  });

  final String id;
  final String preview;
  final int createdAt;
  final int updatedAt;
  final String? modelProvider;
  final String? model;
  final String? name;
  final String? status;

  /// 返回优先采用名称、其次采用预览内容的显示标题。
  /// Returns a display title, preferring the name over the preview.
  String get title {
    final value = name?.trim();
    if (value != null && value.isNotEmpty) return value;
    final summary = preview.trim();
    return summary.isEmpty ? '未命名任务' : summary;
  }

  /// 从 App Server 线程 JSON 创建线程对象。
  /// Creates a thread object from App Server thread JSON.
  factory CodexThread.fromJson(JsonMap value) {
    final id = value['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException(
        'App Server returned a thread without an id.',
      );
    }
    final statusValue = value['status'];
    final status = statusValue is Map
        ? statusValue['type']?.toString()
        : statusValue?.toString();
    return CodexThread(
      id: id,
      preview: value['preview']?.toString() ?? '',
      modelProvider: value['modelProvider']?.toString(),
      model: value['model']?.toString(),
      name: value['name']?.toString(),
      createdAt: _toInt(value['createdAt']),
      updatedAt: _toInt(value['updatedAt']),
      status: status,
    );
  }

  /// 返回替换可选名称后的线程副本。
  /// Returns a thread copy with an optional replacement name.
  CodexThread copyWith({String? name, String? status}) => CodexThread(
    id: id,
    preview: preview,
    modelProvider: modelProvider,
    model: model,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt,
    status: status ?? this.status,
  );

  /// 将线程转换为本地历史缓存使用的 JSON。
  /// Converts the thread to JSON for the local history cache.
  JsonMap toJson() => {
    'id': id,
    'preview': preview,
    'modelProvider': ?modelProvider,
    'model': ?model,
    'name': ?name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'status': ?status,
  };

  /// 将协议中的数值安全转换为整数，缺失或无效时返回零。
  /// Safely converts a protocol number to an integer, returning zero when invalid.
  static int _toInt(Object? value) => value is num ? value.toInt() : 0;
}
