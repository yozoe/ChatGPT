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

class BlockingCodexPluginStore extends MemoryCodexPluginStore {
  final installCompleter = Completer<void>();
  final enabledCompleter = Completer<void>();

  /// 保持安装操作未完成，供界面断言进行中状态。
  /// Keeps installation pending so the interface can assert its progress state.
  @override
  Future<void> installPlugin(CodexPlugin plugin) async {
    await installCompleter.future;
    await super.installPlugin(plugin);
  }

  @override
  Future<void> setPluginEnabled(CodexPlugin plugin, bool enabled) async {
    await enabledCompleter.future;
    await super.setPluginEnabled(plugin, enabled);
  }
}
// ignore_for_file: unused_import, unnecessary_import
