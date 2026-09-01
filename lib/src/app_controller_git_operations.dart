import 'dart:async';
import 'dart:math' as math;

import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/services/git_project_service.dart';

/// Encapsulates Git workspace operations used by [CodexController].
///
/// The callbacks deliberately keep ownership of controller state in the
/// controller while moving the asynchronous Git workflow out of the main
/// coordinator. This preserves request cancellation and notification timing.
class CodexGitOperations {
  CodexGitOperations({
    required GitProjectService service,
    required String? Function() workspace,
    required bool Function() isDisposed,
    required void Function() notify,
    required String Function(Object error) messageOf,
    required int Function() nextProjectRequest,
    required int Function() nextDiffRequest,
    required int Function() nextReviewRequest,
    required bool Function(int request, String workspace) isCurrentProject,
    required bool Function(
      int request,
      String workspace,
      GitProjectChange change,
    )
    isCurrentDiff,
    required bool Function(int request, String workspace) isCurrentReview,
    required void Function(bool value) setProjectLoading,
    required void Function(GitProjectStatus? value) setProjectStatus,
    required void Function(String? value) setProjectError,
    required void Function(GitProjectChange? value) setDiffChange,
    required void Function(String? value) setDiff,
    required void Function(bool value) setDiffLoading,
    required void Function(bool value) setDiffTruncated,
    required void Function(Map<String, GitDiffPreview> value) setReviewDiffs,
    required void Function(Map<String, String> value) setReviewDiffErrors,
    required void Function(bool value) setReviewLoading,
    required bool Function() isOperationRunning,
    required void Function(bool value) setOperationRunning,
    required void Function(String? value) setOperationError,
  }) : _service = service,
       _workspace = workspace,
       _isDisposed = isDisposed,
       _notify = notify,
       _messageOf = messageOf,
       _nextProjectRequest = nextProjectRequest,
       _nextDiffRequest = nextDiffRequest,
       _nextReviewRequest = nextReviewRequest,
       _isCurrentProject = isCurrentProject,
       _isCurrentDiff = isCurrentDiff,
       _isCurrentReview = isCurrentReview,
       _setProjectLoading = setProjectLoading,
       _setProjectStatus = setProjectStatus,
       _setProjectError = setProjectError,
       _setDiffChange = setDiffChange,
       _setDiff = setDiff,
       _setDiffLoading = setDiffLoading,
       _setDiffTruncated = setDiffTruncated,
       _setReviewDiffs = setReviewDiffs,
       _setReviewDiffErrors = setReviewDiffErrors,
       _setReviewLoading = setReviewLoading,
       _isOperationRunning = isOperationRunning,
       _setOperationRunning = setOperationRunning,
       _setOperationError = setOperationError;

  static const maximumConcurrentReviewDiffs = 6;

  final GitProjectService _service;
  final String? Function() _workspace;
  final bool Function() _isDisposed;
  final void Function() _notify;
  final String Function(Object error) _messageOf;
  final int Function() _nextProjectRequest;
  final int Function() _nextDiffRequest;
  final int Function() _nextReviewRequest;
  final bool Function(int request, String workspace) _isCurrentProject;
  final bool Function(int request, String workspace, GitProjectChange change)
  _isCurrentDiff;
  final bool Function(int request, String workspace) _isCurrentReview;
  final void Function(bool value) _setProjectLoading;
  final void Function(GitProjectStatus? value) _setProjectStatus;
  final void Function(String? value) _setProjectError;
  final void Function(GitProjectChange? value) _setDiffChange;
  final void Function(String? value) _setDiff;
  final void Function(bool value) _setDiffLoading;
  final void Function(bool value) _setDiffTruncated;
  final void Function(Map<String, GitDiffPreview> value) _setReviewDiffs;
  final void Function(Map<String, String> value) _setReviewDiffErrors;
  final void Function(bool value) _setReviewLoading;
  final bool Function() _isOperationRunning;
  final void Function(bool value) _setOperationRunning;
  final void Function(String? value) _setOperationError;

