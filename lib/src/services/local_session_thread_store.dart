import 'dart:convert';
import 'dart:io';

import '../domain/codex_thread.dart';

/// 从本机 Codex session 文件中读取指定工作区的线程元数据。
/// Reads thread metadata for a workspace from local Codex session files.
class LocalSessionThreadStore {
  /// 创建本地 session 读取器；测试可提供独立的 session 根目录。
  /// Creates a local session reader; tests can provide an isolated session root.
  LocalSessionThreadStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  /// 列出工作区的非归档 session，并按最后修改时间倒序排列。
  /// Lists non-archived workspace sessions ordered by last modification time.
  Future<List<CodexThread>> listThreads(String workspace) async {
    final directory = _directory ?? _defaultDirectory();
    if (!await directory.exists()) return const [];

    final threads = <String, CodexThread>{};
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final thread = await _threadFromFile(entity, workspace);
      if (thread != null) threads[thread.id] = thread;
    }
    return threads.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  /// 从 session 文件的首条元数据记录提取一个可恢复的线程。
  /// Extracts a resumable thread from the first metadata record in a session file.
  Future<CodexThread?> _threadFromFile(File file, String workspace) async {
    try {
      final firstLine = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final decoded = jsonDecode(firstLine);
      if (decoded is! Map || decoded['type'] != 'session_meta') return null;
      final payload = decoded['payload'];
      if (payload is! Map || payload['cwd']?.toString() != workspace) {
        return null;
      }
      final id = payload['session_id']?.toString() ?? payload['id']?.toString();
      if (id == null || id.isEmpty) return null;
      final createdAt = DateTime.tryParse(
        payload['timestamp']?.toString() ?? '',
      );
      final modifiedAt = await file.lastModified();
      return CodexThread(
        id: id,
        preview: payload['summary']?.toString() ?? '本地会话',
        createdAt: (createdAt ?? modifiedAt).millisecondsSinceEpoch,
        updatedAt: modifiedAt.millisecondsSinceEpoch,
        modelProvider: payload['model_provider']?.toString(),
        model: payload['model']?.toString(),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on StateError {
      return null;
    }
  }

  /// 返回默认的未归档 Codex session 根目录。
  /// Returns the default root directory for non-archived Codex sessions.
  Directory _defaultDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('无法确定 macOS 用户目录。');
    }
    return Directory('$home/.codex/sessions');
  }
}
