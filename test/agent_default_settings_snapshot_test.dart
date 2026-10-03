import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt/src/domain/agent_default_settings_snapshot.dart';
import 'package:chatgpt/src/domain/agent_setting_availability.dart';

void main() {
  test('distinguishes missing, inherited, and explicit config fields', () {
    final snapshot = AgentDefaultSettingsSnapshot.fromConfig(
      {'sandbox_mode': null, 'web_search': 'live'},
      const {
        'web_search': {
          'name': {'type': 'user', 'file': '/tmp/config.toml'},
        },
      },
    );

    expect(
      snapshot.approvalPolicy.availability,
      AgentSettingAvailability.missing,
    );
    expect(
      snapshot.sandboxMode.availability,
      AgentSettingAvailability.inherited,
    );
    expect(snapshot.webSearch.availability, AgentSettingAvailability.explicit);
    expect(snapshot.displayValue(snapshot.sandboxMode), '继承默认值');
    expect(snapshot.displayValue(snapshot.webSearch), 'live');
    expect(snapshot.webSearch.source, '/tmp/config.toml');
  });

  test('accepts camelCase compatibility keys without exposing raw config', () {
    final snapshot = AgentDefaultSettingsSnapshot.fromConfig({
      'modelVerbosity': 'high',
      'modelReasoningSummary': 'concise',
    }, null);

    expect(snapshot.modelVerbosity.value, 'high');
    expect(snapshot.reasoningSummary.value, 'concise');
    expect(snapshot.sources, containsPair('model_verbosity', isNull));
  });
}
