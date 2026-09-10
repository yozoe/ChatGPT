import 'package:flutter/foundation.dart';

/// Live MCP connection and authentication state reported by App Server.
@immutable
class CodexMcpRuntimeStatus {
  const CodexMcpRuntimeStatus({
    required this.name,
    required this.authStatus,
    required this.runtimeStatus,
    required this.toolCount,
    this.title,
  });

  final String name;
  final String authStatus;
  final String? runtimeStatus;
  final int toolCount;
  final String? title;

  String get displayName => title?.trim().isNotEmpty == true ? title! : name;

  CodexMcpRuntimeStatus copyWith({String? runtimeStatus}) =>
      CodexMcpRuntimeStatus(
        name: name,
        authStatus: authStatus,
        runtimeStatus: runtimeStatus ?? this.runtimeStatus,
        toolCount: toolCount,
        title: title,
      );

  static CodexMcpRuntimeStatus? fromJson(Map<dynamic, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final rawTools = json['tools'];
    final serverInfo = json['serverInfo'];
    final title = serverInfo is Map
        ? serverInfo['title']?.toString().trim()
        : null;
    return CodexMcpRuntimeStatus(
      name: name,
      authStatus: json['authStatus']?.toString().trim() ?? 'unknown',
      runtimeStatus: json['runtimeStatus']?.toString().trim(),
      toolCount: rawTools is Map ? rawTools.length : 0,
      title: title?.isNotEmpty == true ? title : null,
    );
  }
}
