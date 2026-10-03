/// Determines where a user-activated HTTP(S) link should open.
enum BrowserLinkOpenMode { system, inApp }

BrowserLinkOpenMode browserLinkOpenModeFromStorage(String? value) =>
    switch (value?.trim().toLowerCase()) {
      'in-app' || 'inapp' || 'browser' => BrowserLinkOpenMode.inApp,
      _ => BrowserLinkOpenMode.system,
    };

String browserLinkOpenModeStorageValue(BrowserLinkOpenMode mode) =>
    switch (mode) {
      BrowserLinkOpenMode.system => 'system',
      BrowserLinkOpenMode.inApp => 'in-app',
    };
