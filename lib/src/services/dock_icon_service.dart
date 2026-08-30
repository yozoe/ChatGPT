import 'package:flutter/services.dart';

/// Requests immediate macOS Dock-icon changes from the desktop host.
class DockIconService {
  DockIconService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'codex_desk/dock_icon';
  final MethodChannel _channel;

  /// Switches the visible Dock icon without requiring an application restart.
  Future<bool> select(String icon) async {
    try {
      return await _channel.invokeMethod<bool>('setDockIcon', <String, String>{
            'icon': icon,
          }) ??
          false;
    } on MissingPluginException {
      // Desktop-host integration is unavailable on non-macOS platforms.
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Reads the icon saved by the desktop host, if that host is available.
  Future<String?> selected() async {
    try {
      return await _channel.invokeMethod<String>('getDockIcon');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
