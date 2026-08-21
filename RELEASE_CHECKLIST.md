# macOS Release Checklist

Run this checklist for every release. The DMG build never launches the application.

## Build and package

1. Update `version` in `pubspec.yaml` and add an entry to [RELEASE_NOTES.md](RELEASE_NOTES.md).
2. Run `dart format .`, `flutter analyze`, `flutter test`, and `flutter build macos --debug`.
3. Run `./build_dmg.sh`; it produces `dist/Codex-Desk-<version>.dmg`.
4. Verify the DMG with `hdiutil verify dist/Codex-Desk-<version>.dmg`.

## Clean-macOS installation regression

Use a separate macOS user account or a clean test machine. Do not reuse the development application bundle or prior Codex Desk Keychain items.

1. Mount the generated DMG and drag `Codex Desk.app` to `Applications`.
2. Start the installed app, choose a test workspace, and verify that no CLI is shown as a clear recoverable error when `codex` is absent.
3. Use “Codex CLI” to confirm the diagnostic report can be copied and contains no test credential.
4. Install or select a test Codex CLI, start the runtime, stop it, then start it again to verify retry behavior.
5. Quit the app, reopen it, and verify the selected workspace and window geometry restore correctly.
6. Unmount the DMG, remove the test app, and record the macOS version and test result in the release PR.

## Signing and notarization (requires release credentials)

1. Sign the release bundle with the project Developer ID Application certificate and verify with `codesign --verify --deep --strict`.
2. Submit the signed DMG to Apple notarization with the project App Store Connect credentials, then staple and assess it with `spctl`.
3. Re-run the clean-macOS regression against the notarized DMG before publishing it.
