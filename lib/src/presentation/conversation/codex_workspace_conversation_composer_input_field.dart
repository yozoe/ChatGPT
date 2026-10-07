import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class ComposerPanelInputField extends StatelessWidget {
  const ComposerPanelInputField({
    super.key,
    required this.composer,
    required this.enabled,
    required this.goalMode,
    required this.showComposerMenu,
    required this.canSteer,
    required this.codeReviewOptionsVisible,
    required this.mcpStatusVisible,
    required this.contextMenuBuilder,
    required this.onMoveMenuSelection,
    required this.onSelectFocusedMenuItem,
    required this.onTogglePlanMode,
    required this.onEscape,
    required this.onReviewUncommittedChanges,
    required this.onDismissMcpStatus,
    required this.onSubmitFromKeyboard,
    required this.onPasteFromClipboard,
  });

  final TextEditingController composer;
  final bool enabled;
  final bool goalMode;
  final bool showComposerMenu;
  final bool canSteer;
  final bool codeReviewOptionsVisible;
  final bool mcpStatusVisible;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final void Function(int delta) onMoveMenuSelection;
  final VoidCallback onSelectFocusedMenuItem;
  final VoidCallback onTogglePlanMode;
  final VoidCallback onEscape;
  final Future<void> Function() onReviewUncommittedChanges;
  final VoidCallback onDismissMcpStatus;
  final VoidCallback onSubmitFromKeyboard;
  final Future<void> Function() onPasteFromClipboard;

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return ConstrainedBox(
      key: const Key('composer-field-region'),
      constraints: const BoxConstraints(minHeight: 64, maxHeight: 124),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: composer,
        child: TextField(
          key: const Key('composer-field'),
          controller: composer,
          enabled: enabled,
          contextMenuBuilder: contextMenuBuilder,
          minLines: 2,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          style: TextStyle(color: palette.trace, fontSize: 13),
          decoration: InputDecoration(
            hintText: goalMode ? '描述你的目标，定义可衡量的成果，以获得最佳效果' : '随心输入',
            hintStyle: TextStyle(color: palette.muted),
            filled: false,
            isCollapsed: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        ),
        builder: (context, value, child) {
          final composing = value.composing;
          final imeIsComposing = composing.isValid && !composing.isCollapsed;
          return CallbackShortcuts(
            bindings: {
              if (showComposerMenu)
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    onMoveMenuSelection(1),
              if (showComposerMenu)
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    onMoveMenuSelection(-1),
              if (showComposerMenu)
                const SingleActivator(LogicalKeyboardKey.tab):
                    onSelectFocusedMenuItem,
              if (!showComposerMenu && !canSteer && !goalMode)
                const SingleActivator(LogicalKeyboardKey.tab, shift: true):
                    onTogglePlanMode,
              const SingleActivator(LogicalKeyboardKey.escape): onEscape,
              if (!imeIsComposing && codeReviewOptionsVisible)
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    unawaited(onReviewUncommittedChanges()),
              if (!imeIsComposing &&
                  mcpStatusVisible &&
                  !codeReviewOptionsVisible)
                const SingleActivator(LogicalKeyboardKey.enter):
                    onDismissMcpStatus,
              if (!imeIsComposing &&
                  !showComposerMenu &&
                  !codeReviewOptionsVisible &&
                  !mcpStatusVisible)
                const SingleActivator(LogicalKeyboardKey.enter):
                    onSubmitFromKeyboard,
              if (!imeIsComposing && showComposerMenu)
                const SingleActivator(LogicalKeyboardKey.enter):
                    onSelectFocusedMenuItem,
              const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
                  unawaited(onPasteFromClipboard()),
              const SingleActivator(
                LogicalKeyboardKey.keyV,
                control: true,
              ): () =>
                  unawaited(onPasteFromClipboard()),
            },
            child: child!,
          );
        },
      ),
    );
  }
}
