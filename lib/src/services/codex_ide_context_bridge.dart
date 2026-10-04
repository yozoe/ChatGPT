import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:chatgpt/src/domain/codex_ide_context.dart';
import 'app_storage_scope.dart';
import 'codex_ide_context_host_transport.dart';

/// Receives explicit IDE context snapshots from a cooperating host.
class CodexIdeContextBridge extends ChangeNotifier {
  CodexIdeContextBridge({MethodChannel? channel, Directory? discoveryDirectory})
    : _channel = channel ?? const MethodChannel('codex_desk/ide_context'),
      _discoveryDirectory =
          discoveryDirectory ?? AppStorageScope.defaultDirectory() {
    _hostTransport = CodexIdeContextHostTransport(
      onUpdate: _applyContext,
      discoveryDirectory: _discoveryDirectory,
    );
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;
  final Directory _discoveryDirectory;
  late final CodexIdeContextHostTransport _hostTransport;
  CodexIdeContext _context = const CodexIdeContext();

  CodexIdeContext get context => _context;
  bool get isConnected => _context.isAvailable;

  /// Starts the localhost bridge used by a real IDE host such as VS Code.
  /// The discovery file contains only a loopback endpoint and a per-process
  /// bearer token; it is removed when the app disposes the bridge.
  Future<void> startExternalHostTransport() => _hostTransport.start();

  /// Stops the localhost bridge and removes its discovery record.
  Future<void> stopExternalHostTransport() => _hostTransport.stop();

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'updateContext') return null;
    _applyContext(call.arguments);
    return null;
  }

  void _applyContext(Object? value) {
    final next = CodexIdeContext.fromJson(value);
    if (mapEquals(next.toJson(), _context.toJson())) return;
    _context = next;
    notifyListeners();
  }

  Map<String, dynamic>? get additionalContext {
    if (!isConnected) return null;
    return {
      'ide': {'kind': 'application', 'value': jsonEncode(_context.toJson())},
    };
  }

  @override
  void dispose() {
    unawaited(stopExternalHostTransport());
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
