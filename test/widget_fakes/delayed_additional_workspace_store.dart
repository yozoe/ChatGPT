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
import 'fake_runtime_configuration_store.dart';

class DelayedAdditionalWorkspaceStore extends FakeRuntimeConfigurationStore {
  final savedSnapshots = <List<String>>[];
  final saveCompleters = <Completer<void>>[];

  /// 记录目录快照并延迟写入完成，用于验证保存顺序。
  /// Records directory snapshots and delays completion to verify save ordering.
  @override
  Future<void> saveAdditionalWorkspaces(List<String> workspaces) {
    savedSnapshots.add(List.of(workspaces));
    final completer = Completer<void>();
    saveCompleters.add(completer);
    return completer.future;
  }
}
// ignore_for_file: unused_import, unnecessary_import
