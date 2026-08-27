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
import 'memory_conversation_history_store.dart';

class BlockingConversationHistoryStore extends MemoryConversationHistoryStore {
  final firstSaveStarted = Completer<void>();
  final allowFirstSave = Completer<void>();
  int saveCalls = 0;

  /// 可选地阻塞第一次保存，以验证控制器的写入串行化。
  /// Optionally blocks the first save to verify controller write serialization.
  @override
  Future<void> save({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    saveCalls++;
    if (saveCalls == 1) {
      firstSaveStarted.complete();
      await allowFirstSave.future;
    }
    await super.save(workspace: workspace, snapshot: snapshot);
  }
}
// ignore_for_file: unused_import, unnecessary_import
