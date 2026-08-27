// Extracted class from local_session_thread_store.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:chatgpt/src/domain/codex_thread.dart';
import 'local_session_thread_store_support.dart';
import 'local_session_thread_store_cached_threads.dart';

class LocalSessionThreadStore {
  /// 创建本地 session 读取器；测试可提供独立的 session 根目录。
  /// Creates a local session reader; tests can provide an isolated session root.
  LocalSessionThreadStore({
    Directory? directory,
    Duration cacheDuration = const Duration(seconds: 10),
  }) : _directory = directory,
       _cacheDuration = cacheDuration;

  final Directory? _directory;
  final Duration _cacheDuration;
  final Map<String, CachedThreads> _cachedThreads = {};
  final Map<String, Future<List<CodexThread>>> _pendingLoads = {};

  static const _metadataReadLimit = 128 * 1024;

  /// 列出工作区的非归档 session，并按最后修改时间倒序排列。
  /// Lists non-archived workspace sessions ordered by last modification time.
  Future<List<CodexThread>> listThreads(String workspace) async {
    final cached = _cachedThreads[workspace];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) < _cacheDuration) {
      return cached.threads;
    }
    final pending = _pendingLoads[workspace];
    if (pending != null) return pending;

    final load = _loadThreads(workspace);
    _pendingLoads[workspace] = load;
    return load;
  }

  /// 扫描 session 目录并更新指定工作区的短期线程缓存。
  /// Scans the session directory and refreshes the short-lived workspace cache.
  Future<List<CodexThread>> _loadThreads(String workspace) async {
    final directory = _directory ?? _defaultDirectory();
    try {
      if (!await directory.exists()) return const [];

      final threads = <String, CodexThread>{};
      await for (final entity in directory.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
        final thread = await _threadFromFile(entity, workspace);
        if (thread != null) threads[thread.id] = thread;
      }
      final result = threads.values.toList(growable: false)
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      _cachedThreads[workspace] = CachedThreads(
        threads: result,
        loadedAt: DateTime.now(),
      );
      return result;
    } finally {
      _pendingLoads.remove(workspace);
    }
  }

  /// 从 session 文件的首条元数据记录提取一个可恢复的线程。
  /// Extracts a resumable thread from the first metadata record in a session file.
  Future<CodexThread?> _threadFromFile(File file, String workspace) async {
    try {
      final prefix = await _metadataPrefix(file);
      if (!RegExp(r'"type"\s*:\s*"session_meta"').hasMatch(prefix)) {
        return null;
      }
      final cwd = _jsonStringValue(prefix, 'cwd');
      if (cwd != workspace) return null;
      final id =
          _jsonStringValue(prefix, 'session_id') ??
          _jsonStringValue(prefix, 'id');
      if (id == null || id.isEmpty) return null;
      final createdAt = DateTime.tryParse(
        _jsonStringValue(prefix, 'timestamp') ?? '',
      );
      final modifiedAt = await file.lastModified();
      return CodexThread(
        id: id,
        preview: _jsonStringValue(prefix, 'summary') ?? '本地会话',
        createdAt: (createdAt ?? modifiedAt).millisecondsSinceEpoch,
        updatedAt: modifiedAt.millisecondsSinceEpoch,
        modelProvider: _jsonStringValue(prefix, 'model_provider'),
        model: _jsonStringValue(prefix, 'model'),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on StateError {
      return null;
    }
  }

  /// 读取 session 元数据所在的文件前缀，避免解码整条超大首行。
  /// Reads the metadata prefix without decoding the entire oversized first line.
  Future<String> _metadataPrefix(File file) async {
    final bytes = await file
        .openRead(0, _metadataReadLimit)
        .fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (buffer, chunk) => buffer..add(chunk),
        );
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  /// 从 JSON 文件前缀中读取一个字符串字段，并正确处理转义字符。
  /// Reads a string field from a JSON file prefix while decoding escapes correctly.
  String? _jsonStringValue(String source, String key) {
    final match = RegExp(
      '"${RegExp.escape(key)}"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"',
    ).firstMatch(source);
    if (match == null) return null;
    try {
      return jsonDecode('"${match.group(1)}"') as String;
    } on FormatException {
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
