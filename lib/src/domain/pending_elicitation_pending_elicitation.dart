// Extracted class from pending_elicitation.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'pending_elicitation_support.dart';
import 'pending_elicitation_elicitation_field.dart';

class PendingElicitation {
  const PendingElicitation({
    required this.requestId,
    required this.params,
    required this.mode,
    required this.message,
    required this.serverName,
    this.fields = const [],
    this.url,
  });

  final Object requestId;
  final JsonMap params;
  final ElicitationMode mode;
  final String message;
  final String serverName;
  final List<ElicitationField> fields;
  final String? url;

  String? get threadId {
    final direct = params['threadId']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return null;
  }

  String get title => mode == ElicitationMode.url ? 'MCP 链接确认' : 'MCP 需要你的输入';

  /// Parses the two App Server elicitation request shapes. Only simple scalar
  /// JSON-schema fields are rendered, so no nested or executable schema can
  /// change client behaviour.
  static PendingElicitation? fromEvent(ServerEvent event) {
    if (event.requestId == null ||
        event.method != 'mcpServer/elicitation/request') {
      return null;
    }
    final mode = event.params['mode']?.toString();
    final message = event.params['message']?.toString().trim();
    final serverName = event.params['serverName']?.toString().trim();
    if (message == null || message.isEmpty) return null;

    if (mode == 'url') {
      final url = event.params['url']?.toString().trim();
      final parsed = url == null ? null : Uri.tryParse(url);
      if (url == null ||
          url.isEmpty ||
          parsed == null ||
          !(parsed.scheme == 'https' || parsed.scheme == 'http')) {
        return null;
      }
      return PendingElicitation(
        requestId: event.requestId!,
        params: event.params,
        mode: ElicitationMode.url,
        message: message,
        serverName: serverName == null || serverName.isEmpty
            ? 'MCP 服务器'
            : serverName,
        url: url,
      );
    }

    if (mode != 'form' && mode != 'openai/form') return null;
    final schema = event.params['requestedSchema'];
    if (schema is! Map) return null;
    final fields = _fieldsFromSchema(schema);
    if (fields == null) return null;
    return PendingElicitation(
      requestId: event.requestId!,
      params: event.params,
      mode: ElicitationMode.form,
      message: message,
      serverName: serverName == null || serverName.isEmpty
          ? 'MCP 服务器'
          : serverName,
      fields: fields,
    );
  }

  static List<ElicitationField>? _fieldsFromSchema(Map schema) {
    final type = schema['type'];
    if (type != null && type != 'object') return null;
    final properties = schema['properties'];
    if (properties != null && properties is! Map) return null;
    final requiredRaw = schema['required'];
    if (requiredRaw != null && requiredRaw is! List) return null;
    final requiredValues = requiredRaw ?? const [];
    final required = <String>{
      for (final value in requiredValues)
        if (value is String) value,
    };
    if (requiredValues.length != required.length) {
      return null;
    }

    final fields = <ElicitationField>[];
    for (final entry in (properties as Map? ?? const {}).entries) {
      if (entry.key is! String || entry.value is! Map) return null;
      final definition = entry.value;
      final fieldType = definition['type']?.toString() ?? 'string';
      if (!const {
        'string',
        'number',
        'integer',
        'boolean',
      }.contains(fieldType)) {
        return null;
      }
      final optionsRaw = definition['enum'];
      if (optionsRaw != null && optionsRaw is! List) return null;
      final options = <Object>[];
      for (final option in optionsRaw as List? ?? const []) {
        if (!_matchesType(option, fieldType)) return null;
        if (options.contains(option)) return null;
        options.add(option);
      }
      final defaultValue = definition['default'];
      if (defaultValue != null && !_matchesType(defaultValue, fieldType)) {
        return null;
      }
      if (defaultValue != null &&
          options.isNotEmpty &&
          !options.contains(defaultValue)) {
        return null;
      }
      fields.add(
        ElicitationField(
          name: entry.key as String,
          type: fieldType,
          title: definition['title']?.toString().trim().isNotEmpty == true
              ? definition['title'].toString()
              : entry.key as String,
          description: definition['description']?.toString(),
          required: required.contains(entry.key),
          defaultValue: defaultValue,
          options: options,
        ),
      );
    }
    if (required.any((name) => !fields.any((field) => field.name == name))) {
      return null;
    }
    return List.unmodifiable(fields);
  }

  static bool _matchesType(Object? value, String type) => switch (type) {
    'string' => value is String,
    'number' => value is num,
    'integer' => value is int,
    'boolean' => value is bool,
    _ => false,
  };
}
