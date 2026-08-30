import 'package:chatgpt/src/services/task_completion_notifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forwards completion feedback to the desktop host', () async {
    const channel = MethodChannel('codex_desk/task_completion');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final notifier = TaskCompletionNotifier(channel: channel);
    await notifier.notifyTaskCompleted();
    await notifier.setDockBadge(visible: true);
    await notifier.setDockBadge(visible: false);

    expect(calls.map((call) => call.method), <String>[
      'notifyTaskCompleted',
      'setDockBadge',
      'setDockBadge',
    ]);
    expect(calls[1].arguments, <String, bool>{'visible': true});
    expect(calls[2].arguments, <String, bool>{'visible': false});
  });
}
