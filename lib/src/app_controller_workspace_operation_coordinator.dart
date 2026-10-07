/// Serializes mutations of the visible workspace and invalidates stale
/// selection requests without owning any workspace state itself.
class CodexWorkspaceOperationCoordinator {
  Future<void> _operationQueue = Future<void>.value();
  int _selectionRequest = 0;
  bool _disposed = false;

  Future<T> serialize<T>(Future<T> Function() action) {
    final previousOperation = _operationQueue;
    final operation = () async {
      try {
        await previousOperation;
      } catch (_) {
        // A failed older operation must not prevent a newer mutation.
      }
      return action();
    }();
    _operationQueue = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<T> runLatest<T>({
    required T staleValue,
    required Future<T> Function(bool Function() isCurrent) action,
  }) {
    final request = ++_selectionRequest;
    bool isCurrent() => !_disposed && request == _selectionRequest;

    return serialize(() {
      if (!isCurrent()) return Future<T>.value(staleValue);
      return action(isCurrent);
    });
  }

  Future<void> waitForIdle() => _operationQueue;

  void dispose() {
    _disposed = true;
    _selectionRequest++;
  }
}
