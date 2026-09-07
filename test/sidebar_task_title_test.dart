import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fades long sidebar task titles instead of showing an ellipsis', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const title = '这是一个很长很长很长很长很长的任务标题，用于验证侧栏渐隐效果';
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..threads = [
        const CodexThread(
          id: 'long-title-thread',
          preview: title,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(
      find.byKey(const ValueKey('sidebar-thread-title-fade-long-title-thread')),
      findsOneWidget,
    );
    final titleText = tester.widget<Text>(find.text(title));
    expect(titleText.overflow, TextOverflow.clip);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('anchors the sidebar title fade to the task row trailing edge', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..threads = [thread(id: 'short-title')];
    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    final taskTile = find.byKey(
      const ValueKey('sidebar-thread-tile-short-title'),
    );
    final fade = find.byKey(
      const ValueKey('sidebar-thread-title-fade-short-title'),
    );
    expect(
      tester.getRect(fade).right,
      closeTo(tester.getRect(taskTile).right - 8, 0.1),
    );
    await tester.pumpWidget(const SizedBox());
  });
}

CodexThread thread({required String id}) =>
    CodexThread(id: id, preview: 'preview-$id', createdAt: 1, updatedAt: 2);
