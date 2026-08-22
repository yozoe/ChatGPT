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
2. Start the installed app, choose a test workspace, and verify that no CLI is shown as a clear recoverable error when `codex` is absent. Confirm that the timeline shows the bounded retry countdown and stops retrying after the third attempt.
3. Use “Codex CLI” to confirm the diagnostic report can be copied and contains no test credential.
4. Install or select a test Codex CLI, choose “重新检测”, and verify that the app connects without being restarted or exposing start/stop controls.
5. Create a second workspace and verify that both entries appear in the sidebar, the current entry is visibly selected, and the other entry switches with one click. Confirm that the runtime reconnects automatically and each workspace restores its own additional directories. Remove a non-active workspace record and confirm that its directory is not deleted.
6. Quit the app, reopen it, and verify that the selected primary/additional workspaces and window geometry restore correctly and the runtime reconnects automatically.
7. Complete a task that creates an untracked file and verify the completion card shows the file count and Diff statistics; click “审核” and confirm the read-only review window shows the file and full-task Diff. If the App Server omits a file-level Diff, verify the UI shows a safe workspace fallback or unknown statistics rather than a false `+0 -0`.
8. Unmount the DMG, remove the test app, and record the macOS version and test result in the release PR.

## Signing and notarization (requires release credentials)

1. Confirm the Developer ID Application certificate is available in Keychain.
2. Create a reusable Keychain profile once with `xcrun notarytool store-credentials <profile>`; never store its password or API key in the repository.
3. Run `./build_dmg.sh --sign-identity "<Developer ID Application identity>" --notary-profile "<profile>"`. The script verifies the signatures, submits and waits for notarization, staples the ticket, validates it, and runs `spctl` assessment.
4. Re-run the clean-macOS regression against the notarized DMG before publishing it.
