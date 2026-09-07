import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows MCP elicitation for a background task and submits its form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final writes = <JsonMap>[];
      final controller =
          CodexController(server: CodexAppServer(messageSink: writes.add))
            ..status = RuntimeStatus.ready
            ..activeThreadId = 'foreground'
            ..threads = [
              thread(id: 'foreground'),
              const CodexThread(
                id: 'background',
                name: '后台 MCP 任务',
                preview: 'preview-background',
                createdAt: 1,
                updatedAt: 2,
              ),
            ];
      controller.handleServerEventForTesting(
        const ServerEvent(
          method: 'mcpServer/elicitation/request',
          requestId: 'background-form',
          params: {
            'threadId': 'background',
            'serverName': 'openai-developers',
            'mode': 'form',
            'message': '选择保存位置。',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'targetPath': {'type': 'string', 'default': '.env.local'},
              },
              'required': ['targetPath'],
            },
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      final panelFinder = find.byKey(const Key('mcp-elicitation-panel'));
      expect(panelFinder, findsOneWidget);
      final panel = tester.widget<Container>(panelFinder);
      final decoration = panel.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(14));
      expect(panel.constraints?.maxWidth, 600);
      expect(find.text('MCP 输入'), findsOneWidget);
      expect(find.text('拒绝  Esc'), findsOneWidget);
      expect(find.text('来自后台任务：后台 MCP 任务'), findsOneWidget);
      expect(
        tester.getRect(panelFinder).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('composer-panel'))).top,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mcp-elicitation-field-targetPath')),
        '.env.test',
      );
      await tester.drag(
        find.byKey(const Key('mcp-elicitation-scroll')),
        const Offset(0, -160),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('mcp-elicitation-accept')));
      await tester.pump();

      expect(writes.single['result'], {
        'action': 'accept',
        'content': {'targetPath': '.env.test'},
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('bounds a large MCP form and preserves prompt arrival order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
    )..status = RuntimeStatus.ready;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/permissions/requestApproval',
        requestId: 'queued-approval',
        params: {'reason': '允许访问额外目录吗？'},
      ),
    );
    controller.handleServerEventForTesting(
      ServerEvent(
        method: 'mcpServer/elicitation/request',
        requestId: 'large-form',
        params: {
          'mode': 'form',
          'message': '填写连接配置。',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              for (var index = 0; index < 12; index++)
                'field$index': {'type': 'string'},
            },
          },
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    expect(find.byKey(const Key('approval-panel')), findsOneWidget);
    expect(find.byKey(const Key('mcp-elicitation-panel')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('approval-decline')));
    await tester.pump();
    final elicitation = find.byKey(const Key('mcp-elicitation-panel'));
    expect(elicitation, findsOneWidget);
    expect(find.byKey(const Key('approval-panel')), findsNothing);
    expect(tester.getSize(elicitation).height, lessThanOrEqualTo(177));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prefers an active-task prompt over an earlier background form', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..activeThreadId = 'active-thread'
      ..status = RuntimeStatus.ready;
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'mcpServer/elicitation/request',
        requestId: 'background-form',
        params: {
          'threadId': 'background-thread',
          'mode': 'form',
          'message': '后台表单',
          'requestedSchema': {
            'type': 'object',
            'properties': <String, Object>{},
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/permissions/requestApproval',
        requestId: 'active-approval',
        params: {'threadId': 'active-thread', 'reason': '当前任务审批'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );

    expect(find.byKey(const Key('approval-panel')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('approval-panel')),
        matching: find.text('当前任务审批'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('mcp-elicitation-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

CodexThread thread({required String id}) =>
    CodexThread(id: id, preview: 'preview-$id', createdAt: 1, updatedAt: 2);
