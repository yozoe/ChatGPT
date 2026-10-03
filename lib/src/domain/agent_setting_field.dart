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

  /// A field is writable only when the runtime exposed it in config/read.
  /// Missing fields remain read-only until a later runtime advertises them.
  bool get isRuntimeExposed => availability != AgentSettingAvailability.missing;
}
