// Extracted class from code_review_panel.dart.
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_file.dart';

class ReviewDirectory {
  ReviewDirectory(this.name, this.fullPath);

  final String name;
  final String fullPath;
  final Map<String, ReviewDirectory> children = {};
  final List<ReviewFile> files = [];
}
