import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('publishes an immutable copy of the controller thread catalog', () {
    final controller = CodexController()
      ..threads = [
        const CodexThread(
          id: 'thread-1',
          preview: 'Preview',
          createdAt: 1,
          updatedAt: 2,
        ),
      ];
    final container = ProviderContainer();
    addTearDown(() {
      container.dispose();
      controller.dispose();
    });

    final snapshot = container.read(
      codexThreadCatalogSnapshotProvider(controller),
    );

    expect(snapshot.threads.single.id, 'thread-1');
    expect(
      () => snapshot.threads.add(snapshot.threads.single),
      throwsUnsupportedError,
    );
  });

  test(
    'publishes a new snapshot when the controller notifies listeners',
    () async {
      final controller = CodexController()
        ..threads = [
          const CodexThread(
            id: 'thread-1',
            preview: 'First',
            createdAt: 1,
            updatedAt: 1,
          ),
        ];
      final container = ProviderContainer();
      final snapshots = <CodexThreadCatalogSnapshot>[];
      final subscription = container.listen(
        codexThreadCatalogSnapshotProvider(controller),
        (previous, next) => snapshots.add(next),
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
        controller.dispose();
      });

      final original = snapshots.single;
      controller.threads = [
        const CodexThread(
          id: 'thread-2',
          preview: 'Second',
          createdAt: 2,
          updatedAt: 2,
        ),
      ];
      controller.notifyListeners();
      await container.pump();

      expect(snapshots.last.threads.single.id, 'thread-2');
      expect(original.threads.single.id, 'thread-1');
    },
  );
}
