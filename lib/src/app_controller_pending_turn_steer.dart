// Extracted class from app_controller.dart.
import 'package:chatgpt/src/services/codex_app_server.dart';

/// Composer 已提交但尚未发送给 App Server 的临时方向调整；它仅存在于当前
/// 界面，在 `turn/steer` 成功前不会写入对话历史。
/// A composer direction change retained locally until it can be sent to App
/// Server. It is not persisted in conversation history before `turn/steer`
/// succeeds.
class PendingTurnSteer {
  const PendingTurnSteer({
    required this.displayText,
    required this.prompt,
    this.goal,
    this.planMode = false,
    this.additionalInput = const [],
    this.imagePaths = const [],
  });

  final String displayText;
  final String prompt;
  final String? goal;
  final bool planMode;
  final List<JsonMap> additionalInput;
  final List<String> imagePaths;
}
