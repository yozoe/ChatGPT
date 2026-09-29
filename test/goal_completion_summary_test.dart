import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_goal_completion_summary.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a compact goal completion summary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: YeknomWorkbenchTheme.dark(),
        home: const Scaffold(
          body: GoalCompletionSummary(label: '已在 10m 4s 内达成目标'),
        ),
      ),
    );

    expect(
      find.byKey(const Key('goal-completion-summary-icon')),
      findsOneWidget,
    );
    expect(find.text('已在 10m 4s 内达成目标'), findsOneWidget);
  });
}
