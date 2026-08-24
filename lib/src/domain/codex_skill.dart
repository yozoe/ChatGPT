import 'package:flutter/foundation.dart';

/// 当前工作区可用、由 App Server 公布的 Codex 技能元数据。
/// A Codex skill advertised by App Server for the active workspace.
@immutable
class CodexSkill {
  const CodexSkill({
    required this.name,
    required this.path,
    required this.description,
    required this.enabled,
    required this.scope,
    this.displayName,
    this.shortDescription,
  });

  final String name;
  final String path;
  final String description;
  final bool enabled;
  final String scope;
  final String? displayName;
  final String? shortDescription;

  /// 优先使用技能接口提供的显示名，缺失时回退到稳定标识。
  /// Prefers the skill interface display name and falls back to its stable id.
  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName!.trim() : name;

  /// 为紧凑列表选择较短说明，未提供时使用完整描述。
  /// Uses the short description for compact lists, falling back to full text.
  String get summary => shortDescription?.trim().isNotEmpty == true
      ? shortDescription!.trim()
      : description.trim();

  /// Parses a skill row returned by `skills/list`.
  static CodexSkill? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final path = json['path']?.toString().trim() ?? '';
    if (name.isEmpty || path.isEmpty) return null;
    final interface = json['interface'];
    final interfaceMap = interface is Map
        ? Map<String, dynamic>.from(interface)
        : const <String, dynamic>{};
    return CodexSkill(
      name: name,
      path: path,
      description: json['description']?.toString() ?? '',
      enabled: json['enabled'] != false,
      scope: json['scope']?.toString() ?? 'user',
      displayName: interfaceMap['displayName']?.toString(),
      shortDescription:
          interfaceMap['shortDescription']?.toString() ??
          json['shortDescription']?.toString(),
    );
  }
}
