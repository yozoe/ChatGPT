// Test double extracted from widget_test.dart.
import 'dart:async';
import 'dart:math' as math;
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/codex_plugin.dart';
import 'package:chatgpt/src/domain/codex_skill.dart';
import 'package:chatgpt/src/domain/codex_marketplace.dart';
import 'package:chatgpt/src/domain/codex_mcp_server.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/domain/scheduled_task.dart';
import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/codex_plugin_store.dart';
import 'package:chatgpt/src/services/conversation_history_store.dart';
import 'package:chatgpt/src/services/git_project_service.dart';
import 'package:chatgpt/src/services/local_session_thread_store.dart';
import 'package:chatgpt/src/services/runtime_configuration_store.dart';
import 'package:chatgpt/src/services/theme_preferences_store.dart';

class MemoryConversationHistoryStore extends ConversationHistoryStore {
  final snapshots = <String, ConversationHistorySnapshot>{};

  /// 从内存快照表读取指定项目的历史。
  /// Reads a workspace history from the in-memory snapshot map.
  @override
  Future<ConversationHistorySnapshot?> read(String workspace) async {
    return snapshots[workspace];
  }

  /// 将指定项目的历史快照保存到内存。
  /// Saves a workspace history snapshot in memory.
  @override
  Future<void> save({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    snapshots[workspace] = snapshot;
  }
}
// ignore_for_file: unused_import, unnecessary_import
