import 'agent_setting_availability.dart';

/// One non-sensitive Codex setting and the evidence available for it.
class AgentSettingField {
  const AgentSettingField({
    required this.availability,
    required this.value,
    required this.source,
    this.rawValue,
  });

  final AgentSettingAvailability availability;
  final String? value;
  final String? source;

  /// The non-sensitive protocol value before display normalization.
  /// Granular objects are retained for diagnostics but are not offered as
  /// editable enum values until the runtime schema is explicitly supported.
  final Object? rawValue;

  /// A field is writable only when the runtime exposed it in config/read.
  /// Missing fields remain read-only until a later runtime advertises them.
  bool get isRuntimeExposed => availability != AgentSettingAvailability.missing;

  bool get isScalarValue =>
      rawValue == null ||
      rawValue is String ||
      rawValue is num ||
      rawValue is bool;
}
