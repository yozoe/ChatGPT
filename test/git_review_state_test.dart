import 'package:chatgpt/src/app_controller_git_review_state.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clears project review data and advances request epochs', () {
    final state = CodexGitReviewState()
      ..gitDiff = '@@ -1 +1 @@'
      ..gitDiffLoading = true
      ..gitDiffTruncated = true
      ..gitReviewDiffs = {
        'lib/main.dart': const GitDiffPreview(
          content: '+changed',
          truncated: false,
        ),
      }
      ..gitReviewDiffErrors = {'lib/other.dart': 'failed'}
      ..gitReviewLoading = true
      ..gitOperationError = 'operation failed'
      ..fileChangeUndoError = 'undo failed';
    state.gitProjectRefreshRequest = 2;
    state.gitDiffRefreshRequest = 3;
    state.gitReviewRefreshRequest = 4;

    state.clearProjectData();

    expect(state.gitDiff, isNull);
    expect(state.gitDiffLoading, isFalse);
    expect(state.gitDiffTruncated, isFalse);
    expect(state.gitReviewDiffs, isEmpty);
    expect(state.gitReviewDiffErrors, isEmpty);
    expect(state.gitReviewLoading, isFalse);
    expect(state.gitOperationError, isNull);
    expect(state.fileChangeUndoError, isNull);
    expect(state.gitProjectRefreshRequest, 3);
    expect(state.gitDiffRefreshRequest, 4);
    expect(state.gitReviewRefreshRequest, 5);
  });

  test('clear resets loading and operation flags', () {
    final state = CodexGitReviewState()
      ..gitProjectLoading = true
      ..gitOperationRunning = true
      ..fileChangeUndoRunning = true;

    state.clear();

    expect(state.gitProjectLoading, isFalse);
    expect(state.gitOperationRunning, isFalse);
    expect(state.fileChangeUndoRunning, isFalse);
  });
}
