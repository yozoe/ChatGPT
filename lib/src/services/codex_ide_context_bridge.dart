import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:chatgpt/src/domain/codex_ide_context.dart';

/// Receives explicit IDE context snapshots from a cooperating host.
class CodexIdeContextBridge extends ChangeNotifier {
  CodexIdeContextBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('codex_desk/ide_context') {
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;
  CodexIdeContext _context = const CodexIdeContext();

  CodexIdeContext get context => _context;
  bool get isConnected => _context.isAvailable;

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'updateContext') return null;
    final next = CodexIdeContext.fromJson(call.arguments);
    if (mapEquals(next.toJson(), _context.toJson())) return null;
    _context = next;
    notifyListeners();
    return null;
  }

  Map<String, dynamic>? get additionalContext {
    if (!isConnected) return null;
    return {
      'ide': {'kind': 'application', 'value': jsonEncode(_context.toJson())},
    };
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
