// Extracted class from code_review_panel.dart.
import 'package:chatgpt/src/domain/git_project_status.dart';

class ReviewFile {
  const ReviewFile({
    required this.path,
    required this.kind,
    required this.diff,
    this.truncated = false,
    this.error,
    this.gitChange,
  });

  final String path;
  final String kind;
  final String diff;
  final bool truncated;
  final String? error;
  final GitProjectChange? gitChange;

  @override
  bool operator ==(Object other) =>
      other is ReviewFile &&
      path == other.path &&
      kind == other.kind &&
      diff == other.diff &&
      truncated == other.truncated &&
      error == other.error;

  @override
  int get hashCode => Object.hash(path, kind, diff, truncated, error);
}
