import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;

/// 统一计算应用状态目录，确保 Debug/Profile 不会读取或覆盖 Release 数据。
/// Resolves app-state storage so Debug/Profile never read or overwrite Release data.
abstract final class AppStorageScope {
  static const releaseDirectoryName = 'Codex Desk';
  static const developmentDirectoryName = 'Codex Desk Development';

  /// Debug and profile runs must not share encrypted state with the release app.
  static String get directoryName =>
      kReleaseMode ? releaseDirectoryName : developmentDirectoryName;

  static Directory defaultDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('无法确定 macOS 用户目录。');
    }
    return Directory('$home/Library/Application Support/$directoryName');
  }
}
