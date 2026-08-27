// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';

class ComposerModelControls extends StatelessWidget {
  const ComposerModelControls({
    required this.controller,
    required this.compact,
  });

  final CodexController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final modelEnabled = controller.canSelectModel;
    final effortEnabled = controller.canSelectReasoningEffort;
    final selectionError = controller.modelSelectionError;
    final contentColor = selectionError != null
        ? palette.fault
        : modelEnabled
        ? palette.trace
        : palette.muted;
    final modelWidth = compact ? 88.0 : 152.0;
    final effortWidth = compact ? 58.0 : 76.0;
    return Container(
      key: const Key('composer-model-controls'),
      height: 34,
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            key: const Key('model-selector'),
            enabled: modelEnabled,
            padding: EdgeInsets.zero,
            tooltip:
                selectionError ?? '切换后续新任务的模型：${controller.selectedModelLabel}',
            onSelected: (value) {
              unawaited(controller.setModel(value.isEmpty ? null : value));
            },
            itemBuilder: (context) => [
              if (selectionError != null)
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(selectionError),
                ),
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('仅影响后续新任务'),
              ),
              CheckedPopupMenuItem(
                key: const Key('model-option-follow-config'),
                value: '',
                checked: controller.selectedModelId == null,
                child: const Text('默认'),
              ),
              ...controller.modelOptions.map(
                (option) => CheckedPopupMenuItem(
                  key: ValueKey('model-option-${option.id}'),
                  value: option.id,
                  checked: controller.selectedModelId == option.id,
                  child: Text(option.displayName),
                ),
              ),
            ],
            child: SizedBox(
              width: modelWidth,
              height: 32,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.newTaskModelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: contentColor),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 15, color: palette.muted),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<ReasoningEffort>(
            key: const Key('reasoning-effort-selector'),
            enabled: effortEnabled,
            padding: EdgeInsets.zero,
            tooltip:
                selectionError ??
                '切换后续新任务的推理强度：${controller.reasoningEffort.label}',
            onSelected: (value) {
              unawaited(controller.setReasoningEffort(value));
            },
            itemBuilder: (context) => controller.reasoningEffortOptions
                .map(
                  (effort) => CheckedPopupMenuItem(
                    key: ValueKey('reasoning-option-${effort.name}'),
                    value: effort,
                    checked: controller.reasoningEffort == effort,
                    child: Text(effort.label),
                  ),
                )
                .toList(growable: false),
            child: SizedBox(
              width: effortWidth,
              height: 32,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        controller.reasoningEffort.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: contentColor),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 15, color: palette.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
