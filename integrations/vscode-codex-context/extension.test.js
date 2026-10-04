const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const Module = require('node:module');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

function disposable() {
  return { dispose() {} };
}

function createVscodeMock(state, events) {
  const configuration = {
    get(key) {
      return key === 'discoveryFile' ? state.discoveryFile : undefined;
    },
  };
  return {
    StatusBarAlignment: { Left: 1 },
    ThemeColor: class ThemeColor {
      constructor(id) {
        this.id = id;
      }
    },
    workspace: {
      getConfiguration() {
        return configuration;
      },
      onDidChangeWorkspaceFolders(callback) {
        events.workspaceFolders = callback;
        return disposable();
      },
    },
    window: {
      activeTextEditor: state.editor,
      tabGroups: {
        all: state.tabGroups,
        onDidChangeTabs(callback) {
          events.tabs = callback;
          return disposable();
        },
      },
      createStatusBarItem() {
        return {
          show() {},
          text: '',
          tooltip: '',
          command: '',
          color: undefined,
        };
      },
      onDidChangeActiveTextEditor(callback) {
        events.activeEditor = callback;
        return disposable();
      },
      onDidChangeTextEditorSelection(callback) {
        events.selection = callback;
        return disposable();
      },
      onDidChangeVisibleTextEditors(callback) {
        events.visibleEditors = callback;
        return disposable();
      },
    },
    commands: {
      registerCommand(_name, callback) {
        events.command = callback;
        return disposable();
      },
    },
  };
}

test('sends editor changes and an empty snapshot on deactivation', async () => {
  const temporaryDirectory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'codex-vscode-context-'),
  );
  const discoveryFile = path.join(temporaryDirectory, 'discovery.json');
  const snapshots = [];
  const server = http.createServer((request, response) => {
    let body = '';
    request.setEncoding('utf8');
    request.on('data', (chunk) => (body += chunk));
    request.on('end', () => {
      assert.equal(
        request.headers.authorization,
        'Bearer test-token-01234567890123456789',
      );
      snapshots.push(JSON.parse(body));
      response.statusCode = 200;
      response.end();
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  fs.writeFileSync(
    discoveryFile,
    JSON.stringify({
      version: 1,
      host: '127.0.0.1',
      port: address.port,
      path: '/updateContext',
      token: 'test-token-01234567890123456789',
    }),
  );

  const state = {
    discoveryFile,
    editor: {
      document: {
        isUntitled: false,
        uri: { fsPath: '/workspace/main.dart' },
        getText: () => 'selected();',
      },
      selection: {
        start: { line: 2, character: 1 },
        end: { line: 2, character: 11 },
      },
    },
    tabGroups: [
      {
        tabs: [
          { input: { uri: { scheme: 'file', fsPath: '/workspace/main.dart' } } },
          { input: { uri: { scheme: 'file', fsPath: '/workspace/test.dart' } } },
        ],
      },
    ],
  };
  const events = {};
  const vscode = createVscodeMock(state, events);
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (request === 'vscode') return vscode;
    return originalLoad.call(this, request, parent, isMain);
  };
  delete require.cache[require.resolve('./extension.js')];
  const extension = require('./extension.js');
  const context = { subscriptions: [] };
  try {
    extension.activate(context);
    await waitFor(() => snapshots.length === 1);
    assert.deepEqual(snapshots[0].activeFile, {
      fsPath: '/workspace/main.dart',
      selectedText: 'selected();',
      selectionRange: {
        start: { line: 2, character: 1 },
        end: { line: 2, character: 11 },
      },
    });
    assert.deepEqual(snapshots[0].openTabs, [
      { fsPath: '/workspace/main.dart' },
      { fsPath: '/workspace/test.dart' },
    ]);

    state.editor.selection.start.character = 0;
    events.selection();
    await waitFor(() => snapshots.length === 2);
    assert.equal(snapshots[1].activeFile.selectionRange.start.character, 0);

    await extension.deactivate();
    await waitFor(() => snapshots.length === 3);
    assert.deepEqual(snapshots[2], {});
  } finally {
    Module._load = originalLoad;
    server.close();
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
});

test('retries after discovery disappears and follows workspace changes', async () => {
  const temporaryDirectory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'codex-vscode-context-lifecycle-'),
  );
  const discoveryFile = path.join(temporaryDirectory, 'discovery.json');
  const snapshots = [];
  const server = http.createServer((request, response) => {
    let body = '';
    request.setEncoding('utf8');
    request.on('data', (chunk) => (body += chunk));
    request.on('end', () => {
      snapshots.push(JSON.parse(body));
      response.statusCode = 200;
      response.end();
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  const writeDiscovery = () =>
    fs.writeFileSync(
      discoveryFile,
      JSON.stringify({
        version: 1,
        host: '127.0.0.1',
        port: address.port,
        path: '/updateContext',
        token: 'test-token-01234567890123456789',
      }),
    );
  writeDiscovery();

  const state = {
    discoveryFile,
    editor: {
      document: {
        isUntitled: false,
        uri: { fsPath: '/workspace/first/main.dart' },
        getText: () => '',
      },
      selection: {
        start: { line: 0, character: 0 },
        end: { line: 0, character: 0 },
      },
    },
    tabGroups: [],
  };
  const events = {};
  const vscode = createVscodeMock(state, events);
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (request === 'vscode') return vscode;
    return originalLoad.call(this, request, parent, isMain);
  };
  delete require.cache[require.resolve('./extension.js')];
  const extension = require('./extension.js');
  try {
    extension.activate({ subscriptions: [] });
    await waitFor(() => snapshots.length === 1);

    fs.unlinkSync(discoveryFile);
    state.editor.document.uri.fsPath = '/workspace/second/main.dart';
    events.workspaceFolders();
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(snapshots.length, 1);

    writeDiscovery();
    events.workspaceFolders();
    await waitFor(() => snapshots.length === 2);
    assert.equal(snapshots[1].activeFile.fsPath, '/workspace/second/main.dart');

    await extension.deactivate();
    await waitFor(() => snapshots.length === 3);
    assert.deepEqual(snapshots[2], {});
  } finally {
    Module._load = originalLoad;
    server.close();
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
});

async function waitFor(predicate) {
  const deadline = Date.now() + 2000;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error('Timed out waiting for snapshot');
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}
