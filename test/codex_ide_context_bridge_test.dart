import 'dart:async';
import 'dart:convert';
import 'package:chatgpt/src/app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses IDE files, selections, and open tabs', () {
    final context = CodexIdeContext.fromJson(const {
      'activeFile': {
        'fsPath': '/workspace/lib/main.dart',
        'activeSelectionContent': 'runApp(App());',
        'selectionRange': {
          'start': {'line': 4, 'character': 2},
          'end': {'line': 4, 'character': 16},
        },
      },
      'openTabs': [
        {'path': '/workspace/README.md'},
        {'path': ''},
        'invalid',
      ],
    });

    expect(context.isAvailable, isTrue);
    expect(context.activeFile?.path, '/workspace/lib/main.dart');
    expect(context.activeFile?.selectedText, 'runApp(App());');
    expect(context.activeFile?.selectionRange?['start'], {
      'line': 4,
      'character': 2,
    });
    expect(context.openTabs.map((file) => file.path), ['/workspace/README.md']);
  });

  test('keeps malformed and empty IDE snapshots disconnected', () {
    expect(CodexIdeContext.fromJson(null).isAvailable, isFalse);
    expect(
      CodexIdeContext.fromJson(const {
        'activeFile': {'path': '   '},
        'openTabs': ['invalid'],
      }).isAvailable,
      isFalse,
    );
  });

  test('receives host updates and encodes schema-compatible context', () async {
    const channel = MethodChannel('codex_desk/ide_context_test');
    final bridge = CodexIdeContextBridge(channel: channel);
    addTearDown(bridge.dispose);
    var notifications = 0;
    bridge.addListener(() => notifications++);

    await _sendHostUpdate(channel, const {
      'activeFile': {
        'path': '/workspace/lib/main.dart',
        'selectedText': 'final answer = 42;',
      },
      'openTabs': [
        {'path': '/workspace/test/main_test.dart'},
      ],
    });

    expect(bridge.isConnected, isTrue);
    expect(notifications, 1);
    final entry = bridge.additionalContext?['ide'] as Map;
    expect(entry['kind'], 'application');
    expect(entry['value'], isA<String>());
    expect(jsonDecode(entry['value'] as String), {
      'activeFile': {
        'path': '/workspace/lib/main.dart',
        'selectedText': 'final answer = 42;',
      },
      'openTabs': [
        {'path': '/workspace/test/main_test.dart'},
      ],
    });

    await _sendHostUpdate(channel, const {});
    expect(bridge.isConnected, isFalse);
    expect(bridge.additionalContext, isNull);
    expect(notifications, 2);
  });

  test('ignores host updates after disposal', () async {
    const channel = MethodChannel('codex_desk/ide_context_disposed_test');
    final bridge = CodexIdeContextBridge(channel: channel);
    bridge.dispose();

    await _sendHostUpdate(channel, const {
      'activeFile': {'path': '/workspace/late.dart'},
    });

    expect(bridge.isConnected, isFalse);
  });
}

Future<void> _sendHostUpdate(MethodChannel channel, Object arguments) async {
  final response = Completer<ByteData?>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('updateContext', arguments)),
        response.complete,
      );
  await response.future;
}
