import 'dart:async';

import 'package:chatgpt/src/app_controller.dart';

import 'fake_codex_app_server.dart';
import 'fake_runtime_configuration_store.dart';
import 'memory_conversation_history_store.dart';

/// Controls fuzzy file-search completion without performing filesystem I/O.
class WorkspaceFileSearchController extends CodexController {
  WorkspaceFileSearchController()
    : super(
        server: FakeCodexAppServer(),
        runtimeConfigurationStore: FakeRuntimeConfigurationStore(),
        conversationHistoryStore: MemoryConversationHistoryStore(),
      );

  List<CodexFileSearchResult> response = const [];
  Object? error;
  final List<String> queries = [];
  final List<List<String>> rootsAtRequest = [];
  final List<String?> cancellationTokens = [];
  final List<Completer<List<CodexFileSearchResult>>> completers = [];

  @override
  Future<List<CodexFileSearchResult>> searchWorkspaceFiles(
    String query, {
    String? cancellationToken,
  }) {
    queries.add(query);
    rootsAtRequest.add(List.of(workspaceRoots));
    cancellationTokens.add(cancellationToken);
    if (error case final value?) return Future.error(value);
    if (completers.isNotEmpty) return completers.removeAt(0).future;
    return Future.value(response);
  }
}
