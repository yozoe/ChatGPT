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
import 'fake_codex_app_server.dart';

class ManagedRuntimeFakeServer extends FakeCodexAppServer {
  bool running = false;
  int startCalls = 0;
  int stopCalls = 0;
  String? runtimeDirectory;

  @override
  bool get isRunning => running;

  /// 返回可用的模拟 CLI 探测结果。
  /// Returns an available fake CLI probe result.
  @override
  Future<CodexRuntimeProbe> probe() async => const CodexRuntimeProbe(
    isAvailable: true,
    executablePath: '/fake/codex',
    version: 'codex fake',
    discovery: '测试运行时',
  );

  /// 记录自动连接使用的主目录。
  /// Records the primary directory used for automatic connection.
  @override
  Future<void> start({required String workingDirectory}) async {
    startCalls++;
    runtimeDirectory = workingDirectory;
    running = true;
  }

  /// 接受模拟初始化握手。
  /// Accepts the fake initialization handshake.
  @override
  Future<void> initialize() async {}

  /// 返回无需登录的模拟账户状态。
  /// Returns a fake account state that does not require login.
  @override
  Future<JsonMap> readAccount() async => {
    'account': null,
    'requiresOpenaiAuth': false,
  };

  /// 记录自动断开操作。
  /// Records an automatic disconnect operation.
  @override
  Future<void> stop() async {
    stopCalls++;
    running = false;
  }
}
// ignore_for_file: unused_import, unnecessary_import
