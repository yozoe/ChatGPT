import 'dart:async';

import 'package:chatgpt/src/services/conversation_attachment_store.dart';

/// 暂停附件持久化，让测试能够覆盖所有权切换的竞态。
/// Pauses attachment persistence so tests can exercise ownership changes.
class DelayedConversationAttachmentStore extends ConversationAttachmentStore {
  DelayedConversationAttachmentStore({required super.directory});

  final Completer<void> persistStarted = Completer<void>();
  final Completer<void> continuePersist = Completer<void>();

  @override
  Future<({Map<String, String> paths, List<String> createdPaths})> persist(
    Iterable<String> paths,
  ) async {
    persistStarted.complete();
    await continuePersist.future;
    return super.persist(paths);
  }
}
