import 'package:chatgpt/src/presentation/files/workspace_code_syntax_highlighter.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

String textUsingColor(TextSpan root, Color color) => root.children!
    .whereType<TextSpan>()
    .where((span) => span.style?.color == color)
    .map((span) => span.text ?? '')
    .join();

void main() {
  test('highlights shell syntax categories without changing source text', () {
    final highlighter = WorkspaceCodeSyntaxHighlighter(dark: true);
    const source = 'set -e\ncount=42\nprint "hello" \$count # note';

    final result = highlighter.highlight(content: source, path: 'build.zsh');
    final rendered = result.children!
        .whereType<TextSpan>()
        .map((span) => span.text ?? '')
        .join();

    expect(rendered, source);
    expect(textUsingColor(result, highlighter.keywordColor), contains('set'));
    expect(
      textUsingColor(result, highlighter.stringColor),
      contains('"hello"'),
    );
    expect(textUsingColor(result, highlighter.numberColor), contains('42'));
    expect(
      textUsingColor(result, highlighter.variableColor),
      contains(r'$count'),
    );
    expect(
      textUsingColor(result, highlighter.commentColor),
      contains('# note'),
    );
  });

  test('highlights Dart keywords, types, and line comments', () {
    final highlighter = WorkspaceCodeSyntaxHighlighter(dark: false);
    const source = 'final Widget child = value; // detail';

    final result = highlighter.highlight(content: source, path: 'view.dart');

    expect(textUsingColor(result, highlighter.keywordColor), contains('final'));
    expect(textUsingColor(result, highlighter.typeColor), contains('Widget'));
    expect(
      textUsingColor(result, highlighter.commentColor),
      contains('// detail'),
    );
  });
}
