// Extracted class from conversation_history_store.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'app_storage_scope.dart';
import 'codex_keychain_storage.dart';
import 'conversation_history_store_support.dart';
import 'conversation_history_store_conversation_history_snapshot.dart';

class PortableConversationHistory {
  const PortableConversationHistory({
    required this.workspace,
    required this.exportedAt,
    required this.snapshot,
  });

  static const schemaVersion = 1;

  final String workspace;
  final DateTime exportedAt;
  final ConversationHistorySnapshot snapshot;

  /// 将可移植历史转换为包含版本和来源项目的 JSON。
  /// Converts portable history to JSON containing its version and source workspace.
  Map<String, dynamic> toJson() => {
    'format': 'codex-desk-history',
    'version': schemaVersion,
    'workspace': workspace,
    'exportedAt': exportedAt.toIso8601String(),
    'snapshot': snapshot.toJson(),
  };

  /// 验证并解析由 Codex Desk 导出的可移植历史 JSON。
  /// Validates and parses portable-history JSON exported by Codex Desk.
  factory PortableConversationHistory.fromJson(Map<dynamic, dynamic> value) {
    if (value['format'] != 'codex-desk-history' ||
        value['version'] != schemaVersion ||
        value['snapshot'] is! Map) {
      throw const FormatException('不是受支持的 Codex Desk 历史导出文件。');
    }
    return PortableConversationHistory(
      workspace: value['workspace']?.toString() ?? '',
      exportedAt:
          DateTime.tryParse(value['exportedAt']?.toString() ?? '') ??
          DateTime.now(),
      snapshot: ConversationHistorySnapshot.fromJson(value['snapshot'] as Map),
    );
  }
}
