// Extracted class from app_controller.dart.
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'app_controller_support.dart';

class TurnSubmission {
  TurnSubmission({
    required this.workspace,
    required this.threadId,
    required this.prompt,
    required List<JsonMap> additionalInput,
    required JsonMap? additionalContext,
    required this.goal,
    required JsonMap? collaborationMode,
    required List<String> imagePaths,
  }) : additionalInput = List.unmodifiable(
         additionalInput.map((item) => cloneJsonMap(item)),
       ),
       additionalContext = additionalContext == null
           ? null
           : cloneJsonMap(additionalContext),
       collaborationMode = collaborationMode == null
           ? null
           : cloneJsonMap(collaborationMode),
       imagePaths = List.unmodifiable(imagePaths);

  final String workspace;
  final String threadId;
  final String prompt;
  final List<JsonMap> additionalInput;
  final JsonMap? additionalContext;
  final String? goal;
  final JsonMap? collaborationMode;
  final List<String> imagePaths;
}
