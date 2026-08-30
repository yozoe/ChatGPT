/// A hook discovered by the running Codex App Server.
class CodexHook {
  const CodexHook({
    required this.key,
    required this.eventName,
    required this.handlerType,
    required this.source,
    required this.sourcePath,
    required this.enabled,
    required this.trustStatus,
    required this.currentHash,
    this.command,
    this.timeoutSec,
    this.statusMessage,
    this.pluginId,
  });

  final String key;
  final String eventName;
  final String handlerType;
  final String source;
  final String sourcePath;
  final bool enabled;
  final String trustStatus;
  final String currentHash;
  final String? command;
  final int? timeoutSec;
  final String? statusMessage;
  final String? pluginId;

  bool get isTrusted => trustStatus == 'trusted';
}
