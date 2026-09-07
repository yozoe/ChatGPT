// Extracted class from code_review_panel.dart.
import 'package:chatgpt/src/presentation/code_review/code_review_panel_support.dart';

class ReviewRow {
  const ReviewRow(this.kind, this.text, {this.oldLine, this.newLine});

  final ReviewRowKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
}
