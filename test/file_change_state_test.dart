import 'package:chatgpt/src/app_controller_file_change_state.dart';
import 'package:chatgpt/src/domain/codex_file_change.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('separates current-turn and persisted thread collections', () {
    final state = CodexFileChangeState();
    const change = CodexFileChange(
      path: 'lib/main.dart',
      kind: 'modified',
      diff: '@@ -1 +1 @@',
    );

    state.fileChangesByPath[change.path] = change;
    state.turnFileChangesByPath[change.path] = change;
    state.turnDiffDerivedFileChangePaths.add(change.path);
    state.persistedFileChangesByThreadId['thread-1'] = [change];

    state.clearCurrentTurn();

    expect(state.fileChangesByPath, {change.path: change});
    expect(state.turnFileChangesByPath, isEmpty);
    expect(state.turnDiffDerivedFileChangePaths, isEmpty);
    expect(state.persistedFileChangesByThreadId['thread-1'], [change]);
  });

  test('removes every persisted file snapshot for one thread', () {
    final state = CodexFileChangeState()
      ..persistedFileChangesByThreadId['thread-1'] = const []
      ..persistedTurnFileChangesByThreadId['thread-1'] = const []
      ..persistedFileChangesBeforeTurnByThreadId['thread-1'] = const []
      ..persistedTurnDiffByThreadId['thread-1'] = 'diff'
      ..persistedFileChangesByThreadId['thread-2'] = const [];

    state.removeThread('thread-1');

    expect(state.persistedFileChangesByThreadId, {'thread-2': const []});
    expect(state.persistedTurnFileChangesByThreadId, isEmpty);
    expect(state.persistedFileChangesBeforeTurnByThreadId, isEmpty);
    expect(state.persistedTurnDiffByThreadId, isEmpty);
  });

  test('clear removes current and persisted collections', () {
    final state = CodexFileChangeState()
      ..fileChangesByPath['one.dart'] = const CodexFileChange(
        path: 'one.dart',
        kind: 'added',
        diff: 'new file',
      )
      ..turnExplicitFileChangePaths.add('one.dart')
      ..persistedTurnDiffByThreadId['thread-1'] = 'diff';

    state.clear();

    expect(state.fileChangesByPath, isEmpty);
    expect(state.turnExplicitFileChangePaths, isEmpty);
    expect(state.persistedTurnDiffByThreadId, isEmpty);
  });
}
