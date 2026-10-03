import 'agent_setting_availability.dart';

/// One non-sensitive Codex setting and the evidence available for it.
class AgentSettingField {
  const AgentSettingField({
    required this.availability,
    required this.value,
    required this.source,
  });

  final AgentSettingAvailability availability;
  final String? value;
  final String? source;
}
