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
      'profile': 'work',
    }, null);

    expect(snapshot.modelVerbosity.value, 'high');
    expect(snapshot.reasoningSummary.value, 'concise');
    expect(snapshot.profile, 'work');
    expect(snapshot.profileSource, isNull);
    expect(snapshot.sources, containsPair('model_verbosity', isNull));
  });

  test('keeps the user layer version for optimistic config writes', () {
    final snapshot = AgentDefaultSettingsSnapshot.fromConfig(
      {'sandbox_mode': 'read-only'},
      const {},
      [
        {
          'name': {'type': 'system'},
          'version': 2,
        },
        {
          'name': {'type': 'user'},
          'version': 7,
        },
      ],
    );

    expect(snapshot.userConfigVersion, 7);
  });

  test(
    'retains granular policy values without presenting them as scalar enums',
    () {
      final snapshot = AgentDefaultSettingsSnapshot.fromConfig({
        'approval_policy': {'type': 'granular', 'network': 'on-request'},
      }, null);

      expect(
        snapshot.approvalPolicy.availability,
        AgentSettingAvailability.explicit,
      );
      expect(snapshot.approvalPolicy.isScalarValue, isFalse);
      expect(snapshot.approvalPolicy.value, contains('granular'));
    },
  );
}
