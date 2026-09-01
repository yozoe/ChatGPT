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

class FakeRuntimeConfigurationStore extends RuntimeConfigurationStore {
  String? workspace;
  String? savedWorkspace;
  List<String> additionalWorkspaces = [];
  List<String>? savedAdditionalWorkspaces;
  List<WorkspaceConfiguration> workspaces = [];
  List<WorkspaceConfiguration>? savedWorkspaces;
  String? reasoningEffort;
  String? savedReasoningEffort;
  String? model;
  String? savedModel;
  String? approvalMode;
  String? savedApprovalMode;
  bool browserEnabled = true;
  bool? savedBrowserEnabled;
  bool clearedWorkspace = false;
  Set<String> pinnedWorkspaces = {};
  Set<String>? savedPinnedWorkspaces;
  List<ScheduledTask> scheduledTasks = [];
  List<ScheduledTask>? savedScheduledTasks;

  /// 模拟未保存自定义 CLI 路径。
  /// Simulates no saved custom CLI path.
  @override
  Future<String?> readExecutable() async => null;

  /// 返回测试预设的项目路径。
  /// Returns the test-configured workspace path.
  @override
  Future<String?> readWorkspace() async => workspace;

  /// 在内存中保存项目路径，便于断言持久化结果。
  /// Saves the workspace path in memory for persistence assertions.
  @override
  Future<void> saveWorkspace(String value) async {
    savedWorkspace = value;
    workspace = value;
  }

  /// 清空内存项目路径并标记清理操作。
  /// Clears the in-memory workspace path and records the clear operation.
  @override
  Future<void> clearWorkspace() async {
    clearedWorkspace = true;
    workspace = null;
  }

  /// 返回测试预设的附加工作区目录。
  /// Returns test-configured additional workspace directories.
  @override
  Future<List<String>> readAdditionalWorkspaces() async =>
      List.of(additionalWorkspaces);

  /// 在内存中保存附加工作区目录，便于断言持久化结果。
  /// Saves additional workspace directories in memory for persistence assertions.
  @override
  Future<void> saveAdditionalWorkspaces(List<String> workspaces) async {
    savedAdditionalWorkspaces = List.of(workspaces);
    additionalWorkspaces = List.of(workspaces);
  }

  /// 返回测试预设的可切换工作区列表。
  /// Returns the test-configured switchable workspace list.
  @override
  Future<List<WorkspaceConfiguration>> readWorkspaces() async => workspaces
      .map(
        (workspace) => WorkspaceConfiguration(
          id: workspace.id,
          primaryPath: workspace.primaryPath,
          additionalPaths: workspace.additionalPaths,
          name: workspace.name,
        ),
      )
      .toList(growable: false);

  /// 在内存中保存完整工作区列表，便于验证迁移和切换。
  /// Saves the complete workspace list in memory for migration and switching assertions.
  @override
  Future<void> saveWorkspaces(
    List<WorkspaceConfiguration> configurations,
  ) async {
    final snapshot = configurations
        .map(
          (workspace) => WorkspaceConfiguration(
            id: workspace.id,
            primaryPath: workspace.primaryPath,
            additionalPaths: workspace.additionalPaths,
            name: workspace.name,
          ),
        )
        .toList(growable: false);
    savedWorkspaces = snapshot;
    workspaces = snapshot;
  }

  @override
  Future<Set<String>> readPinnedWorkspaces() async => Set.of(pinnedWorkspaces);

  @override
  Future<void> savePinnedWorkspaces(Iterable<String> paths) async {
    savedPinnedWorkspaces = paths.toSet();
    pinnedWorkspaces = paths.toSet();
  }

  @override
  Future<List<ScheduledTask>> readScheduledTasks() async =>
      List.of(scheduledTasks);

  @override
  Future<void> saveScheduledTasks(Iterable<ScheduledTask> tasks) async {
    savedScheduledTasks = tasks.toList(growable: false);
    scheduledTasks = List.of(savedScheduledTasks!);
  }

  /// 返回测试预设的推理强度。
  /// Returns the test-configured reasoning effort.
  @override
  Future<String?> readReasoningEffort() async => reasoningEffort;

  /// 在内存中保存推理强度，便于断言更新结果。
  /// Saves reasoning effort in memory for update assertions.
  @override
  Future<void> saveReasoningEffort(String? value) async {
    savedReasoningEffort = value;
    reasoningEffort = value;
  }

  /// 返回测试预设的新任务模型；`null` 表示跟随 Codex 配置。
  /// Returns the test-configured model for new tasks; `null` means follow Codex configuration.
  @override
  Future<String?> readModel() async => model;

  /// 在内存中保存新任务模型，便于断言模型切换持久化。
  /// Saves the new-task model in memory so model-selection persistence can be asserted.
  @override
  Future<void> saveModel(String? value) async {
    savedModel = value;
    model = value;
  }

  /// 返回测试预设的审批模式；`null` 表示请求批准。
  /// Returns the test-configured approval mode; `null` means request approval.
  @override
  Future<String?> readApprovalMode() async => approvalMode;

  /// 在内存中保存审批模式，便于验证重启后的恢复行为。
  /// Saves approval mode in memory to verify restoration after restart.
  @override
  Future<void> saveApprovalMode(String? value) async {
    savedApprovalMode = value;
    approvalMode = value;
  }

  @override
  Future<bool> readBrowserEnabled() async => browserEnabled;

  @override
  Future<void> saveBrowserEnabled(bool enabled) async {
    browserEnabled = enabled;
    savedBrowserEnabled = enabled;
  }
}
// ignore_for_file: unused_import, unnecessary_import
