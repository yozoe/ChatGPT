# Codex Desk Release Notes

## 1.0.0+1

Initial macOS release.

- Connect to the local Codex App Server and manage tasks, approvals, providers, plugins, and workspace threads.
- Keep encrypted local conversation history, restore workspace preferences, and provide a read-only Git change view.
- Include runtime diagnostics with credential redaction, API Key / browser sign-in, and configurable reasoning effort.
- Show live structured task plans in a floating step-progress panel with pending, active, and completed states.
- Make in-place macOS installs resilient to cancelled Automation quit requests, and request administrator privileges only when `/Applications` is not writable.
- Use Riverpod for application-level controller ownership and workspace state subscriptions, while preserving safe test and embedded-controller injection.
- Support batch archive and confirmed permanent task deletion with duplicate-submission protection.
- Package the unsigned Release application with `./build_dmg.sh`; Developer ID signing and Apple notarization are pending release credentials.
