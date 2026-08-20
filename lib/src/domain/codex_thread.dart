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

  String get title {
    final value = name?.trim();
    if (value != null && value.isNotEmpty) return value;
    final summary = preview.trim();
    return summary.isEmpty ? '未命名任务' : summary;
  }

  factory CodexThread.fromJson(JsonMap value) {
    final id = value['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException(
        'App Server returned a thread without an id.',
      );
    }
    final statusValue = value['status'];
    final status = statusValue is Map ? statusValue['type']?.toString() : null;
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

  CodexThread copyWith({String? name}) => CodexThread(
    id: id,
    preview: preview,
    modelProvider: modelProvider,
    model: model,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt,
    status: status,
  );

  static int _toInt(Object? value) => value is num ? value.toInt() : 0;
}
