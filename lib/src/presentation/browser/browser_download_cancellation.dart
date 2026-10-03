import 'dart:async';

/// Cancellation signal shared by the browser download UI and its HTTP layer.
class BrowserDownloadCancellation {
  final Completer<void> _completer = Completer<void>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}