  Future<void> refreshProject() async {
    final path = _workspace();
    if (path == null) return;
    final request = _nextProjectRequest();
    _setProjectLoading(true);
    _setProjectError(null);
    if (!_isDisposed()) _notify();
    try {
      final next = await _service.inspect(path);
      if (!_isCurrentProject(request, path)) return;
      _setProjectStatus(next);
      _setProjectError(next.error);
    } catch (error) {
      if (!_isCurrentProject(request, path)) return;
      _setProjectError(_messageOf(error));
    } finally {
      if (_isCurrentProject(request, path)) {
        _setProjectLoading(false);
        _notify();
      }
    }
  }

  Future<void> showDiff(GitProjectChange change) async {
    final path = _workspace();
    if (path == null) return;
    final request = _nextDiffRequest();
    _setDiffLoading(true);
    _setDiffChange(change);
    _setDiff(null);
    _setDiffTruncated(false);
    if (!_isDisposed()) _notify();
    try {
      final next = await _service.readDiffPreview(
        workspace: path,
        change: change,
      );
      if (!_isCurrentDiff(request, path, change)) return;
      _setDiff(next.content);
      _setDiffTruncated(next.truncated);
    } catch (error) {
      if (!_isCurrentDiff(request, path, change)) return;
      _setDiff('无法读取 Git Diff：${_messageOf(error)}');
      _setDiffTruncated(false);
    } finally {
      if (_isCurrentDiff(request, path, change)) {
        _setDiffLoading(false);
        _notify();
      }
    }
  }

  Future<void> refreshReview() async {
    final path = _workspace();
    if (path == null) return;
    final request = _nextReviewRequest();
    _setReviewLoading(true);
    _setReviewDiffErrors(const {});
    if (!_isDisposed()) _notify();
    try {
      final status = await _service.inspect(path);
      if (!_isCurrentReview(request, path)) return;
      _setProjectStatus(status);
      _setProjectError(status.error);
      final results =
          <({String path, GitDiffPreview? preview, String? error})>[];
      for (
        var offset = 0;
        offset < status.changes.length;
        offset += maximumConcurrentReviewDiffs
      ) {
        final end = math.min(
          offset + maximumConcurrentReviewDiffs,
          status.changes.length,
        );
        final batch = await Future.wait(
          status.changes.sublist(offset, end).map((change) async {
            try {
              final preview = await _service.readDiffPreview(
                workspace: path,
                change: change,
              );
              return (
                path: change.path,
                preview: preview,
                error: null as String?,
              );
            } catch (error) {
              return (
                path: change.path,
                preview: null as GitDiffPreview?,
                error: _messageOf(error),
              );
            }
          }),
        );
        results.addAll(batch);
        if (!_isCurrentReview(request, path)) return;
      }
      _setReviewDiffs({
        for (final result in results) result.path: ?result.preview,
      });
      _setReviewDiffErrors({
        for (final result in results) result.path: ?result.error,
      });
    } catch (error) {
      if (!_isCurrentReview(request, path)) return;
      _setProjectError(_messageOf(error));
      _setReviewDiffs(const {});
    } finally {
      if (_isCurrentReview(request, path)) {
        _setReviewLoading(false);
        _notify();
      }
    }
  }

  Future<List<String>> listBaseBranches() async {
    final path = _workspace();
    if (path == null) return const [];
    return _service.listReviewBaseBranches(path);
  }

  Future<bool> run(Future<void> Function() operation) async {
    if (_workspace() == null || _isOperationRunning()) return false;
    _setOperationRunning(true);
    _setOperationError(null);
    if (!_isDisposed()) _notify();
    try {
      await operation();
      await refreshProject();
      return true;
    } catch (error) {
      _setOperationError(_messageOf(error));
      return false;
    } finally {
      _setOperationRunning(false);
      if (!_isDisposed()) _notify();
    }
  }
}
