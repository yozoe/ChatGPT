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
import 'memory_codex_plugin_store.dart';

class FailOnSecondInstallCodexPluginStore extends MemoryCodexPluginStore {
  var installCalls = 0;

  /// 首次安装成功，第二次失败，用于验证待重启提示不会丢失。
  /// Succeeds once, then fails to verify pending restart feedback persists.
  @override
  Future<void> installPlugin(CodexPlugin plugin) async {
    installCalls++;
    if (installCalls == 2) throw StateError('second install failed');
    await super.installPlugin(plugin);
  }
}
// ignore_for_file: unused_import, unnecessary_import
