import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps live counts when another file has no countable lines', () {
    final stats = reliableFileChangeStats(const [
      CodexFileChange(
        path: 'assets/logo.png',
        kind: 'modified',
        diff: 'diff --git a/assets/logo.png b/assets/logo.png',
      ),
      CodexFileChange(
        path: 'lib/main.dart',
        kind: 'modified',
        diff: '''diff --git a/lib/main.dart b/lib/main.dart
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1 +1 @@
-old
+new''',
      ),
    ], null);

    expect(stats?.additions, 1);
    expect(stats?.deletions, 1);
  });

  test('recovers only the matching file from a turn-wide Diff', () {
    final stats = reliableFileChangeStats(
      const [
        CodexFileChange(
          path: '/workspace/packages/app/lib/app.dart',
          kind: 'modified',
          diff: '',
        ),
      ],
      '''diff --git a/lib/main.dart b/lib/main.dart
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1 +1 @@
-old main
+new main
diff --git a/packages/app/lib/app.dart b/packages/app/lib/app.dart
--- a/packages/app/lib/app.dart
+++ b/packages/app/lib/app.dart
@@ -1,2 +1,3 @@
-old app
+new app
+another line
 context''',
    );

    expect(stats?.additions, 2);
    expect(stats?.deletions, 1);
  });

  test('does not substitute an unrelated turn-wide patch', () {
    final stats = reliableFileChangeStats(
      const [
        CodexFileChange(path: 'assets/logo.png', kind: 'modified', diff: ''),
      ],
      '''diff --git a/lib/main.dart b/lib/main.dart
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1 +1 @@
-old
+new''',
    );

    expect(stats, isNull);
  });

  test('keeps available counts while another file awaits its Diff', () {
    final stats = reliableFileChangeStats(const [
      CodexFileChange(
        path: 'lib/ready.dart',
        kind: 'modified',
        diff: '@@ -1 +1,2 @@\n-old\n+new\n+another',
      ),
      CodexFileChange(path: 'lib/pending.dart', kind: 'modified', diff: ''),
    ], null);

    expect(stats?.additions, 2);
    expect(stats?.deletions, 1);
  });

  test('prefers an exact path over an earlier suffix match', () {
    final stats = reliableFileChangeStats(
      const [
        CodexFileChange(path: 'lib/main.dart', kind: 'modified', diff: ''),
      ],
      '''diff --git a/packages/nested/lib/main.dart b/packages/nested/lib/main.dart
--- a/packages/nested/lib/main.dart
+++ b/packages/nested/lib/main.dart
@@ -1 +1,2 @@
-nested old
+nested new
+nested extra
diff --git a/lib/main.dart b/lib/main.dart
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1 +1 @@
-root old
+root new''',
    );

    expect(stats?.additions, 1);
    expect(stats?.deletions, 1);
  });

  test('hides stats when a relative path has multiple suffix matches', () {
    final stats = reliableFileChangeStats(
      const [
        CodexFileChange(path: 'lib/main.dart', kind: 'modified', diff: ''),
      ],
      '''diff --git a/packages/one/lib/main.dart b/packages/one/lib/main.dart
--- a/packages/one/lib/main.dart
+++ b/packages/one/lib/main.dart
@@ -1 +1 @@
-one old
+one new
diff --git a/packages/two/lib/main.dart b/packages/two/lib/main.dart
--- a/packages/two/lib/main.dart
+++ b/packages/two/lib/main.dart
@@ -1 +1 @@
-two old
+two new''',
    );

    expect(stats, isNull);
  });
}
