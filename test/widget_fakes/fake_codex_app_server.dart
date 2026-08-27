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

class FakeCodexAppServer extends CodexAppServer {
  FakeCodexAppServer() : super(executable: '/not/a/codex');

  final listRequests = <Completer<List<JsonMap>>>[];
  List<JsonMap> listResponse = <JsonMap>[];
  final Map<String, List<JsonMap>> listResponsesByDirectory = {};
  List<JsonMap> archivedListResponse = <JsonMap>[];
  List<JsonMap> modelListResponse = <JsonMap>[];
  Object? modelListError;
  JsonMap configReadResponse = {
    'config': <String, Object?>{},
    'origins': <String, Object?>{},
  };
  String? configReadDirectory;
  bool queueListRequests = false;
  Object? resumeError;
  JsonMap resumeResult = {
    'thread': {'turns': <JsonMap>[]},
  };
  JsonMap turnPage = {'data': <JsonMap>[]};
  Completer<JsonMap>? turnPageCompleter;
  final turnPageCursors = <String?>[];
  JsonMap itemPage = {'data': <JsonMap>[]};
  final itemPageTurnIds = <String>[];
  Object? itemPageError;
  List<JsonMap>? itemPages;
  var itemPageIndex = 0;
  String? resumedThreadId;
  int resumeCalls = 0;
  String? resumedModelProvider;
  String? resumedModel;
  JsonMap? resumedConfig;
  String? startedThreadDirectory;
  List<String>? startedRuntimeWorkspaceRoots;
  String? startedModelProvider;
  String? startedModel;
  JsonMap? startedConfig;
  List<JsonMap> skillListResponse = <JsonMap>[];
  String? startedTurnPrompt;
  String? startedTurnDirectory;
  final List<String> startedTurnPrompts = [];
  String? startedTurnThreadId;
  final List<String> startedTurnThreadIds = [];
  final List<String> startThreadResponseIds = [];
  List<JsonMap> startedTurnAdditionalInput = <JsonMap>[];
  JsonMap? startedTurnCollaborationMode;
  Object? startTurnError;
  Completer<void>? startTurnCompleter;
  String? steeredTurnThreadId;
  String? steeredTurnId;
  String? steeredTurnPrompt;
  List<JsonMap> steeredTurnAdditionalInput = <JsonMap>[];
  String? steerResponseTurnId;
  Object? steerTurnError;
  Completer<String>? steerCompleter;
  String? interruptedThreadId;
  String? interruptedTurnId;
  Completer<void>? interruptCompleter;
  Object? interruptTurnError;
  Object? unarchiveError;
  String? threadGoal;
  String? renamedThreadId;
  String? renamedThreadName;
  String? unarchivedThreadId;
  int unarchiveCalls = 0;
  Completer<void>? unarchiveCompleter;
  final archivedThreadIds = <String>[];
  int archiveCalls = 0;
  Completer<void>? archiveCompleter;
  Object? archiveError;
  final archiveErrorsById = <String, Object>{};
  final deletedThreadIds = <String>[];
  final archiveFailureIds = <String>{};

  /// 始终报告运行中，模拟已连接的 App Server。
  /// Always reports running, simulating a connected App Server.
  @override
  bool get isRunning => true;

  /// 返回预设线程列表，或排队请求以控制刷新竞争测试。
  /// Returns preset threads or queues requests to control refresh-race tests.
  @override
  Future<List<JsonMap>> listThreads({
    required String workingDirectory,
    bool archived = false,
  }) {
    if (archived) return Future.value(archivedListResponse);
    final directoryResponse = listResponsesByDirectory[workingDirectory];
    if (directoryResponse != null) return Future.value(directoryResponse);
    if (!queueListRequests) return Future.value(listResponse);
    final completer = Completer<List<JsonMap>>();
    listRequests.add(completer);
    return completer.future;
  }

  /// 返回预设模型能力列表。
  /// Returns the preset model-capability list.
  @override
  Future<List<JsonMap>> listModels({bool includeHidden = false}) async {
    if (modelListError case final error?) throw error;
    return modelListResponse;
  }

  /// 返回 App Server 已按层级合并的配置，并记录用于解析项目配置的目录。
  /// Returns App Server's merged configuration and records the workspace used to resolve project layers.
  @override
  Future<JsonMap> readConfig({String? workingDirectory}) async {
    configReadDirectory = workingDirectory;
    return configReadResponse;
  }

