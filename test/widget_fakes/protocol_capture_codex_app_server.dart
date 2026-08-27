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

class ProtocolCaptureCodexAppServer extends CodexAppServer {
  String? requestedMethod;
  JsonMap? requestedParams;
  final notifications = <String>[];

  /// 捕获协议请求并返回稳定响应，不启动真实子进程。
  /// Captures a protocol request and returns a stable response without starting a child process.
  @override
  Future<JsonMap> request(String method, [JsonMap params = const {}]) async {
    requestedMethod = method;
    requestedParams = params;
    if (method == 'turn/steer') {
      return {
        'result': {'turnId': 'turn-1'},
      };
    }
    return {
      'result': {
        'thread': {'id': 'thread-with-roots'},
      },
    };
  }

  /// 捕获初始化完成通知，避免协议测试依赖真实子进程。
  /// Captures initialization notifications without requiring a real child process.
  @override
  void notify(String method, [JsonMap params = const {}]) {
    notifications.add(method);
  }
}
// ignore_for_file: unused_import, unnecessary_import
