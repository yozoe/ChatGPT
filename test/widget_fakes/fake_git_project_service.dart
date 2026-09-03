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

class FakeGitProjectService extends GitProjectService {
  GitProjectStatus status = const GitProjectStatus(isRepository: false);
  List<String> reviewBaseBranches = const [];
  List<String> localBranches = const [];
  Completer<void>? localBranchesCompleter;
  String? requestedLocalBranchesWorkspace;
  String? checkedOutBranch;
  String? checkedOutBranchWorkspace;
  String? createdBranch;
  String? createdBranchWorkspace;
  String diff = '';
  String? reversedDiff;
  List<String>? reversedExpectedPaths;
  GitProjectChange? requestedChange;
  final List<GitProjectChange> requestedChanges = [];
  int inspectCalls = 0;
  int reverseCalls = 0;
  int stageCalls = 0;
  Object? stageError;
  Completer<void>? stageCompleter;
  Completer<void>? diffCompleter;
  int activeDiffReads = 0;
  int maximumActiveDiffReads = 0;
  Object? reverseError;
  Completer<void>? reverseCompleter;

  /// 返回预设的只读 Git 项目状态，并记录调用次数。
  /// Returns the preset read-only Git project status and records the call count.
  @override
  Future<GitProjectStatus> inspect(String workspace) async {
    inspectCalls++;
    return status;
  }

  @override
  Future<List<String>> listReviewBaseBranches(String workspace) async =>
      List.of(reviewBaseBranches);

  @override
  Future<List<String>> listLocalBranches(String workspace) async {
    requestedLocalBranchesWorkspace = workspace;
    await localBranchesCompleter?.future;
    return List.of(localBranches);
  }

  @override
  Future<void> checkoutBranch({
    required String workspace,
    required String branch,
  }) async {
    checkedOutBranch = branch;
    checkedOutBranchWorkspace = workspace;
    status = GitProjectStatus(
      isRepository: true,
      branch: branch,
      changes: status.changes,
    );
  }

  @override
  Future<void> createAndCheckoutBranch({
    required String workspace,
    required String branch,
  }) async {
    createdBranch = branch;
    createdBranchWorkspace = workspace;
    status = GitProjectStatus(
      isRepository: true,
      branch: branch,
      changes: status.changes,
    );
  }

  /// 返回预设 Diff，并记录界面请求的文件变更。
  /// Returns the preset diff and records the change requested by the interface.
  @override
  Future<String> readDiff({
    required String workspace,
    required GitProjectChange change,
  }) async {
    requestedChange = change;
    requestedChanges.add(change);
    return diff;
  }

  @override
  Future<GitDiffPreview> readDiffPreview({
    required String workspace,
    required GitProjectChange change,
  }) async {
    requestedChange = change;
    requestedChanges.add(change);
    activeDiffReads++;
    maximumActiveDiffReads = math.max(maximumActiveDiffReads, activeDiffReads);
    try {
      await diffCompleter?.future;
      return GitDiffPreview(
        content: diff,
        truncated: diff.endsWith(GitProjectService.truncatedDiffMarker),
      );
    } finally {
      activeDiffReads--;
    }
  }

  @override
  Future<void> stageFile({
    required String workspace,
    required GitProjectChange change,
  }) async {
    stageCalls++;
    if (stageError case final error?) throw error;
    await stageCompleter?.future;
  }

  @override
  Future<void> reverseApplyDiff({
    required String workspace,
    required String diff,
    required Iterable<String> expectedPaths,
  }) async {
    reverseCalls++;
    reversedDiff = diff;
    reversedExpectedPaths = List.of(expectedPaths);
    if (reverseError case final error?) throw error;
    await reverseCompleter?.future;
  }
}
// ignore_for_file: unused_import, unnecessary_import
