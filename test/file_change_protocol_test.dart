import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records App Server file changes and unified diffs for display', () {
    final controller = CodexController(server: CodexAppServer());

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {
                'path': 'lib/main.dart',
                'kind': 'modified',
                'diff': '@@ -1 +1 @@\n-old\n+new',
              },
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': 'diff --git a/lib/main.dart b/lib/main.dart'},
      ),
    );

    expect(controller.fileChanges, [
      const CodexFileChange(
        path: 'lib/main.dart',
        kind: 'modified',
        diff: '@@ -1 +1 @@\n-old\n+new',
      ),
    ]);
    expect(controller.turnDiff, 'diff --git a/lib/main.dart b/lib/main.dart');
    expect(
      controller.entries.map((entry) => '${entry.title}:${entry.detail}'),
      isNot(contains('文件变更:modified lib/main.dart')),
    );
    controller.dispose();
  });

  test('derives task files when App Server supplies only a turn-wide diff', () {
    final controller = CodexController(server: CodexAppServer());
    const diff =
        'diff --git a/lib/old.dart b/lib/old.dart\n'
        'deleted file mode 100644\n'
        'diff --git a/lib/new.dart b/lib/new.dart\n'
        'new file mode 100644\n'
        '--- /dev/null\n'
        '+++ b/lib/new.dart\n'
        '@@ -0,0 +1 @@\n'
        '+new';

    controller.handleServerEventForTesting(
      const ServerEvent(method: 'turn/diff/updated', params: {'diff': diff}),
    );

    expect(controller.turnDiff, diff);
    expect(controller.fileChanges, [
      const CodexFileChange(
        path: 'lib/old.dart',
        kind: 'deleted',
        diff:
            'diff --git a/lib/old.dart b/lib/old.dart\ndeleted file mode 100644',
      ),
      const CodexFileChange(
        path: 'lib/new.dart',
        kind: 'added',
        diff:
            'diff --git a/lib/new.dart b/lib/new.dart\n'
            'new file mode 100644\n'
            '--- /dev/null\n'
            '+++ b/lib/new.dart\n'
            '@@ -0,0 +1 @@\n'
            '+new',
      ),
    ]);
    controller.dispose();
  });

  test('replaces files derived from a superseded turn-wide diff', () {
    final controller = CodexController(server: CodexAppServer());
    const firstDiff =
        'diff --git a/first.dart b/first.dart\n'
        '@@ -1 +1 @@\n'
        '-old\n'
        '+first';
    const secondDiff =
        'diff --git a/second.dart b/second.dart\n'
        '@@ -1 +1 @@\n'
        '-old\n'
        '+second';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': firstDiff},
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': secondDiff},
      ),
    );

    expect(controller.fileChanges.map((change) => change.path), [
      'second.dart',
    ]);
    controller.dispose();
  });

  test('replaces a derived patch after a metadata-only file change event', () {
    final controller = CodexController(server: CodexAppServer());
    const firstDiff =
        'diff --git a/lib/main.dart b/lib/main.dart\n'
        '@@ -1 +1 @@\n'
        '-old\n'
        '+first';
    const secondDiff =
        'diff --git a/lib/main.dart b/lib/main.dart\n'
        '@@ -1 +1 @@\n'
        '-old\n'
        '+second';

    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': firstDiff},
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'item/completed',
        params: {
          'item': {
            'type': 'fileChange',
            'changes': [
              {'path': 'lib/main.dart', 'kind': 'modified'},
            ],
          },
        },
      ),
    );
    controller.handleServerEventForTesting(
      const ServerEvent(
        method: 'turn/diff/updated',
        params: {'diff': secondDiff},
      ),
    );

    expect(controller.turnDiff, secondDiff);
    expect(controller.fileChanges.single.diff, secondDiff);
    controller.dispose();
  });

  test('parses quoted paths from a turn-wide diff', () {
    const diff =
        'diff --git "a/目录\\t文件.dart" "b/目录\\t文件.dart"\n'
        '@@ -1 +1 @@\n'
        '-old\n'
        '+new';

    expect(codexFileChangesFromUnifiedDiff(diff).single.path, '目录\t文件.dart');
  });
}
