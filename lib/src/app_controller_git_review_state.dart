import 'package:chatgpt/src/domain/git_project_status.dart';

/// 集中维护 Git 项目、Diff、审查和任务文件撤销的呈现状态。
/// Owns Git project, Diff, review, and task-file undo presentation state.
///
/// Git 服务请求和路径安全校验仍由控制器与 [CodexGitOperations] 负责；本
/// 类型只归组加载、错误、刷新代次和操作状态。
/// Git requests and path validation remain in the controller and
/// [CodexGitOperations]; this type only groups loading, error, request epochs,
/// and operation state.
class CodexGitReviewState {
  GitProjectStatus? gitProjectStatus;
  bool gitProjectLoading = false;
  String? gitProjectError;
  GitProjectChange? gitDiffChange;
  String? gitDiff;
  bool gitDiffLoading = false;
  bool gitDiffTruncated = false;
  Map<String, GitDiffPreview> gitReviewDiffs = const {};
  Map<String, String> gitReviewDiffErrors = const {};
  bool gitReviewLoading = false;
  bool gitOperationRunning = false;
  String? gitOperationError;
  bool fileChangeUndoRunning = false;
  String? fileChangeUndoError;

  int gitProjectRefreshRequest = 0;
  int gitDiffRefreshRequest = 0;
  int gitReviewRefreshRequest = 0;

  void clearProjectData() {
    gitProjectStatus = null;
    gitProjectError = null;
    gitDiffChange = null;
    gitDiff = null;
    gitDiffLoading = false;
    gitDiffTruncated = false;
    gitReviewDiffs = const {};
    gitReviewDiffErrors = const {};
    gitReviewLoading = false;
    gitOperationError = null;
    fileChangeUndoError = null;
    gitProjectRefreshRequest++;
    gitDiffRefreshRequest++;
    gitReviewRefreshRequest++;
  }

  void clear() {
    clearProjectData();
    gitProjectLoading = false;
    gitOperationRunning = false;
    fileChangeUndoRunning = false;
  }
}
