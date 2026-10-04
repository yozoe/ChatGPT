const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const vscode = require('vscode');

const DISCOVERY_FILE_NAME = 'ide-context-host.json';
const MAX_SELECTED_TEXT = 64000;
const MAX_OPEN_TABS = 64;
let refreshTimer;

function discoveryCandidates() {
  const configured = vscode.workspace
    .getConfiguration('codexDesk')
    .get('discoveryFile');
  if (typeof configured === 'string' && configured.trim()) {
    return [configured.trim()];
  }
  const support = path.join(os.homedir(), 'Library', 'Application Support');
  return [
    path.join(support, 'Codex Desk', DISCOVERY_FILE_NAME),
    path.join(support, 'Codex Desk Development', DISCOVERY_FILE_NAME),
  ];
}

function readDiscovery() {
  for (const candidate of discoveryCandidates()) {
    try {
      const value = JSON.parse(fs.readFileSync(candidate, 'utf8'));
      if (
        value &&
        value.version === 1 &&
        value.host === '127.0.0.1' &&
        Number.isInteger(value.port) &&
        value.port > 0 &&
        typeof value.token === 'string' &&
        value.token.length > 20
      ) {
        return value;
      }
    } catch (_) {
      // Codex Desk may be starting or stopping; retry on the next editor event.
    }
  }
  return null;
}

function fileContext(editor) {
  if (!editor || !editor.document || editor.document.isUntitled) return null;
  const selection = editor.selection;
  const selectedText = editor.document.getText(selection).slice(0, MAX_SELECTED_TEXT);
  return {
    fsPath: editor.document.uri.fsPath,
    selectedText,
    selectionRange: {
      start: {
        line: selection.start.line,
        character: selection.start.character,
      },
      end: {
        line: selection.end.line,
        character: selection.end.character,
      },
    },
  };
}

function snapshot() {
  const activeFile = fileContext(vscode.window.activeTextEditor);
  const openTabs = [];
  for (const group of vscode.window.tabGroups.all) {
    for (const tab of group.tabs) {
      if (tab.input && tab.input.uri && tab.input.uri.scheme === 'file') {
        openTabs.push({ fsPath: tab.input.uri.fsPath });
        if (openTabs.length >= MAX_OPEN_TABS) break;
      }
    }
    if (openTabs.length >= MAX_OPEN_TABS) break;
  }
  return { activeFile, openTabs };
}

function postSnapshot(value) {
  const discovery = readDiscovery();
  if (!discovery) return Promise.resolve(false);
  const body = Buffer.from(JSON.stringify(value));
  return new Promise((resolve) => {
    const request = http.request(
      {
        hostname: discovery.host,
        port: discovery.port,
        path: discovery.path || '/updateContext',
        method: 'POST',
        headers: {
          Authorization: `Bearer ${discovery.token}`,
          'Content-Type': 'application/json',
          'Content-Length': body.length,
        },
        timeout: 1000,
      },
      (response) => {
        response.resume();
        resolve(response.statusCode === 200);
      },
    );
    request.on('error', () => resolve(false));
    request.on('timeout', () => {
      request.destroy();
      resolve(false);
    });
    request.end(body);
  });
}

function activate(context) {
  const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 10);
  status.text = '$(code) Codex Context';
  status.tooltip = 'Send the active editor context to Codex Desk';
  status.command = 'codexDesk.refreshContext';
  status.show();
  context.subscriptions.push(status);

  const send = () => {
    void postSnapshot(snapshot()).then((sent) => {
      status.color = sent ? undefined : new vscode.ThemeColor('descriptionForeground');
    });
  };
  refreshTimer = setInterval(send, 2000);
  context.subscriptions.push({ dispose: () => clearInterval(refreshTimer) });
  context.subscriptions.push(
    vscode.commands.registerCommand('codexDesk.refreshContext', send),
    vscode.window.onDidChangeActiveTextEditor(send),
    vscode.window.onDidChangeTextEditorSelection(send),
    vscode.window.onDidChangeVisibleTextEditors(send),
    vscode.window.tabGroups.onDidChangeTabs(send),
    vscode.workspace.onDidChangeWorkspaceFolders(send),
  );
  send();
}

function deactivate() {
  if (refreshTimer) {
    clearInterval(refreshTimer);
    refreshTimer = undefined;
  }
  // Codex Desk treats a missing discovery update as stale and clears the
  // selected chip when the host is no longer connected.
  return postSnapshot({});
}

module.exports = { activate, deactivate };
