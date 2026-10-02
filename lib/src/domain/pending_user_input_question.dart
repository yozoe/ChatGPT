import 'pending_user_input_option.dart';

/// One structured question in an App Server `request_user_input` request.
class PendingUserInputQuestion {
  const PendingUserInputQuestion({
    required this.id,
    required this.header,
    required this.question,
    required this.options,
    required this.allowsOther,
    required this.isSecret,
  });

  final String id;
  final String header;
  final String question;
  final List<PendingUserInputOption> options;
  final bool allowsOther;
  final bool isSecret;
}
