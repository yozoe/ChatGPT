# IDE context host protocol

`CodexIdeContextBridge` accepts snapshots through the Flutter `MethodChannel`
`codex_desk/ide_context` and through its local IDE host transport. The first
concrete host is the VS Code extension in
[`integrations/vscode-codex-context`](../integrations/vscode-codex-context).
The extension is intentionally separate from the desktop bundle and only
connects to a Codex Desk process on the same machine.

## VS Code transport

Codex Desk publishes a discovery record at:

- `~/Library/Application Support/Codex Desk/ide-context-host.json` in release;
- `~/Library/Application Support/Codex Desk Development/ide-context-host.json`
  in debug/profile builds.

The record is atomically replaced and contains a loopback host, an ephemeral
port, `/updateContext`, the current process ID, and a per-process bearer token.
The VS Code extension sends `POST` JSON requests only to `127.0.0.1` and treats
missing, stale, or invalid records as a disconnected host. Requests without
the exact bearer token, malformed JSON, or bodies over 512 KiB are rejected.
The record and endpoint are removed when Codex Desk stops the bridge.

## Host to Composer

Send a method call named `updateContext` whenever the active editor context
changes. The arguments must be a JSON-compatible object:

```json
{
  "activeFile": {
    "path": "/workspace/lib/main.dart",
    "selectedText": "runApp(App());",
    "selectionRange": {
      "start": {"line": 4, "character": 2},
      "end": {"line": 4, "character": 16}
    }
  },
  "openTabs": [
    {"path": "/workspace/lib/main.dart"},
    {"path": "/workspace/test/widget_test.dart"}
  ]
}
```

`activeFile` and each `openTabs` item may use `fsPath` instead of `path`.
`activeSelectionContent` is accepted as an alias for `selectedText`. Empty or
malformed files are ignored; an empty object means the host is disconnected.
The bridge keeps at most 64 open tabs and truncates selected text to 64,000
characters so an accidental full-file selection cannot make a turn unbounded.

## Composer behavior

The `/IDE 上下文` command remains disabled until a valid snapshot is present.
Selecting it adds a temporary `IDE 上下文` chip. Only an explicit selection is
sent, as a JSON string in App Server `turn/start.additionalContext` or
`turn/steer.additionalContext` under the opaque source key `ide`. A host update
never automatically changes or sends a user selection.

The chip is removed when the host disconnects, when the active project changes,
after a successful submission, or when the user removes it. The ordinary
“当前项目” action is independent and only sends the workspace path.

## Host responsibilities

The host must send absolute paths belonging to the active project roots, avoid
sending secrets or full files unnecessarily, and send `{}` when its editor
window closes. The host is responsible for obtaining user consent according to
its IDE's privacy model. The App Server source key and value serialization are
opaque protocol details; plugins must not depend on a private Codex extension
IPC format. The VS Code extension sends `{}` when it is deactivated; while
Codex Desk is not running it waits silently and retries discovery on editor
events and a short polling interval. The extension truncates selected text to
64,000 characters and visible file tabs to 64 entries before sending.
