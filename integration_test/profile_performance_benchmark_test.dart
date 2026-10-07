import 'dart:async';
import 'dart:io';

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'package:chatgpt/src/domain/git_project_status.dart';
import 'package:chatgpt/src/presentation/code_review/code_review_panel.dart';
import 'package:chatgpt/src/presentation/browser/codex_workspace_browser_workspace_page.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/widget_test_fakes.dart';

final _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

void main() {
  testWidgets('profile benchmark: 1000-thread sidebar refresh', (tester) async {
    final controller = _createController(threadCount: 1000);
    await _pumpWorkspace(tester, controller);

    await _binding.watchPerformance(
      () => _pumpNotifications(tester, controller, frames: 90),
      reportKey: 'sidebar_1000_threads',
    );
  });

  testWidgets('profile benchmark: streaming deltas', (tester) async {
    final controller = _createController(threadCount: 1)
      ..activeThreadId = 'thread-0'
      ..activeTurnId = 'turn-0'
      ..status = RuntimeStatus.running;
    await _pumpWorkspace(tester, controller);

    await _binding.watchPerformance(() async {
      for (var index = 0; index < 240; index++) {
        controller.handleServerEventForTesting(
          ServerEvent(
            method: 'item/agentMessage/delta',
            params: {
              'threadId': 'thread-0',
              'turnId': 'turn-0',
              'itemId': 'message-0',
              'delta': 'stream-$index ',
            },
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }, reportKey: 'streaming_deltas');
  });

  testWidgets('profile benchmark: background completion notifications', (
    tester,
  ) async {
    final controller = _createController(threadCount: 64)
      ..status = RuntimeStatus.ready
      ..activeThreadId = 'thread-0';
    await _pumpWorkspace(tester, controller);

    await _binding.watchPerformance(() async {
      for (var index = 1; index < 64; index++) {
        controller.handleServerEventForTesting(
          ServerEvent(
            method: 'turn/completed',
            params: {
              'threadId': 'thread-$index',
              'turnId': 'turn-$index',
              'turn': {'status': 'completed'},
            },
          ),
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
    }, reportKey: 'background_completion_notifications');
  });

  testWidgets('profile benchmark: rapid task switching', (tester) async {
    final controller = _createController(threadCount: 250)
      ..activeThreadId = 'thread-0'
      ..status = RuntimeStatus.ready;
    await _pumpWorkspace(tester, controller);

    final stopwatch = Stopwatch()..start();
    await _binding.watchPerformance(() async {
      for (var index = 0; index < 20; index++) {
        controller.activeThreadId = 'thread-${index % 20}';
        controller.notifyListeners();
        await tester.pump(const Duration(milliseconds: 32));
      }
    }, reportKey: 'rapid_task_switching');
    stopwatch.stop();
    _recordBenchmarkData('rapid_task_switching', {
      'switchCount': 20,
      'elapsedMicros': stopwatch.elapsedMicroseconds,
    });
  });

  testWidgets('profile benchmark: large unified diff parsing', (tester) async {
    final diff = _largeUnifiedDiff(fileCount: 500, linesPerFile: 24);
    var parsed = const <CodexFileChange>[];
    final stopwatch = Stopwatch()..start();
    await _binding.traceAction(() async {
      for (var iteration = 0; iteration < 8; iteration++) {
        parsed = codexFileChangesFromUnifiedDiff(diff);
      }
    }, reportKey: 'large_diff_parsing_timeline');
    stopwatch.stop();
    _binding.reportData ??= <String, dynamic>{};
    _binding.reportData!['large_diff_parsing'] = {
      'fileCount': 500,
      'linesPerFile': 24,
      'iterations': 8,
      'diffBytes': diff.length,
      'elapsedMicros': stopwatch.elapsedMicroseconds,
    };

    expect(parsed, hasLength(500));
  });

  testWidgets('profile benchmark: large Git review canvas', (tester) async {
    final controller = _createGitReviewController(
      fileCount: 500,
      linesPerFile: 24,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CodeReviewPanel(
          controller: controller,
          source: CodeReviewSource.gitWorkspace,
          compact: false,
          onSourceChanged: (_) {},
          onCollapse: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final canvas = find.byKey(
      const ValueKey('code-review-canvas-gitWorkspace'),
    );
    expect(canvas, findsOneWidget);
    final stopwatch = Stopwatch()..start();
    await _binding.watchPerformance(() async {
      await tester.drag(canvas, const Offset(0, -12000));
      await tester.pump(const Duration(milliseconds: 160));
      await tester.drag(canvas, const Offset(0, 12000));
      await tester.pump(const Duration(milliseconds: 160));
      await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const Key('code-review-navigation-toggle')));
      await tester.pump(const Duration(milliseconds: 80));
    }, reportKey: 'large_git_review_canvas');
    stopwatch.stop();
    _recordBenchmarkData('large_git_review_canvas', {
      'fileCount': 500,
      'linesPerFile': 24,
      'elapsedMicros': stopwatch.elapsedMicroseconds,
    });
  });

  testWidgets('profile benchmark: native WebView workspace expand and return', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_browserBenchmarkHtml());
        await request.response.close();
      }),
    );
    final expanded = ValueNotifier<bool>(false);
    addTearDown(expanded.dispose);
    final url = 'http://127.0.0.1:${server.port}/benchmark';
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: expanded,
          builder: (context, isExpanded, _) => Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: isExpanded ? 900 : 360,
              height: 700,
              child: BrowserWorkspacePage(
                onOpenConversation: () {},
                initialUrl: url,
                urlSafetyChecker: (_) async => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      InAppWebViewPlatform.instance.runtimeType.toString(),
      contains('MacOSInAppWebViewPlatform'),
    );
    expect(find.byKey(const Key('browser-native-webview-0')), findsOneWidget);

    final stopwatch = Stopwatch()..start();
    await _binding.watchPerformance(() async {
      for (var index = 0; index < 4; index++) {
        expanded.value = !expanded.value;
        await tester.pump(const Duration(milliseconds: 180));
      }
      await tester.pump(const Duration(milliseconds: 250));
    }, reportKey: 'native_webview_workspace_expand_return');
    stopwatch.stop();
    _recordBenchmarkData('native_webview_workspace_expand_return', {
      'transitions': 4,
      'collapsedWidth': 360,
      'expandedWidth': 900,
      'elapsedMicros': stopwatch.elapsedMicroseconds,
    });
    expect(tester.takeException(), isNull);
  });
}

