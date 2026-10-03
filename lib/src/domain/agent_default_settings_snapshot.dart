import 'agent_setting_field.dart';
import 'agent_setting_availability.dart';

/// Non-sensitive, display-only snapshot of Codex agent defaults.
///
/// A missing key means the runtime did not expose the field. A present null
/// means the runtime exposed it and it inherits a lower layer or model
/// default. Neither state is treated as an editable value.
class AgentDefaultSettingsSnapshot {
  const AgentDefaultSettingsSnapshot({
    required this.approvalPolicy,
    required this.sandboxMode,
    required this.webSearch,
    required this.modelVerbosity,
    required this.reasoningSummary,
    required this.sources,
    required this.userConfigVersion,
    this.profile,
    this.profileSource,
  });

  factory AgentDefaultSettingsSnapshot.fromConfig(
    Map<String, Object?> config,
    Object? origins, [
    Object? layers,
  ]) {
    String? read(List<String> keys) {
      for (final key in keys) {
        if (config.containsKey(key)) return config[key]?.toString();
      }
      return null;
    }

    AgentSettingAvailability availability(List<String> keys) {
      for (final key in keys) {
        if (config.containsKey(key)) {
          return config[key] == null
              ? AgentSettingAvailability.inherited
              : AgentSettingAvailability.explicit;
        }
      }
      return AgentSettingAvailability.missing;
    }

    String? source(List<String> keys) {
      if (origins is! Map) return null;
      for (final key in keys) {
        Object? value = origins[key];
        if (value == null) {
          for (final entry in origins.entries) {
            final name = entry.key.toString();
            if (name == key ||
                name.endsWith('/$key') ||
                name.endsWith('.$key')) {
              value = entry.value;
              break;
            }
          }
        }
        if (value is Map) {
          final name = value['name'];
          if (name is Map) {
            final type = name['type']?.toString();
            final file = name['file']?.toString().trim();
            return switch (type) {
              'user' when file != null && file.isNotEmpty => file,
              'project' => '项目配置',
              'sessionFlags' => '运行时启动参数',
              'packagedDefaults' => 'Codex 内置默认值',
              'mdm' || 'enterpriseManaged' => '组织管理配置',
              _ => type,
            };
          }
        }
      }
      return null;
    }

    int? userVersion() {
      if (layers is! Iterable) return null;
      for (final rawLayer in layers) {
        if (rawLayer is! Map) continue;
        final rawName = rawLayer['name'];
        final type = rawName is Map
            ? rawName['type']?.toString()
            : rawName?.toString();
        if (type != 'user') continue;
        final rawVersion = rawLayer['version'];
        if (rawVersion is int) return rawVersion;
        final parsed = int.tryParse(rawVersion?.toString() ?? '');
        if (parsed != null) return parsed;
      }
      return null;
    }

    const approvalKeys = ['approval_policy', 'approvalPolicy'];
    const sandboxKeys = ['sandbox_mode', 'sandboxMode'];
    const webSearchKeys = ['web_search', 'webSearch'];
    const verbosityKeys = ['model_verbosity', 'modelVerbosity'];
    const summaryKeys = ['model_reasoning_summary', 'modelReasoningSummary'];
    const profileKeys = ['profile', 'profile_name', 'profileName'];
    return AgentDefaultSettingsSnapshot(
      approvalPolicy: AgentSettingField(
        availability: availability(approvalKeys),
        value: read(approvalKeys),
        source: source(approvalKeys),
      ),
      sandboxMode: AgentSettingField(
        availability: availability(sandboxKeys),
        value: read(sandboxKeys),
        source: source(sandboxKeys),
      ),
      webSearch: AgentSettingField(
        availability: availability(webSearchKeys),
        value: read(webSearchKeys),
        source: source(webSearchKeys),
      ),
      modelVerbosity: AgentSettingField(
        availability: availability(verbosityKeys),
        value: read(verbosityKeys),
        source: source(verbosityKeys),
      ),
      reasoningSummary: AgentSettingField(
        availability: availability(summaryKeys),
        value: read(summaryKeys),
        source: source(summaryKeys),
      ),
      sources: {
        'approval_policy': source(approvalKeys),
        'sandbox_mode': source(sandboxKeys),
        'web_search': source(webSearchKeys),
        'model_verbosity': source(verbosityKeys),
        'model_reasoning_summary': source(summaryKeys),
      },
      userConfigVersion: userVersion(),
      profile: read(profileKeys),
      profileSource: source(profileKeys),
    );
  }

  static const empty = AgentDefaultSettingsSnapshot(
    approvalPolicy: AgentSettingField(
      availability: AgentSettingAvailability.missing,
      value: null,
      source: null,
    ),
    sandboxMode: AgentSettingField(
      availability: AgentSettingAvailability.missing,
      value: null,
      source: null,
    ),
    webSearch: AgentSettingField(
      availability: AgentSettingAvailability.missing,
      value: null,
      source: null,
    ),
    modelVerbosity: AgentSettingField(
      availability: AgentSettingAvailability.missing,
      value: null,
      source: null,
    ),
    reasoningSummary: AgentSettingField(
      availability: AgentSettingAvailability.missing,
      value: null,
      source: null,
    ),
    sources: {},
    userConfigVersion: null,
    profile: null,
    profileSource: null,
  );

  final AgentSettingField approvalPolicy;
  final AgentSettingField sandboxMode;
  final AgentSettingField webSearch;
  final AgentSettingField modelVerbosity;
  final AgentSettingField reasoningSummary;
  final Map<String, String?> sources;
  final int? userConfigVersion;

  /// The effective profile name when the runtime exposes one.
  /// 运行时暴露 profile 时的最终 profile 名称。
  final String? profile;

  /// The configuration origin for the effective profile.
  /// 最终 profile 的配置来源。
  final String? profileSource;

  String displayValue(AgentSettingField field, {String inherited = '继承默认值'}) {
    return switch (field.availability) {
      AgentSettingAvailability.missing => '由配置管理',
      AgentSettingAvailability.inherited => inherited,
      AgentSettingAvailability.explicit => field.value ?? '已配置',
    };
  }
}
