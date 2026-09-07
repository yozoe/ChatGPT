import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('redacts credentials from runtime diagnostics', () {
    final value = CodexAppServer.redactDiagnosticText(
      'api_key=private-key token: token-value '
      '{"secret":"json-secret"} authorization: Bearer bearer-value '
      'Authorization: Basic YWxpY2U6c2VjcmV0 sk-private',
    );

    expect(value, contains('api_key=***'));
    expect(value, contains('token: ***'));
    expect(value, isNot(contains('private-key')));
    expect(value, isNot(contains('token-value')));
    expect(value, isNot(contains('json-secret')));
    expect(value, isNot(contains('bearer-value')));
    expect(value, contains('Authorization: ***'));
    expect(value, isNot(contains('YWxpY2U6c2VjcmV0')));
    expect(value, isNot(contains('sk-private')));
  });

  test('keeps bounded redacted runtime logs in diagnostic reports', () {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..runtimeProbe = const CodexRuntimeProbe(
        isAvailable: true,
        executablePath: '/usr/local/bin/codex',
        version: 'codex 1.2.3',
        discovery: '自动查找：用户设置、常见安装位置和 PATH。',
      )
      ..lastError = 'token=last-error-token';

    for (var index = 0; index < 201; index++) {
      controller.handleServerEventForTesting(
        ServerEvent(
          method: 'runtime/stderr',
          params: {'message': 'log-$index api_key=secret-$index'},
        ),
      );
    }
    final report = controller.buildRuntimeDiagnosticReport();

    expect(controller.runtimeLogs, hasLength(200));
    expect(controller.runtimeLogs.first.message, contains('log-1'));
    expect(report, contains('CLI version: codex 1.2.3'));
    expect(report, contains('Recent runtime logs (200/200)'));
    expect(report, isNot(contains('secret-')));
    expect(report, isNot(contains('last-error-token')));
    controller.dispose();
  });

  test('notifies only diagnostics listeners for log writes and clears', () {
    final controller = CodexController(server: CodexAppServer());
    var diagnosticsNotifications = 0;
    var controllerNotifications = 0;
    controller.runtimeDiagnostics.addListener(() => diagnosticsNotifications++);
    controller.addListener(() => controllerNotifications++);

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'runtime/stderr',
        params: {'message': 'diagnostic event'},
      ),
    );
    expect(diagnosticsNotifications, 1);
    expect(controllerNotifications, 0);

    controller.clearRuntimeLogs();
    expect(diagnosticsNotifications, 2);
    expect(controllerNotifications, 0);
    controller.dispose();
  });

  test('deduplicates concurrent runtime startup attempts', () async {
    final controller = CodexController(
      server: CodexAppServer(executable: '/not/a/codex'),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
    );
    await controller.waitForInitialConfiguration();
    controller.workspacePath = Directory.systemTemp.path;

    final firstStart = controller.startRuntime();
    final secondStart = controller.startRuntime();

    expect(controller.status, RuntimeStatus.starting);
    await Future.wait([firstStart, secondStart]);

    expect(
      controller.entries.where((entry) => entry.title == '正在启动本地运行时'),
      hasLength(1),
    );
    controller.dispose();
  });

  test('reports a clear diagnostic for a missing Codex executable', () async {
    final server = CodexAppServer(executable: '/not/a/codex');

    final probe = await server.probe();

    expect(probe.isAvailable, isFalse);
    expect(probe.error, contains('未找到 Codex CLI'));
    await server.dispose();
  });

  test(
    'keeps missing CLI failures recoverable with redacted diagnostics on retry',
    () async {
      final controller = CodexController(
        server: CodexAppServer(executable: '/not/a/codex?token=private-token'),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      );
      await controller.waitForInitialConfiguration();
      controller.workspacePath = Directory.systemTemp.path;

      await controller.startRuntime();

      expect(controller.status, RuntimeStatus.failed);
      expect(controller.lastError, contains('未找到 Codex CLI'));
      final firstReport = controller.buildRuntimeDiagnosticReport();
      expect(firstReport, contains('Runtime status: failed'));
      expect(firstReport, contains('CLI available: no'));
      expect(firstReport, isNot(contains('private-token')));

      await controller.startRuntime();

      expect(controller.status, RuntimeStatus.failed);
      expect(
        controller.entries.where((entry) => entry.title == '无法启动运行时'),
        hasLength(2),
      );
      controller.dispose();
    },
  );
}
