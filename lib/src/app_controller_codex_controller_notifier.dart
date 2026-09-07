// Extracted class from app_controller.dart.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_controller_codex_controller.dart';

/// 将既有控制器的状态变更桥接为 Riverpod 状态更新。
/// Bridges existing controller changes into Riverpod state updates.
class CodexControllerNotifier extends Notifier<CodexController> {
  late final CodexController _controller;

  @override
  CodexController build() {
    _controller = CodexController();
    _controller.addListener(_publishControllerChange);
    unawaited(_controller.connectRestoredWorkspace());
    ref.onDispose(() {
      _controller.removeListener(_publishControllerChange);
      _controller.dispose();
    });
    return _controller;
  }

  void _publishControllerChange() => state = _controller;

  @override
  bool updateShouldNotify(CodexController previous, CodexController next) =>
      true;
}
