// Test double extracted from widget_test.dart.
import 'package:chatgpt/src/services/conversation_history_store.dart';

import 'memory_conversation_history_store.dart';

class FailingConversationHistoryStore extends MemoryConversationHistoryStore {
  /// Rejects every write so callers can verify transactional rollback.
  @override
  Future<void> save({
    required String workspace,
    required ConversationHistorySnapshot snapshot,
  }) async {
    throw StateError('history save failed');
  }
}
