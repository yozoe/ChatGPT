import 'package:chatgpt/src/app_controller_runtime_executable_coordinator.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:chatgpt/src/services/codex_app_server_codex_runtime_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates and persists a custom executable', () async {
    var selected = '/old/codex';
    String? saved;
    var inspections = 0;
    final coordinator = CodexRuntimeExecutableCoordinator(
      executable: () => selected,
      setExecutable: (path) => selected = path ?? 'automatic',
      inspect: () async {
        inspections++;
        return const CodexRuntimeProbe(
          isAvailable: true,
          executablePath: '/new/codex',
        );
      },
      saveExecutable: (path) async => saved = path,
      clearExecutable: () async {},
    );

    final probe = await coordinator.setCustomExecutable('/requested/codex');

    expect(probe.executablePath, '/new/codex');
    expect(selected, '/requested/codex');
    expect(saved, '/new/codex');
    expect(inspections, 1);
  });

  test('rolls back a custom executable when probing fails', () async {
    var selected = '/old/codex';
    final coordinator = CodexRuntimeExecutableCoordinator(
      executable: () => selected,
      setExecutable: (path) => selected = path ?? 'automatic',
      inspect: () async =>
          const CodexRuntimeProbe(isAvailable: false, error: 'missing'),
      saveExecutable: (_) async {},
      clearExecutable: () async {},
    );

    await expectLater(
      coordinator.setCustomExecutable('/bad/codex'),
      throwsA(isA<StateError>()),
    );
    expect(selected, '/old/codex');
  });

  test('reset clears persistence before probing automatic discovery', () async {
    String? selected = '/custom/codex';
    var cleared = false;
    final coordinator = CodexRuntimeExecutableCoordinator(
      executable: () => selected ?? 'automatic',
      setExecutable: (path) => selected = path,
      inspect: () async => const CodexRuntimeProbe(
        isAvailable: true,
        executablePath: '/auto/codex',
      ),
      saveExecutable: (_) async {},
      clearExecutable: () async => cleared = true,
    );

    final probe = await coordinator.resetExecutable();

    expect(selected, isNull);
    expect(cleared, isTrue);
    expect(probe.executablePath, '/auto/codex');
  });
}
