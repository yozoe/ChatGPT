import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('updates visible account state from App Server notifications', () {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'account/updated',
        params: {'authMode': 'chatgpt', 'planType': 'plus'},
      ),
    );

    expect(controller.authStatus, AuthStatus.chatgpt);
    expect(controller.authLabel, 'ChatGPT plus');
    controller.dispose();
  });

  test('uses the authentication requirement resolved from Codex config', () {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..authStatus = AuthStatus.signedOut;

    controller.requiresOpenaiAuth = false;
    expect(controller.canSend, isTrue);

    controller.requiresOpenaiAuth = true;
    expect(controller.canSend, isFalse);
    controller.dispose();
  });

  test('disables sending until a restored thread is attached', () async {
    final restoredThread = thread(id: 'restored-thread');
    final server = FakeCodexAppServer()
      ..listResponse = [restoredThread.toJson()];
    final controller = CodexController(
      server: server,
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready
      ..requiresOpenaiAuth = false
      ..activeThreadId = 'restored-thread';

    expect(controller.canSend, isFalse);

    await controller.resumeThread(restoredThread);

    expect(controller.canSend, isTrue);
    controller.dispose();
  });
}

CodexThread thread({required String id}) =>
    CodexThread(id: id, preview: 'preview-$id', createdAt: 1, updatedAt: 2);
