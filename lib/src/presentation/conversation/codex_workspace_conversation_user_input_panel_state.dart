// Extracted class from codex_workspace_conversation.dart.
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_user_input_panel.dart';

/// Owns selections and free-form answers for a structured Codex question card.
class UserInputPanelState extends State<UserInputPanel> {
  static const otherAnswer = '__codex_other_answer__';
  static const _visibleCountdown = Duration(seconds: 20);
  final Map<String, String> _selectedAnswers = {};
  final Map<String, TextEditingController> _textControllers = {};
  Timer? _countdownTicker;
  Timer? _advanceTimer;
  int _questionIndex = 0;

  @override
  void initState() {
    super.initState();
    for (final question in widget.request.questions) {
      if (question.options.isNotEmpty && widget.initiallySelectFirstOption) {
        _selectedAnswers[question.id] = question.options.first.label;
      }
      if (question.options.isEmpty || question.allowsOther) {
        _textControllers[question.id] = TextEditingController();
      }
    }
    _syncCountdownTicker();
  }

  @override
  void didUpdateWidget(covariant UserInputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoResolutionDeadline != widget.autoResolutionDeadline) {
      _syncCountdownTicker();
    }
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _advanceTimer?.cancel();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      widget.enabled &&
      widget.request.questions.every((q) {
        if (q.options.isEmpty) {
          return _textControllers[q.id]!.text.trim().isNotEmpty;
        }
        final selected = _selectedAnswers[q.id];
        if (selected == null) return false;
        return selected != otherAnswer ||
            _textControllers[q.id]!.text.trim().isNotEmpty;
      });

  JsonMap _answers() => {
    for (final question in widget.request.questions)
      question.id: {
        'answers': [
          if (question.options.isEmpty)
            _textControllers[question.id]!.text.trim()
          else if (_selectedAnswers[question.id] == otherAnswer)
            _textControllers[question.id]!.text.trim()
          else
            _selectedAnswers[question.id]!,
        ],
      },
  };

  List<PendingUserInputAnswer> _answerDetails() => [
    for (final question in widget.request.questions)
      PendingUserInputAnswer(
        questionId: question.id,
        selectedOptionId:
            question.options.isNotEmpty &&
                _selectedAnswers[question.id] != otherAnswer
            ? _selectedAnswers[question.id]
            : null,
        freeformText:
            question.options.isEmpty ||
                _selectedAnswers[question.id] == otherAnswer
            ? _textControllers[question.id]!.text.trim()
            : null,
      ),
  ];

  Future<void> _submit() async {
    if (!_canSubmit) return;
    await widget.onSubmit(_answers(), _answerDetails());
  }

