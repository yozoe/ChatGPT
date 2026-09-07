// Extracted class from code_review_panel.dart.
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_file.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel_review_directory.dart';

class ReviewTreeRow {
  const ReviewTreeRow.directory(this.directory, this.depth) : file = null;
  const ReviewTreeRow.file(this.file, this.depth) : directory = null;

  final ReviewDirectory? directory;
  final ReviewFile? file;
  final int depth;
}
