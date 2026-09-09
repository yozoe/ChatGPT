/// 规范化 App Server 线程生命周期值，供控制器判断运行中与终态。
/// Normalizes App Server thread lifecycle values for controller decisions.
class CodexThreadLifecycle {
  bool isTerminalStatus(String? status) {
    return switch (_normalized(status)) {
      'idle' ||
      'completed' ||
      'complete' ||
      'done' ||
      'success' ||
      'failed' ||
      'error' ||
      'systemerror' ||
      'interrupted' ||
      'cancelled' ||
      'canceled' => true,
      _ => false,
    };
  }

  bool isRunningStatus(String? status) {
    final value = _normalized(status);
    return value == 'active' || value == 'inprogress' || value == 'running';
  }

  String _normalized(String? status) =>
      status?.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') ?? '';
}