  void _advanceOrSubmit() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    if (_questionIndex < widget.request.questions.length - 1) {
      setState(() => _questionIndex++);
      return;
    }
    unawaited(_submit());
  }

  void _selectOption(PendingUserInputQuestion question, String value) {
    _registerUserInteraction();
    _advanceTimer?.cancel();
    setState(() => _selectedAnswers[question.id] = value);
    if (value != otherAnswer) {
      _advanceTimer = Timer(
        const Duration(milliseconds: 180),
        _advanceOrSubmit,
      );
    }
  }

  void _showQuestion(int index) {
    _registerUserInteraction();
    _advanceTimer?.cancel();
    _advanceTimer = null;
    setState(() => _questionIndex = index);
  }

  void _registerUserInteraction() {
    widget.onUserInteraction?.call();
  }

  void _syncCountdownTicker() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    if (widget.autoResolutionDeadline == null) return;
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  int? get _visibleCountdownSeconds {
    final deadline = widget.autoResolutionDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    if (remaining > _visibleCountdown) return null;
    return math.max(0, (remaining.inMilliseconds / 1000).ceil());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      unawaited(widget.onDismiss());
      return KeyEventResult.handled;
    }
    if (primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft && _questionIndex > 0) {
      _registerUserInteraction();
      _advanceTimer?.cancel();
      setState(() => _questionIndex--);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        _questionIndex < widget.request.questions.length - 1) {
      _registerUserInteraction();
      _advanceTimer?.cancel();
      setState(() => _questionIndex++);
      return KeyEventResult.handled;
    }
    final question = widget.request.questions[_questionIndex];
    if ((key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) &&
        question.options.isNotEmpty) {
      final selected = _selectedAnswers[question.id];
      final selectedIndex = question.options.indexWhere(
        (option) => option.label == selected,
      );
      if (key == LogicalKeyboardKey.arrowDown &&
          question.allowsOther &&
          selectedIndex == question.options.length - 1) {
        _selectOption(question, otherAnswer);
        return KeyEventResult.handled;
      }
      final nextIndex = key == LogicalKeyboardKey.arrowDown
          ? math.min(question.options.length - 1, selectedIndex + 1)
          : math.max(
              0,
              selected == otherAnswer
                  ? question.options.length - 1
                  : selectedIndex - 1,
            );
      _selectOption(question, question.options[nextIndex].label);
      return KeyEventResult.handled;
    }
    final digit = int.tryParse(event.character ?? '');
    if (digit != null && digit > 0 && digit <= question.options.length) {
      _selectOption(question, question.options[digit - 1].label);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && _currentQuestionAnswered) {
      _registerUserInteraction();
      _advanceOrSubmit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final question = widget.request.questions[_questionIndex];
    final hasMultipleQuestions = widget.request.questions.length > 1;
    final maximumCardHeight = math.min(
      440.0,
      math.max(220.0, MediaQuery.sizeOf(context).height * 0.48),
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          key: const Key('user-input-panel'),
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: maximumCardHeight,
          ),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.controlBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question.question,
                          key: ValueKey('user-input-question-${question.id}'),
                          style: TextStyle(
                            color: palette.trace,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasMultipleQuestions) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '上一个问题',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: _questionIndex == 0
                          ? null
                          : () => _showQuestion(_questionIndex - 1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      '${_questionIndex + 1} of ${widget.request.questions.length}',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                    IconButton(
                      tooltip: '下一个问题',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed:
                          _questionIndex == widget.request.questions.length - 1
                          ? null
                          : () => _showQuestion(_questionIndex + 1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                  if (_visibleCountdownSeconds case final seconds?) ...[
                    const SizedBox(width: 4),
                    Container(
                      key: const Key('user-input-dismiss-countdown'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: palette.signal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${seconds}s',
                        style: TextStyle(
                          color: palette.signal,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  IconButton(
                    key: const Key('user-input-dismiss'),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: widget.enabled ? widget.onDismiss : null,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (widget.taskLabel case final label?) ...[
                const SizedBox(height: 5),
                Text(
                  '来自后台任务：$label',
                  style: TextStyle(color: palette.signal, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  key: const Key('user-input-scroll'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_buildQuestion(question)],
                  ),
                ),
              ),
              if (question.options.isEmpty ||
                  _selectedAnswers[question.id] == otherAnswer) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('user-input-submit'),
                    onPressed: _currentQuestionAnswered
                        ? () {
                            _registerUserInteraction();
                            _advanceOrSubmit();
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.field,
                      foregroundColor: palette.trace,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      minimumSize: Size.zero,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _questionIndex == widget.request.questions.length - 1
                              ? '提交'
                              : '继续',
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          '↵',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _currentQuestionAnswered {
    final question = widget.request.questions[_questionIndex];
    if (question.options.isEmpty) {
      return _textControllers[question.id]!.text.trim().isNotEmpty;
    }
    final selected = _selectedAnswers[question.id];
    return selected != null &&
        (selected != otherAnswer ||
            _textControllers[question.id]!.text.trim().isNotEmpty);
  }

  Widget _buildQuestion(PendingUserInputQuestion question) {
    final selected = _selectedAnswers[question.id];
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.options.isNotEmpty) ...[
            for (final (index, option) in question.options.indexed)
              _buildOption(
                question,
                option.label,
                option.description,
                index: index,
              ),
            if (question.allowsOther)
              _buildOption(question, otherAnswer, widget.otherDescription),
          ],
          if (question.options.isEmpty || selected == otherAnswer) ...[
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('user-input-text-${question.id}'),
              controller: _textControllers[question.id],
              enabled: widget.enabled,
              obscureText: question.isSecret,
              autocorrect: !question.isSecret,
              enableSuggestions: !question.isSecret,
              enableIMEPersonalizedLearning: !question.isSecret,
              maxLines: question.isSecret ? 1 : 3,
              minLines: 1,
              onChanged: (_) {
                _registerUserInteraction();
                setState(() {});
              },
              onSubmitted: (_) {
                if (_currentQuestionAnswered) _advanceOrSubmit();
              },
              decoration: InputDecoration(
                hintText: widget.textFieldHint,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOption(
    PendingUserInputQuestion question,
    String value,
    String description, {
    int? index,
  }) {
    final palette = YeknomPalette.of(context);
    final selected = _selectedAnswers[question.id] == value;
    final label = value == otherAnswer ? widget.otherLabel : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: ValueKey('user-input-option-${question.id}-$value'),
          onTap: widget.enabled ? () => _selectOption(question, value) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? palette.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? palette.signal : palette.muted,
                    ),
                  ),
                  child: selected
                      ? Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: palette.signal,
                            shape: BoxShape.circle,
                          ),
                        )
                      : Text(
                          index == null ? '·' : '${index + 1}',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 10,
                            height: 1,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: palette.trace,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        description,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
