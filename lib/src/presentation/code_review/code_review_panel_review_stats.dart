// Extracted class from code_review_panel.dart.

class ReviewStats {
  const ReviewStats({this.additions = 0, this.deletions = 0});

  final int additions;
  final int deletions;

  ReviewStats operator +(ReviewStats other) => ReviewStats(
    additions: additions + other.additions,
    deletions: deletions + other.deletions,
  );
}
