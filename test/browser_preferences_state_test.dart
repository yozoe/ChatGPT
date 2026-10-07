import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/app_controller_browser_preferences_state.dart';
import 'package:chatgpt/src/domain/browser_link_open_mode.dart';

void main() {
  test('uses safe browser preference defaults', () {
    final state = CodexBrowserPreferencesState();

    expect(state.browserEnabled, isTrue);
    expect(state.browserLinkOpenMode, BrowserLinkOpenMode.system);
    expect(state.browserDownloadDirectory, isNull);
    expect(state.browserAskBeforeDownload, isTrue);
    expect(state.browserRestoreTabs, isFalse);
  });

  test('load-time change markers remain independent', () {
    final state = CodexBrowserPreferencesState()
      ..browserEnabledChangedBeforeLoad = true
      ..browserRestoreTabsChangedBeforeLoad = true;

    expect(state.browserEnabledChangedBeforeLoad, isTrue);
    expect(state.browserLinkOpenModeChangedBeforeLoad, isFalse);
    expect(state.browserDownloadDirectoryChangedBeforeLoad, isFalse);
    expect(state.browserAskBeforeDownloadChangedBeforeLoad, isFalse);
    expect(state.browserRestoreTabsChangedBeforeLoad, isTrue);
  });
}
