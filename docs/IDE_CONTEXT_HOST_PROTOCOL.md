# IDE context host protocol

`CodexIdeContextBridge` listens on the Flutter `MethodChannel`
`codex_desk/ide_context`. This is a host contract; the desktop application does
not claim that a VS Code, Xcode, or other IDE plugin is bundled.

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
IPC format.
