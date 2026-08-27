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

class BlockingExtensionListCodexPluginStore extends MemoryCodexPluginStore {
  final pluginRequests = <Completer<List<CodexPlugin>>>[];
  final marketplaceRequests = <Completer<List<CodexMarketplace>>>[];

  @override
  Future<List<CodexPlugin>> listPlugins() {
    final completer = Completer<List<CodexPlugin>>();
    pluginRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<CodexMarketplace>> listMarketplaces() {
    final completer = Completer<List<CodexMarketplace>>();
    marketplaceRequests.add(completer);
    return completer.future;
  }
}
// ignore_for_file: unused_import, unnecessary_import
