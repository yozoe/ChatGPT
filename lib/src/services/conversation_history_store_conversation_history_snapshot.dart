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

class ConversationHistorySnapshot {
  const ConversationHistorySnapshot({
    required this.threads,
    required this.archivedThreads,
    required this.entries,
    required this.fileChanges,
    this.pinnedThreadIds = const {},
    this.acknowledgedCompletedThreadIds = const {},
    this.turnDiff,
    this.activeThreadId,
    this.ownedThreadIds = const {},
    this.historyInitialized = false,
  });

  final List<CodexThread> threads;
  final List<CodexThread> archivedThreads;
  final List<TimelineEntry> entries;
  final List<CodexFileChange> fileChanges;
  final Set<String> pinnedThreadIds;

  /// Completed-task reminders that the user has already viewed.
  final Set<String> acknowledgedCompletedThreadIds;
  final String? turnDiff;

  /// The thread that was open when the workspace snapshot was saved.
  /// 保存快照时当前打开的线程；旧版本快照没有此字段时保持为空。
  final String? activeThreadId;

  /// Thread IDs explicitly belonging to this project.
  final Set<String> ownedThreadIds;

  /// Whether the project has established its thread boundary.
  final bool historyInitialized;

  /// 将当前工作区快照转换为可持久化的 JSON。
  /// Converts the current workspace snapshot to persistable JSON.
  Map<String, dynamic> toJson() => {
    'threads': threads.map((thread) => thread.toJson()).toList(),
    'archivedThreads': archivedThreads
        .map((thread) => thread.toJson())
        .toList(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'fileChanges': fileChanges.map((change) => change.toJson()).toList(),
    'pinnedThreadIds': pinnedThreadIds.toList(growable: false),
    'acknowledgedCompletedThreadIds': acknowledgedCompletedThreadIds.toList(
      growable: false,
    ),
    'turnDiff': ?turnDiff,
    'activeThreadId': ?activeThreadId,
    'ownedThreadIds': ownedThreadIds.toList(growable: false),
    'historyInitialized': historyInitialized,
  };

  /// 从持久化 JSON 恢复当前工作区快照。
  /// Restores a workspace snapshot from persisted JSON.
  factory ConversationHistorySnapshot.fromJson(Map<dynamic, dynamic> value) {
    /// 过滤无效元素并按调用方指定的解析函数恢复列表。
    /// Filters invalid elements and restores a list with the supplied parser.
    List<T> decodeList<T>(
      Object? raw,
      T Function(Map<dynamic, dynamic>) parse,
    ) {
      if (raw is! Iterable) return const [];
      return raw.whereType<Map>().map(parse).toList(growable: false);
    }

    final decodedThreads = decodeList(
      value['threads'],
      (thread) => CodexThread.fromJson(Map<String, dynamic>.from(thread)),
    );
    final decodedArchivedThreads = decodeList(
      value['archivedThreads'],
      (thread) => CodexThread.fromJson(Map<String, dynamic>.from(thread)),
    );
    final explicitOwned = value['ownedThreadIds'] is Iterable
        ? (value['ownedThreadIds'] as Iterable)
              .where((id) => id != null)
              .map((id) => id.toString().trim())
              .where((id) => id.isNotEmpty)
              .toSet()
        : <String>{};
    // Older snapshots did not have an ownership field; their visible threads
    // are the safest migration source.
    final owned = <String>{
      ...explicitOwned,
      ...decodedThreads.map((thread) => thread.id),
      ...decodedArchivedThreads.map((thread) => thread.id),
    };
    return ConversationHistorySnapshot(
      threads: decodedThreads,
      archivedThreads: decodedArchivedThreads,
      entries: decodeList(value['entries'], TimelineEntry.fromJson),
      fileChanges: decodeList(value['fileChanges'], CodexFileChange.fromJson),
      pinnedThreadIds: value['pinnedThreadIds'] is Iterable
          ? (value['pinnedThreadIds'] as Iterable)
                .where((id) => id != null)
                .map((id) => id.toString())
                .where((id) => id.isNotEmpty)
                .toSet()
          : const {},
      acknowledgedCompletedThreadIds:
          value['acknowledgedCompletedThreadIds'] is Iterable
          ? (value['acknowledgedCompletedThreadIds'] as Iterable)
                .where((id) => id != null)
                .map((id) => id.toString())
                .where((id) => id.isNotEmpty)
                .toSet()
          : const {},
      turnDiff: value['turnDiff']?.toString(),
      activeThreadId: value['activeThreadId']?.toString().trim().isEmpty == true
          ? null
          : value['activeThreadId']?.toString(),
      ownedThreadIds: owned,
      historyInitialized:
          value['historyInitialized'] == true || owned.isNotEmpty,
    );
  }
}
