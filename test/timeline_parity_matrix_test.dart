import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'keeps timeline phases in Codex order and exposes elapsed details',
    (tester) async {
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..replaceTimelineEntriesForTesting([
          TimelineEntry(
            kind: TimelineKind.user,
            title: '你',
            detail: '请完成任务',
            createdAt: DateTime(2026),
          ),
          TimelineEntry(
            kind: TimelineKind.system,
            title: '任务已创建',
            detail: 'Thread timeline-thread',
            createdAt: DateTime(2026, 1, 1, 0, 0, 1),
          ),
          TimelineEntry(
            kind: TimelineKind.agent,
            title: 'Codex',
            detail: '我先检查项目。',
            agentPhase: 'commentary',
            createdAt: DateTime(2026, 1, 1, 0, 0, 2),
          ),
          TimelineEntry(
            kind: TimelineKind.command,
            title: '执行命令',
            detail: 'flutter analyze\nNo issues found',
            createdAt: DateTime(2026, 1, 1, 0, 0, 3),
          ),
          TimelineEntry(
            kind: TimelineKind.agent,
            title: 'Codex',
            detail: '任务已经完成。',
            agentPhase: 'final_answer',
            createdAt: DateTime(2026, 1, 1, 0, 0, 4),
          ),
          TimelineEntry(
            kind: TimelineKind.elapsed,
            title: '耗时 4 秒',
            detail: '',
            createdAt: DateTime(2026, 1, 1, 0, 0, 5),
          ),
          TimelineEntry(
            kind: TimelineKind.system,
            title: '任务完成',
            detail: '',
            createdAt: DateTime(2026, 1, 1, 0, 0, 6),
          ),
        ]);
      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );

      expect(find.text('任务已创建'), findsOneWidget);
      expect(find.text('我先检查项目。'), findsOneWidget);
      expect(find.text('已运行了命令'), findsOneWidget);
      expect(find.text('任务已经完成。'), findsOneWidget);
      expect(find.text('耗时 4 秒'), findsOneWidget);
      expect(find.text('任务完成'), findsOneWidget);

      expect(
        tester.getTopLeft(find.text('任务已创建')).dy,
        lessThan(tester.getTopLeft(find.text('我先检查项目。')).dy),
      );
      expect(
        tester.getTopLeft(find.text('我先检查项目。')).dy,
        lessThan(tester.getTopLeft(find.text('已运行了命令')).dy),
      );
      expect(
        tester.getTopLeft(find.text('已运行了命令')).dy,
        lessThan(tester.getTopLeft(find.text('任务已经完成。')).dy),
      );
      expect(
        tester.getTopLeft(find.text('任务已经完成。')).dy,
        lessThan(tester.getTopLeft(find.text('任务完成')).dy),
      );
      expect(
        find.byKey(const Key('completed-turn-disclosure-content')),
        findsOneWidget,
      );
    },
  );

  testWidgets('keeps approval as a floating layer above the composer', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/permissions/requestApproval',
        requestId: 77,
        params: {
          'threadId': 'approval-thread',
          'reason': '是否允许执行测试命令？',
          'command': 'flutter test',
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final approval = find.byKey(const Key('approval-panel'));
    final composer = find.byKey(const Key('composer-panel'));
    expect(approval, findsOneWidget);
    expect(find.text('权限请求'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(
      tester.getRect(approval).bottom,
      lessThanOrEqualTo(tester.getRect(composer).top),
    );
    expect(find.byKey(const Key('approval-allow-once')), findsOneWidget);
    expect(find.byKey(const Key('approval-decline')), findsOneWidget);
  });
}
