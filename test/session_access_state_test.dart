import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/app_controller_session_access_state.dart';
import 'package:chatgpt/src/app_controller_support.dart';

void main() {
  test('parses account display fields and authentication mode', () {
    final state = CodexSessionAccessState();

    state.updateFromAccount({
      'authMode': 'chatgpt',
      'planType': 'plus',
      'requiresOpenaiAuth': true,
      'account': {'email': 'user@example.com'},
    });

    expect(state.authStatus, AuthStatus.chatgpt);
    expect(state.accountEmail, 'user@example.com');
    expect(state.accountPlan, 'plus');
    expect(state.requiresOpenaiAuth, isTrue);
  });

  test('keeps the resolved auth requirement when an update omits it', () {
    final state = CodexSessionAccessState()..requiresOpenaiAuth = true;

    state.updateFromAccount({'authMode': 'apikey'});

    expect(state.authStatus, AuthStatus.apiKey);
    expect(state.requiresOpenaiAuth, isTrue);
    expect(state.accountEmail, isNull);
    expect(state.accountPlan, isNull);
  });
}
