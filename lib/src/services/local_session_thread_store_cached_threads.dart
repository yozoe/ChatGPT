// Extracted class from local_session_thread_store.dart.
import 'package:chatgpt/src/domain/codex_thread.dart';

class CachedThreads {
  /// 创建带有加载时间的缓存条目。
  /// Creates a cache entry with its load timestamp.
  const CachedThreads({required this.threads, required this.loadedAt});

  final List<CodexThread> threads;
  final DateTime loadedAt;
}
