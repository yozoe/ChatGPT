import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_timeline_activity_list.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('groups consecutive command and tool history', (tester) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'flutter analyze\nNo issues found',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.tool,
        title: '网页搜索',
        detail: 'Codex activity lists · 1 条结果',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('已运行了命令并进行了搜索'), findsOneWidget);
    expect(find.text('已运行 flutter analyze'), findsNothing);
    expect(find.text('网页搜索'), findsNothing);
    final activityList = find.byType(TimelineActivityList);
    expect(activityList, findsOneWidget);
    final summaryText = tester.widget<Text>(find.text('已运行了命令并进行了搜索'));
    expect(
      summaryText.style?.color,
      YeknomPalette.of(tester.element(find.text('已运行了命令并进行了搜索'))).muted,
    );
    final disclosureArrow = find.descendant(
      of: activityList,
      matching: find.byType(AnimatedRotation),
    );
    expect(disclosureArrow, findsOneWidget);
    expect(tester.widget<AnimatedRotation>(disclosureArrow).turns, 0);
    final disclosureArea = find.descendant(
      of: activityList,
      matching: find.byType(AnimatedSize),
    );
    expect(disclosureArea, findsOneWidget);
    expect(
      tester.widget<AnimatedSize>(disclosureArea).duration,
      const Duration(milliseconds: 180),
    );
    expect(
      tester.widget<AnimatedSize>(disclosureArea).alignment,
      Alignment.topLeft,
    );
    expect(
      tester
          .widget<SizedBox>(
            find.byKey(const Key('timeline-activity-disclosure-area')),
          )
          .width,
      double.infinity,
    );

    await tester.tap(find.text('已运行了命令并进行了搜索'));
    await tester.pump();

    expect(tester.widget<AnimatedRotation>(disclosureArrow).turns, 0.25);
    expect(find.text('已运行 flutter analyze'), findsOneWidget);
    expect(find.text('网页搜索'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('merges auto-approved commands into one activity list', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'first command',
        createdAt: DateTime(2026),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '已自动批准本次操作',
        detail: '命令执行请求',
        createdAt: DateTime(2026, 1, 1, 0, 0, 1),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'second command',
        createdAt: DateTime(2026, 1, 1, 0, 0, 2),
      ),
      TimelineEntry(
        kind: TimelineKind.system,
        title: '已自动批准本次操作',
        detail: '命令执行请求',
        createdAt: DateTime(2026, 1, 1, 0, 0, 3),
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'third command',
        createdAt: DateTime(2026, 1, 1, 0, 0, 4),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.text('已运行了命令'), findsOneWidget);
    expect(find.text('已自动批准本次操作'), findsNothing);

    await tester.tap(find.text('已运行了命令'));
    await tester.pump();

    expect(find.text('已运行 first command'), findsOneWidget);
    expect(find.text('已运行 second command'), findsOneWidget);
    expect(find.text('已运行 third command'), findsOneWidget);
    expect(find.text('已自动批准本次操作'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keeps separate groups with matching timestamps', (tester) async {
    final timestamp = DateTime(2026);
    final controller = CodexController(server: CodexAppServer());
    controller.replaceTimelineEntriesForTesting([
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'first command',
        createdAt: timestamp,
      ),
      TimelineEntry(
        kind: TimelineKind.user,
        title: '你',
        detail: 'separates activity groups',
        createdAt: timestamp,
      ),
      TimelineEntry(
        kind: TimelineKind.command,
        title: '执行命令',
        detail: 'second command',
        createdAt: timestamp,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final summaries = find.text('已运行了命令');
    expect(summaries, findsNWidgets(2));
    await tester.tap(summaries.first);
    await tester.pump();

    expect(find.text('已运行 first command'), findsOneWidget);
    expect(find.text('已运行 second command'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