  /// 记录恢复参数，并返回预设结果或抛出预设异常。
  /// Records resume parameters and returns a preset result or error.
  @override
  Future<JsonMap> resumeThread({
    required String threadId,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    resumeCalls++;
    resumedThreadId = threadId;
    resumedModelProvider = modelProvider;
    resumedModel = model;
    resumedConfig = config;
    final error = resumeError;
    if (error != null) throw error;
    return resumeResult;
  }

  /// 记录新线程参数并返回稳定的测试线程 ID。
  /// Records new-thread parameters and returns a stable test thread ID.
  @override
  Future<String> startThread({
    required String workingDirectory,
    List<String>? runtimeWorkspaceRoots,
    String? modelProvider,
    String? model,
    JsonMap? config,
  }) async {
    startedThreadDirectory = workingDirectory;
    startedRuntimeWorkspaceRoots = runtimeWorkspaceRoots;
    startedModelProvider = modelProvider;
    startedModel = model;
    startedConfig = config;
    return startThreadResponseIds.isEmpty
        ? 'new-thread'
        : startThreadResponseIds.removeAt(0);
  }

  /// 接受模拟任务启动，不与真实运行时通信。
  /// Accepts a simulated turn start without communicating with a runtime.
  @override
  Future<void> startTurn({
    required String threadId,
    required String prompt,
    required String workingDirectory,
    List<JsonMap> additionalInput = const [],
    JsonMap? collaborationMode,
  }) async {
    startedTurnDirectory = workingDirectory;
    startedTurnThreadId = threadId;
    startedTurnThreadIds.add(threadId);
    startedTurnPrompt = prompt;
    startedTurnPrompts.add(prompt);
    startedTurnAdditionalInput = List.of(additionalInput);
    startedTurnCollaborationMode = collaborationMode;
    if (startTurnCompleter case final completer?) await completer.future;
    if (startTurnError case final error?) throw error;
  }

  @override
  Future<String> steerTurn({
    required String threadId,
    required String expectedTurnId,
    required String prompt,
    List<JsonMap> additionalInput = const [],
  }) async {
    steeredTurnThreadId = threadId;
    steeredTurnId = expectedTurnId;
    steeredTurnPrompt = prompt;
    steeredTurnAdditionalInput = List.of(additionalInput);
    if (steerTurnError case final error?) throw error;
    if (steerCompleter case final completer?) return completer.future;
    return steerResponseTurnId ?? expectedTurnId;
  }

  @override
  Future<void> interruptTurn({
    required String threadId,
    required String turnId,
  }) async {
    interruptedThreadId = threadId;
    interruptedTurnId = turnId;
    await interruptCompleter?.future;
    if (interruptTurnError case final error?) throw error;
  }

  @override
  Future<void> setThreadGoal({
    required String threadId,
    required String objective,
  }) async {
    threadGoal = objective;
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    renamedThreadId = threadId;
    renamedThreadName = name;
  }

  @override
  Future<List<JsonMap>> listSkills({
    required String workingDirectory,
    bool forceReload = false,
  }) async => List.of(skillListResponse);

  /// 返回预设 turn 页面并记录使用的游标。
  /// Returns a preset turn page and records the cursor used.
  @override
  Future<JsonMap> listThreadTurns({
    required String threadId,
    String? cursor,
    int limit = 50,
    String sortDirection = 'desc',
  }) async {
    turnPageCursors.add(cursor);
    if (turnPageCompleter case final completer?) return completer.future;
    return turnPage;
  }

  /// 返回预设项目页面、记录 turn，并可模拟读取失败。
  /// Returns preset item pages, records the turn, and can simulate a read failure.
  @override
  Future<JsonMap> listThreadItems({
    required String threadId,
    required String turnId,
    String? cursor,
    int limit = 50,
  }) async {
    itemPageTurnIds.add(turnId);
    final error = itemPageError;
    if (error != null) throw error;
    final pages = itemPages;
    if (pages != null && itemPageIndex < pages.length) {
      return pages[itemPageIndex++];
    }
    return itemPage;
  }

  /// 记录恢复归档请求，并可延迟完成以测试重复提交防护。
  /// Records an unarchive request and can delay completion for duplicate-submit tests.
  @override
  Future<void> unarchiveThread({required String threadId}) async {
    unarchivedThreadId = threadId;
    unarchiveCalls++;
    await unarchiveCompleter?.future;
    if (unarchiveError case final error?) throw error;
    archivedListResponse = <JsonMap>[];
  }

  /// 记录归档请求，并从活跃测试列表中移除相应任务。
  /// Records archive requests and removes corresponding tasks from the active test list.
  @override
  Future<void> archiveThread({required String threadId}) async {
    archiveCalls++;
    await archiveCompleter?.future;
    if (archiveError case final error?) throw error;
    if (archiveErrorsById[threadId] case final error?) throw error;
    if (archiveFailureIds.contains(threadId)) {
      throw StateError('无法归档 $threadId');
    }
    archivedThreadIds.add(threadId);
    listResponse = listResponse
        .where((value) => value['id']?.toString() != threadId)
        .toList(growable: false);
  }

  /// 记录永久删除请求，并从活跃和归档测试列表中移除相应任务。
  /// Records permanent deletion requests and removes matching tasks from both test lists.
  @override
  Future<void> deleteThread({required String threadId}) async {
    deletedThreadIds.add(threadId);
    listResponse = listResponse
        .where((value) => value['id']?.toString() != threadId)
        .toList(growable: false);
    archivedListResponse = archivedListResponse
        .where((value) => value['id']?.toString() != threadId)
        .toList(growable: false);
  }
}
// ignore_for_file: unused_import, unnecessary_import
