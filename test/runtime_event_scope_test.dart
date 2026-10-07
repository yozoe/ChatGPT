import 'package:chatgpt/src/app_controller_runtime_event_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers envelope identifiers over nested turn identifiers', () {
    const params = <String, dynamic>{
      'threadId': ' envelope-thread ',
      'turnId': ' envelope-turn ',
      'turn': {'threadId': 'nested-thread', 'id': 'nested-turn'},
    };

    expect(
      CodexRuntimeEventScope.threadIdFromParams(params),
      'envelope-thread',
    );
    expect(CodexRuntimeEventScope.turnIdFromParams(params), 'envelope-turn');
  });

  test('falls back to nested turn identifiers', () {
    const params = <String, dynamic>{
      'turn': {'threadId': 'nested-thread', 'id': 'nested-turn'},
    };

    expect(CodexRuntimeEventScope.threadIdFromParams(params), 'nested-thread');
    expect(CodexRuntimeEventScope.turnIdFromParams(params), 'nested-turn');
  });

  test('returns null for missing or blank identifiers', () {
    const params = <String, dynamic>{
      'threadId': '  ',
      'turnId': null,
      'turn': {'threadId': '', 'id': 0},
    };

    expect(CodexRuntimeEventScope.threadIdFromParams(params), isNull);
    expect(CodexRuntimeEventScope.turnIdFromParams(params), '0');
  });
}
