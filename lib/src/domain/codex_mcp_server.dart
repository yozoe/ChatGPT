import 'package:flutter/foundation.dart';

enum CodexMcpServerScope { user, project, managed }

/// 本机 Codex 配置中的一个 MCP 服务器。
/// An MCP server from the local Codex configuration.
@immutable
class CodexMcpServer {
  const CodexMcpServer({
    required this.name,
    required this.enabled,
    required this.transportLabel,
    this.authStatus,
    this.scope = CodexMcpServerScope.user,
    this.configurationPath,
  });

  final String name;
  final bool enabled;
  final String transportLabel;
  final String? authStatus;
  final CodexMcpServerScope scope;
  final String? configurationPath;

  bool get canChangeEnabled => scope != CodexMcpServerScope.managed;

  String get scopeLabel => switch (scope) {
    CodexMcpServerScope.user => '用户',
    CodexMcpServerScope.project => '项目',
    CodexMcpServerScope.managed => '托管',
  };

  CodexMcpServer copyWith({
    bool? enabled,
    CodexMcpServerScope? scope,
    String? configurationPath,
  }) => CodexMcpServer(
    name: name,
    enabled: enabled ?? this.enabled,
    transportLabel: transportLabel,
    authStatus: authStatus,
    scope: scope ?? this.scope,
    configurationPath: configurationPath ?? this.configurationPath,
  );

  static CodexMcpServer? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final transport = json['transport'];
    final transportMap = transport is Map
        ? Map<String, dynamic>.from(transport)
        : const <String, dynamic>{};
    final type = transportMap['type']?.toString();
    final label = switch (type) {
      'streamable_http' => transportMap['url']?.toString().trim(),
      'stdio' => transportMap['command']?.toString().trim(),
      _ => null,
    };
    return CodexMcpServer(
      name: name,
      enabled: json['enabled'] != false,
      transportLabel: label?.isNotEmpty == true
          ? label!
          : switch (type) {
              'streamable_http' => 'HTTP',
              'stdio' => '本地进程',
              _ => 'MCP 服务器',
            },
      authStatus: json['auth_status']?.toString(),
    );
  }
}
