# Codex Desk Context for VS Code

This is the first concrete IDE host for the generic `codex_desk/ide_context`
contract. It sends the active file, selection range, selected text and up to 64
visible file tabs to a running Codex Desk instance.

Codex Desk publishes a short-lived discovery file at:

- `~/Library/Application Support/Codex Desk/ide-context-host.json` for release;
- `~/Library/Application Support/Codex Desk Development/ide-context-host.json` for debug/profile.

The file contains a loopback port and a per-process bearer token. The extension
never sends editor context to a remote host and does nothing when Codex Desk is
not running. Set `codexDesk.discoveryFile` to override discovery for packaged
or test environments.

This host is intentionally explicit: editor changes update the bridge, but the
Codex Desk Composer only sends the snapshot after the user selects its IDE
context action.

The extension retries discovery on editor events and every two seconds, so it
can connect after Codex Desk starts without requiring a VS Code reload. Run
`npm test` in this directory to exercise active-editor, selection, and
deactivation behavior against a local loopback server.
