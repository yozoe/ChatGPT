import 'package:chatgpt/src/domain/browser_link_open_mode.dart';

/// Owns persisted browser preferences and load-time user-change markers.
///
/// The controller remains responsible for persistence, native browser calls,
/// and user-facing errors. This state only keeps the preference values and
/// protects a user edit made before the initial preference load completes.
class CodexBrowserPreferencesState {
  bool browserEnabled = true;
  BrowserLinkOpenMode browserLinkOpenMode = BrowserLinkOpenMode.system;
  String? browserDownloadDirectory;
  bool browserAskBeforeDownload = true;
  bool browserRestoreTabs = false;

  bool browserEnabledChangedBeforeLoad = false;
  bool browserLinkOpenModeChangedBeforeLoad = false;
  bool browserDownloadDirectoryChangedBeforeLoad = false;
  bool browserAskBeforeDownloadChangedBeforeLoad = false;
  bool browserRestoreTabsChangedBeforeLoad = false;
}
