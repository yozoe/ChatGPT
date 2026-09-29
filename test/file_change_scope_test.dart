import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_file_change_summary_card.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('labels cumulative files but counts only the current turn', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: YeknomWorkbenchTheme.dark(),
        home: Scaffold(
          body: FileChangeSummaryCard(
            changes: const [
              CodexFileChange(
                path: 'lib/first.dart',
                kind: 'modified',
                diff: '@@ -1 +1 @@\n-old first\n+new first',
              ),
              CodexFileChange(
                path: 'lib/second.dart',
                kind: 'modified',
                diff: '@@ -1 +1,2 @@\n-old second\n+new second\n+extra',
              ),
            ],
            statsChanges: const [
              CodexFileChange(
                path: 'lib/second.dart',
                kind: 'modified',
                diff: '@@ -1 +1,2 @@\n-old second\n+new second\n+extra',
              ),
            ],
            turnDiff: null,
            expanded: false,
            onExpandedChanged: (_) {},
            onReview: () async {},
            onUndo: () async {},
            canUndo: false,
            undoRunning: false,
          ),
        ),
      ),
    );

    expect(find.text('已编辑 2 个文件'), findsOneWidget);
    expect(find.textContaining('本回合'), findsOneWidget);
    final stats = tester.widget<Text>(
      find.byKey(const Key('file-change-summary-stats')),
    );
    expect(stats.textSpan?.toPlainText(), contains('+2'));
    expect(stats.textSpan?.toPlainText(), contains('-1'));
    expect(stats.textSpan?.toPlainText(), isNot(contains('+3')));
    expect(stats.textSpan?.toPlainText(), isNot(contains('-2')));
  });
}
