import 'package:chatgpt/src/app_controller_live_turn_activity_mapper.dart';
import 'package:chatgpt/src/app_controller_live_turn_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mapper = CodexLiveTurnActivityMapper();

  test('maps parsed filesystem commands and web search actions', () {
    expect(
      mapper.map({
        'id': 'command-1',
        'type': 'commandExecution',
        'commandActions': [
          {'type': 'read', 'name': '/workspace/lib/main.dart'},
        ],
      }),
      isA<LiveTurnActivity>()
          .having((value) => value.kind, 'kind', 'fileRead')
          .having((value) => value.detail, 'detail', 'main.dart'),
    );
    final search = mapper.map({
      'id': 'search-1',
      'type': 'webSearch',
      'action': {'type': 'openPage', 'url': 'https://example.com'},
    });
    expect(search?.label, '正在打开网页');
    expect(search?.detail, 'https://example.com');
  });

  test('maps skill and collaboration payloads with stable labels', () {
    final skill = mapper.map({
      'id': 'skill-1',
      'type': 'dynamicToolCall',
      'namespace': 'skills',
      'tool': 'read',
      'skillPath': '/workspace/code-review/SKILL.md',
    });
    expect(skill?.kind, 'skillRead');
    expect(skill?.label, '正在读取 Code Review 技能');

    final collaboration = mapper.map({
      'id': 'activity-1',
      'type': 'subAgentActivity',
      'agentThreadId': 'child-1',
      'agentStatus': {'displayName': 'Reviewer', 'status': 'running'},
    });
    expect(collaboration?.label, 'Reviewer');
    expect(collaboration?.status, 'working');
    expect(collaboration?.linkedThreadId, 'child-1');
  });

  test('normalizes reasoning summaries and ignores user messages', () {
    final reasoning = mapper.map({
      'id': 'reasoning-1',
      'type': 'reasoning',
      'summary': [
        {'text': '**Plan** the fix'},
      ],
    });
    expect(reasoning?.label, 'Plan the fix');
    expect(mapper.map({'type': 'userMessage'}), isNull);
  });
}
