import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/pending_elicitation.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('returns accepted structured input for an MCP elicitation', () async {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
    );

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'mcpServer/elicitation/request',
        requestId: 'elicitation-1',
        params: {
          'threadId': 'thread-1',
          'serverName': 'openai-developers',
          'mode': 'openai/form',
          'message': '请选择保存位置。',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'targetPath': {
                'type': 'string',
                'title': '保存位置',
                'default': '.env.local',
              },
            },
            'required': ['targetPath'],
          },
        },
      ),
    );

    expect(controller.pendingElicitation?.serverName, 'openai-developers');
    await controller.respondToElicitation(
      action: 'accept',
      content: {'targetPath': '.env.test'},
    );

    expect(writes, [
      {
        'id': 'elicitation-1',
        'result': {
          'action': 'accept',
          'content': {'targetPath': '.env.test'},
        },
      },
    ]);
    expect(controller.pendingElicitation, isNull);
    controller.dispose();
  });

  test('keeps MCP elicitation manual in auto approval mode', () async {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
    );
    await controller.setApprovalMode(ApprovalMode.autoApprove);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'mcpServer/elicitation/request',
        requestId: 'elicitation-url',
        params: {
          'mode': 'url',
          'message': '确认继续授权流程。',
          'url': 'https://example.com/authorize',
        },
      ),
    );

    expect(writes, isEmpty);
    expect(controller.pendingElicitation?.mode, ElicitationMode.url);
    await controller.respondToElicitation(action: 'cancel');
    expect(writes.single['result'], {'action': 'cancel', 'content': null});
    controller.dispose();
  });

  test('declines malformed MCP elicitation schemas safely', () {
    final writes = <JsonMap>[];
    final controller = CodexController(
      server: CodexAppServer(messageSink: writes.add),
    );

    const schemas = [
      {
        'type': 'array',
        'items': {'type': 'string'},
      },
      {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'enum': ['a', 'b'],
            'default': 'c',
          },
        },
      },
      {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'enum': ['a', 'a'],
          },
        },
      },
    ];
    for (var index = 0; index < schemas.length; index++) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'mcpServer/elicitation/request',
          requestId: 'invalid-elicitation-$index',
          params: {
            'mode': 'form',
            'message': '请输入信息。',
            'requestedSchema': schemas[index],
          },
        ),
      );
    }

    expect(controller.pendingElicitation, isNull);
    expect(writes, hasLength(schemas.length));
    for (var index = 0; index < schemas.length; index++) {
      expect(writes[index], {
        'id': 'invalid-elicitation-$index',
        'result': {'action': 'decline', 'content': null},
      });
    }
    controller.dispose();
  });
}
