import 'package:chatgpt/src/services/codex_app_server.dart';
import 'pending_user_input_option.dart';
import 'pending_user_input_question.dart';

/// A structured question request emitted by Codex while a turn is running.
class PendingUserInputRequest {
  const PendingUserInputRequest({
    required this.requestId,
    required this.params,
    required this.threadId,
    required this.turnId,
    required this.itemId,
    required this.questions,
    required this.isBlocking,
  });

  final Object requestId;
  final JsonMap params;
  final String threadId;
  final String turnId;
  final String itemId;
  final List<PendingUserInputQuestion> questions;
  final bool isBlocking;

  static PendingUserInputRequest? fromEvent(ServerEvent event) {
    if (event.requestId == null ||
        event.method != 'item/tool/requestUserInput') {
      return null;
    }
    final threadId = event.params['threadId']?.toString().trim() ?? '';
    final turnId = event.params['turnId']?.toString().trim() ?? '';
    final itemId = event.params['itemId']?.toString().trim() ?? '';
    final rawQuestions = event.params['questions'];
    final isBlocking = event.params['isBlocking'];
    if (threadId.isEmpty ||
        turnId.isEmpty ||
        itemId.isEmpty ||
        isBlocking is! bool ||
        rawQuestions is! List ||
        rawQuestions.isEmpty ||
        rawQuestions.length > 3) {
      return null;
    }

    final questions = <PendingUserInputQuestion>[];
    final ids = <String>{};
    for (final rawQuestion in rawQuestions) {
      if (rawQuestion is! Map) return null;
      final id = rawQuestion['id']?.toString().trim() ?? '';
      final header = rawQuestion['header']?.toString().trim() ?? '';
      final prompt = rawQuestion['question']?.toString().trim() ?? '';
      if (id.isEmpty || header.isEmpty || prompt.isEmpty || !ids.add(id)) {
        return null;
      }
      final rawOptions = rawQuestion['options'];
      if (rawOptions != null && rawOptions is! List) return null;
      final options = <PendingUserInputOption>[];
      for (final rawOption in rawOptions as List? ?? const []) {
        if (rawOption is! Map) return null;
        final label = rawOption['label']?.toString().trim() ?? '';
        final description = rawOption['description']?.toString().trim() ?? '';
        if (label.isEmpty) return null;
        options.add(
          PendingUserInputOption(label: label, description: description),
        );
      }
      questions.add(
        PendingUserInputQuestion(
          id: id,
          header: header,
          question: prompt,
          options: List.unmodifiable(options),
          allowsOther: rawQuestion['isOther'] == true,
          isSecret: rawQuestion['isSecret'] == true,
        ),
      );
    }

    return PendingUserInputRequest(
      requestId: event.requestId!,
      params: event.params,
      threadId: threadId,
      turnId: turnId,
      itemId: itemId,
      questions: List.unmodifiable(questions),
      isBlocking: isBlocking,
    );
  }
}
