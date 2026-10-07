import 'package:chatgpt/src/app_controller_browser_invocation_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps handled IDs, queued URLs, and the session grant together', () {
    final state = CodexBrowserInvocationState()
      ..handledInvocationIds.add('call-1')
      ..queuedInvocations.add('https://example.com')
      ..allowAllSites = true;

    expect(state.handledInvocationIds, {'call-1'});
    expect(state.queuedInvocations, ['https://example.com']);
    expect(state.allowAllSites, isTrue);
  });

  test('clear removes only session-scoped browser invocation state', () {
    final state = CodexBrowserInvocationState()
      ..handledInvocationIds.add('call-1')
      ..queuedInvocations.add('https://example.com')
      ..allowAllSites = true;

    state.clear();

    expect(state.handledInvocationIds, isEmpty);
    expect(state.queuedInvocations, isEmpty);
    expect(state.allowAllSites, isFalse);
  });
}
