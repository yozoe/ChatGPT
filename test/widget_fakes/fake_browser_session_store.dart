import 'package:chatgpt/src/domain/browser_tab_snapshot.dart';
import 'package:chatgpt/src/services/browser_session_store.dart';

/// In-memory session store for browser restore lifecycle tests.
class FakeBrowserSessionStore extends BrowserSessionStore {
  FakeBrowserSessionStore({this.snapshot});

  final ({List<BrowserTabSnapshot> tabs, int activeIndex})? snapshot;

  @override
  Future<({List<BrowserTabSnapshot> tabs, int activeIndex})?> read() async =>
      snapshot;

  @override
  Future<void> save({
    required List<BrowserTabSnapshot> tabs,
    required int activeIndex,
  }) async {}

  @override
  Future<void> clear() async {}
}
