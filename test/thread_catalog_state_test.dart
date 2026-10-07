import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/app_controller_thread_catalog_state.dart';

void main() {
  test('clear removes active, archived, loading, and local status state', () {
    final state = CodexThreadCatalogState()
      ..threadsLoading = true
      ..threadsError = 'active error'
      ..archivedThreadsLoading = true
      ..archivedThreadsError = 'archive error'
      ..localThreadStatuses['thread-1'] = 'failed';

    state.clear();

    expect(state.threads, isEmpty);
    expect(state.archivedThreads, isEmpty);
    expect(state.threadsLoading, isFalse);
    expect(state.threadsError, isNull);
    expect(state.archivedThreadsLoading, isFalse);
    expect(state.archivedThreadsError, isNull);
    expect(state.localThreadStatuses, isEmpty);
  });

  test('active and archived catalogs remain independent', () {
    final state = CodexThreadCatalogState();

    state.threadsError = 'active error';

    expect(state.archivedThreadsError, isNull);
    expect(state.archivedThreads, isEmpty);
  });
}