CodexController _createController({required int threadCount}) {
  final controller =
      CodexController(
          server: CodexAppServer(executable: '/not/a/codex'),
          runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
          conversationHistoryStore: MemoryConversationHistoryStore(),
          localSessionThreadStore: MemoryLocalSessionThreadStore(),
          pluginStore: MemoryCodexPluginStore(),
        )
        ..workspacePath = '/profile-benchmark-workspace'
        ..threads = List<CodexThread>.generate(
          threadCount,
          (index) => CodexThread(
            id: 'thread-$index',
            preview: 'Profile benchmark task $index',
            createdAt: index,
            updatedAt: index,
            status: 'idle',
          ),
        );
  return controller;
}

void _recordBenchmarkData(String key, Map<String, Object> values) {
  _binding.reportData ??= <String, dynamic>{};
  final current = _binding.reportData![key];
  if (current is Map<String, dynamic>) {
    current.addAll(values);
  } else {
    _binding.reportData![key] = <String, dynamic>{...values};
  }
}

CodexController _createGitReviewController({
  required int fileCount,
  required int linesPerFile,
}) {
  final changes = [
    for (var index = 0; index < fileCount; index++)
      GitProjectChange(code: ' M', path: 'lib/generated/review_$index.dart'),
  ];
  final diffs = <String, GitDiffPreview>{
    for (final change in changes)
      change.path: GitDiffPreview(
        content: _fileUnifiedDiff(change.path, linesPerFile: linesPerFile),
        truncated: false,
      ),
  };
  return CodexController(
      server: CodexAppServer(executable: '/not/a/codex'),
      runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
      conversationHistoryStore: MemoryConversationHistoryStore(),
      localSessionThreadStore: MemoryLocalSessionThreadStore(),
      pluginStore: MemoryCodexPluginStore(),
    )
    ..workspacePath = '/profile-benchmark-workspace'
    ..status = RuntimeStatus.ready
    ..gitProjectStatus = GitProjectStatus(
      isRepository: true,
      branch: 'main',
      changes: changes,
    )
    ..gitReviewDiffs = diffs;
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  CodexController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(home: CodexWorkspace(controller: controller)),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _pumpNotifications(
  WidgetTester tester,
  CodexController controller, {
  required int frames,
}) async {
  for (var index = 0; index < frames; index++) {
    controller.notifyListeners();
    await tester.pump(const Duration(milliseconds: 16));
  }
}

String _largeUnifiedDiff({required int fileCount, required int linesPerFile}) {
  final buffer = StringBuffer();
  for (var fileIndex = 0; fileIndex < fileCount; fileIndex++) {
    final path = 'lib/generated/benchmark_$fileIndex.dart';
    buffer
      ..writeln('diff --git a/$path b/$path')
      ..writeln('index 0000000..1111111 100644')
      ..writeln('--- a/$path')
      ..writeln('+++ b/$path')
      ..writeln('@@ -0,0 +1,$linesPerFile @@');
    for (var lineIndex = 0; lineIndex < linesPerFile; lineIndex++) {
      buffer.writeln('+final value${fileIndex}_$lineIndex = $lineIndex;');
    }
  }
  return buffer.toString();
}

String _fileUnifiedDiff(String path, {required int linesPerFile}) {
  final buffer = StringBuffer()
    ..writeln('diff --git a/$path b/$path')
    ..writeln('index 0000000..1111111 100644')
    ..writeln('--- a/$path')
    ..writeln('+++ b/$path')
    ..writeln('@@ -0 +1,$linesPerFile @@');
  for (var lineIndex = 0; lineIndex < linesPerFile; lineIndex++) {
    buffer.writeln('+final value_$lineIndex = $lineIndex;');
  }
  return buffer.toString();
}

String _browserBenchmarkHtml() {
  final rows = StringBuffer();
  for (var index = 0; index < 300; index++) {
    rows.writeln('<p>Benchmark row $index — deterministic WebKit content.</p>');
  }
  return '''<!doctype html>
<html><head><meta name="viewport" content="width=device-width">
<style>body{font:14px -apple-system;margin:24px}p{margin:8px 0}</style>
</head><body><h1>WebView benchmark</h1>$rows</body></html>''';
}
