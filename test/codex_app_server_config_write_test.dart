import 'dart:convert';
import 'dart:async';

import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'probes and writes config/batchWrite using the official shape',
    () async {
      late CodexAppServer server;
      final messages = <JsonMap>[];
      server = CodexAppServer(
        messageSink: (message) {
          messages.add(message);
          final id = message['id'];
          final method = message['method'];
          if (id == null || method != 'config/batchWrite') return;
          scheduleMicrotask(
            () => server.handleStdoutLineForTesting(
              jsonEncode({'id': id, 'result': <String, Object?>{}}),
            ),
          );
        },
      );

      expect(await server.supportsConfigBatchWrite(), isTrue);
      await server.writeConfigValue(
        keyPath: 'sandbox_mode',
        value: 'workspace-write',
      );

      expect(messages, hasLength(2));
      expect(messages.first['method'], 'config/batchWrite');
      expect(messages.first['params'], {
        'edits': const <JsonMap>[],
        'reloadUserConfig': false,
      });
      expect(messages.last['params'], {
        'edits': [
          {
            'op': 'set',
            'keyPath': 'sandbox_mode',
            'value': 'workspace-write',
            'mergeStrategy': 'replace',
          },
        ],
        'reloadUserConfig': true,
      });
      await server.dispose();
    },
  );

  test(
    'rejects empty config writes before sending a protocol request',
    () async {
      final messages = <JsonMap>[];
      final server = CodexAppServer(messageSink: messages.add);
      await expectLater(
        server.writeConfigBatch(edits: const []),
        throwsArgumentError,
      );
      expect(messages, isEmpty);
      await server.dispose();
    },
  );

  test('falls back when config/read does not support layer metadata', () async {
    late CodexAppServer server;
    final messages = <JsonMap>[];
    server = CodexAppServer(
      messageSink: (message) {
        messages.add(message);
        final id = message['id'];
        if (id == null || message['method'] != 'config/read') return;
        final includeLayers =
            (message['params'] as Map?)?['includeLayers'] == true;
        scheduleMicrotask(
          () => server.handleStdoutLineForTesting(
            jsonEncode(
              includeLayers
                  ? {
                      'id': id,
                      'error': {
                        'code': -32602,
                        'message': 'includeLayers is unsupported',
                      },
                    }
                  : {
                      'id': id,
                      'result': {
                        'config': {'sandbox_mode': null},
                        'origins': const {},
                      },
                    },
            ),
          ),
        );
      },
    );

    final result = await server.readConfig(workingDirectory: '/workspace');

    expect(result['config'], {'sandbox_mode': null});
    expect(messages, hasLength(2));
    expect((messages.first['params'] as Map)['includeLayers'], isTrue);
    expect((messages.last['params'] as Map)['includeLayers'], isFalse);
    await server.dispose();
  });
}
