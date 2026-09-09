// Extracted class from codex_workspace_conversation.dart.
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_pending_turn_steer_queue.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_model_controls.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_activity_pill.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_file_change_pill.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_attachment.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_pasted_text.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_pasted_text_card.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_submission.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_header.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_item.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_message.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_context_chip.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_code_review_options_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_mcp_status_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_slash_command.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_slash_command_menu.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_selected_skill_chip.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_skill_details_dialog.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_context_usage_button.dart';

class ComposerPanelState extends State<ComposerPanel> {
  static const _clipboardFileReader = ClipboardFileReader();
  static const _collapsedPasteCharacterThreshold = 800;
  static const _collapsedPasteLineThreshold = 8;
  final List<ComposerAttachment> _attachments = [];
  final List<ComposerPastedText> _pastedTexts = [];
  final Set<String> _selectedSkillPaths = {};
  final Map<String, Uint8List> _securityBookmarks = {};
  final Set<String> _temporaryAttachmentPaths = {};
  final Map<ComposerSlashCommandKind, GlobalKey> _slashCommandScrollKeys = {};
  final Map<String, GlobalKey> _slashSkillScrollKeys = {};
  bool _draggingFiles = false;
  bool _includeWorkspace = false;
  bool _planMode = false;
  bool _recordSkill = false;
  bool _goalMode = false;
  bool _mcpStatusVisible = false;
  bool _codeReviewOptionsVisible = false;
  bool _codeReviewBranchesLoading = false;
  bool _reviewSubmissionPending = false;
  String? _codeReviewBranchesError;
  List<String> _codeReviewBaseBranches = const [];
  int _codeReviewBranchRequest = 0;
  bool _imeCompositionActive = false;
  bool _imeCompositionJustEnded = false;
  bool _slashMenuDismissed = false;
  int _slashMenuSelectedIndex = 0;
  int _nextPastedTextId = 0;
  String _slashMenuQuery = '';
  Timer? _imeCompositionDeferral;
  late int _handledRecordSkillRequest;
  String? _draftBeforeGoalMode;
  String? _goal;
  String? _goalBeforeGoalMode;

  CodexController get controller => widget.controller;
  TextEditingController get composer => widget.composer;

  List<CodexSkill> get _selectedSkills => controller.skills
      .where(
        (skill) => skill.enabled && _selectedSkillPaths.contains(skill.path),
      )
      .toList(growable: false);

  CodexThread? get _activeComposerThread {
    final activeId = controller.activeThreadId;
    if (activeId == null) return null;
    for (final thread in controller.threads) {
      if (thread.id == activeId) return thread;
    }
    return null;
  }

  bool get _canArchiveActiveThread {
    final thread = _activeComposerThread;
    return thread != null &&
        controller.workspacePath != null &&
        !controller.isThreadExecutionActive(thread) &&
        !controller.isUpdatingThread(thread.id);
  }

  List<CodexSkill> get _slashSkills =>
      controller.skills.where((skill) => skill.enabled).toList(growable: false);

  List<CodexSkill> get _filteredMentionSkills {
    final query = _currentMentionQuery?.trim().toLowerCase();
    if (query == null || query.isEmpty) return _slashSkills;
    return _slashSkills
        .where(
          (skill) => [
            skill.name,
            skill.label,
            skill.summary,
            skill.description,
          ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  ({int used, int maximum}) get _contextUsage {
    // App Server does not currently expose token accounting in the client
    // protocol. Keep a conservative local estimate so the affordance remains
    // useful and updates as history, tool output, and the draft change.
    var characters = 1000; // system instructions and protocol envelope
    for (final entry in controller.entries) {
      characters += entry.title.runes.length + entry.detail.runes.length;
    }
    characters += composer.text.runes.length;
    for (final pastedText in _pastedTexts) {
      characters += pastedText.text.runes.length;
    }
    for (final attachment in _attachments) {
      characters += attachment.path.runes.length + 256;
    }
    for (final skill in _selectedSkills) {
      characters += skill.name.runes.length + skill.description.runes.length;
    }
    return (used: (characters / 4).ceil(), maximum: 258000);
  }

  bool get _hasComposerChips =>
      _attachments.isNotEmpty ||
      _includeWorkspace ||
      _goal?.isNotEmpty == true ||
      _planMode ||
      _recordSkill ||
      _selectedSkillPaths.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _handledRecordSkillRequest = widget.recordSkillRequest.value;
    controller.addListener(_handleControllerChanged);
    composer.addListener(_handleComposerEditingChanged);
    widget.recordSkillRequest.addListener(_handleRecordSkillRequest);
  }

  @override
  void didUpdateWidget(covariant ComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      for (final path in _temporaryAttachmentPaths) {
        oldWidget.controller.transferTemporaryAttachmentTo(path, controller);
      }
      controller.addListener(_handleControllerChanged);
      _releaseDetachedAttachmentResources();
    }
    if (oldWidget.recordSkillRequest != widget.recordSkillRequest) {
      oldWidget.recordSkillRequest.removeListener(_handleRecordSkillRequest);
      _handledRecordSkillRequest = widget.recordSkillRequest.value;
      widget.recordSkillRequest.addListener(_handleRecordSkillRequest);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    composer.removeListener(_handleComposerEditingChanged);
    widget.recordSkillRequest.removeListener(_handleRecordSkillRequest);
    _imeCompositionDeferral?.cancel();
    _releaseAllAttachmentResources();
    super.dispose();
  }

  void _handleRecordSkillRequest() {
    if (_handledRecordSkillRequest == widget.recordSkillRequest.value) return;
    _handledRecordSkillRequest = widget.recordSkillRequest.value;
    if (mounted) setState(() => _recordSkill = true);
  }

  void _handleControllerChanged() {
    if (controller.status != RuntimeStatus.running) {
      _releaseDetachedAttachmentResources();
    }
  }

  /// 在平台已清除组合范围后，仍将确认输入法候选的 Enter 视为输入法操作。
  /// Keeps the Enter that confirms an IME candidate from being mistaken for a
  /// new send after the platform has already cleared the composing range.
  void _handleComposerEditingChanged() {
    final slashQuery = _currentSlashQuery;
    final mentionQuery = _currentMentionQuery;
    final triggerQuery = slashQuery != null
        ? '/$slashQuery'
        : mentionQuery != null
        ? '@$mentionQuery'
        : '';
    if (triggerQuery != _slashMenuQuery) {
      _slashMenuQuery = triggerQuery;
      _slashMenuDismissed = false;
      _slashMenuSelectedIndex = 0;
    }
    if (mentionQuery != null &&
        controller.skills.isEmpty &&
        !controller.skillsLoading) {
      unawaited(controller.refreshSkills());
    }
    if ((slashQuery?.isNotEmpty ?? false) || mentionQuery != null) {
      _mcpStatusVisible = false;
      _codeReviewOptionsVisible = false;
    }
    if (mounted) setState(() {});
    final composing = composer.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      _imeCompositionActive = true;
      _imeCompositionJustEnded = false;
      _imeCompositionDeferral?.cancel();
      return;
    }
    if (!_imeCompositionActive) return;

    _imeCompositionActive = false;
    _imeCompositionJustEnded = true;
    _imeCompositionDeferral?.cancel();
    _imeCompositionDeferral = Timer(
      const Duration(milliseconds: 16),
      () => _imeCompositionJustEnded = false,
    );
  }

  String? get _currentSlashQuery {
    final text = composer.text;
    if (!text.startsWith('/') || text.contains('\n')) return null;
    final query = text.substring(1);
    if (query.contains(RegExp(r'\s'))) return null;
    return query;
  }

  String? get _currentMentionQuery {
    final text = composer.text;
    if (!text.startsWith('@') || text.contains('\n')) return null;
    final query = text.substring(1);
    if (query.contains(RegExp(r'\s'))) return null;
    return query;
  }

  bool get _showSlashMenu => _currentSlashQuery != null && !_slashMenuDismissed;

  bool get _showMentionMenu =>
      _currentMentionQuery != null && !_slashMenuDismissed;

  bool get _showComposerMenu => _showSlashMenu || _showMentionMenu;

  List<ComposerSlashCommand> get _slashCommands => [
    const ComposerSlashCommand(
      kind: ComposerSlashCommandKind.workspaceContext,
      label: 'IDE 上下文',
      description: '包含当前选择、打开的文件以及其他来自你的 IDE 的上下文',
      icon: Icons.auto_awesome_outlined,
    ),
    const ComposerSlashCommand(
      kind: ComposerSlashCommandKind.mcpStatus,
      label: 'MCP',
      description: '显示 MCP 服务器状态',
      icon: Icons.hub_outlined,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.codeReview,
      label: '代码审查',
      description: '审查未提交的更改，或与某个分支进行比较',
      icon: Icons.fact_check_outlined,
      enabled: controller.canStartCodeReview,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.sideChat,
      label: '侧边',
      description: '打开不会中断主任务的临时聊天',
      icon: Icons.add_circle_outline,
      enabled:
          controller.activeThreadId != null &&
          controller.workspacePath != null &&
          controller.serverIsRunning,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.forkChat,
      label: '创建聊天分支',
      description: '在当前工作空间或新工作树中创建此聊天的分支',
      icon: Icons.call_split_outlined,
      enabled: controller.canForkActiveThread,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.compact,
      label: '压缩',
      description:
          '压缩此聊天的上下文（已使用 ${((_contextUsage.used / _contextUsage.maximum) * 100).floor()}%）',
      icon: Icons.circle_outlined,
      enabled: controller.canCompactActiveThread,
    ),
    const ComposerSlashCommand(
      kind: ComposerSlashCommandKind.feedback,
      label: '反馈',
      description: '发送有关此聊天的反馈',
      icon: Icons.chat_bubble_outline,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.archive,
      label: '归档',
      description: '归档当前聊天',
      icon: Icons.archive_outlined,
      enabled: _canArchiveActiveThread,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.reasoning,
      label: '推理',
      description: controller.reasoningEffort.label,
      icon: Icons.psychology_outlined,
      enabled: controller.canSelectReasoningEffort,
    ),
    const ComposerSlashCommand(
      kind: ComposerSlashCommandKind.newChat,
      label: '新聊天',
      description: '在同一工作空间中开启空白聊天',
      icon: Icons.add_comment_outlined,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.model,
      label: '模型',
      description: controller.newTaskModelLabel,
      icon: Icons.view_in_ar_outlined,
      enabled: controller.canSelectModel,
    ),
  ];

  List<ComposerSlashCommand> get _mentionCommands => [
    const ComposerSlashCommand(
      kind: ComposerSlashCommandKind.files,
      label: '文件和文件夹',
      description: '',
      icon: Icons.attach_file,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.workspaceContext,
      label:
          '附加 ${controller.workspacePath == null ? '当前项目' : _pathLabel(controller.workspacePath!)}',
      description: '',
      icon: Icons.terminal_outlined,
    ),
    const ComposerSlashCommand(
      kind: ComposerSlashCommandKind.goal,
      label: '目标',
      description: '设置要持续追求的目标',
      icon: Icons.track_changes_outlined,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.planMode,
      label: '计划模式',
      description: controller.canSteer ? '任务运行时不可用' : '开启计划模式',
      icon: Icons.lightbulb_outline,
      enabled: !controller.canSteer,
    ),
    const ComposerSlashCommand(
      kind: ComposerSlashCommandKind.recordSkill,
      label: '录制技能',
      description: '',
      icon: Icons.radio_button_checked,
    ),
  ];

  List<ComposerSlashCommand> get _filteredSlashCommands {
    final query = _currentSlashQuery;
    if (query == null) return const [];
    return _slashCommands
        .where((command) => command.matches(query))
        .toList(growable: false);
  }

  List<ComposerSlashCommand> get _filteredMentionCommands {
    final query = _currentMentionQuery;
    if (query == null) return const [];
    return _mentionCommands
        .where((command) => command.matches(query))
        .toList(growable: false);
  }

  void _moveSlashMenuSelection(int delta) {
    final itemCount = _showMentionMenu
        ? _filteredMentionSkills.length + _filteredMentionCommands.length
        : _filteredSlashCommands.length;
    if (itemCount == 0) return;
    var nextIndex = _slashMenuSelectedIndex;
    do {
      final candidate = (nextIndex + delta).clamp(0, itemCount - 1);
      if (candidate == nextIndex) return;
      nextIndex = candidate;
    } while (!_composerMenuItemEnabled(nextIndex));
    setState(() => _slashMenuSelectedIndex = nextIndex);
    _scrollFocusedSlashMenuItemIntoView();
  }

  bool _composerMenuItemEnabled(int index) {
    if (_showMentionMenu) {
      final commands = _filteredMentionCommands;
      if (index < commands.length) return commands[index].enabled;
      return index < commands.length + _filteredMentionSkills.length;
    }
    final commands = _filteredSlashCommands;
    return index < commands.length && commands[index].enabled;
  }

  void _scrollFocusedSlashMenuItemIntoView() {
    final key = _focusedSlashMenuItemKey;
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final itemContext = key.currentContext;
      if (!mounted || itemContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          itemContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  GlobalKey? get _focusedSlashMenuItemKey {
    final commands = _showMentionMenu
        ? _filteredMentionCommands
        : _filteredSlashCommands;
    if (_showMentionMenu) {
      final skills = _filteredMentionSkills;
      final index = _slashMenuSelectedIndex.clamp(
        0,
        commands.length + skills.length - 1,
      );
      if (index < commands.length) {
        return _scrollKeyForSlashCommand(commands[index].kind);
      }
      if (skills.isEmpty) return null;
      return _scrollKeyForSlashSkill(skills[index - commands.length].path);
    }
    if (commands.isEmpty) return null;
    final index = _slashMenuSelectedIndex.clamp(0, commands.length - 1);
    return _scrollKeyForSlashCommand(commands[index].kind);
  }

  GlobalKey _scrollKeyForSlashCommand(ComposerSlashCommandKind kind) =>
      _slashCommandScrollKeys.putIfAbsent(kind, GlobalKey.new);

  GlobalKey _scrollKeyForSlashSkill(String path) =>
      _slashSkillScrollKeys.putIfAbsent(path, GlobalKey.new);

  void _selectFocusedSlashCommand() {
    if (_showMentionMenu) {
      final skills = _filteredMentionSkills;
      final commands = _filteredMentionCommands;
      if (skills.isEmpty && commands.isEmpty) return;
      final index = _slashMenuSelectedIndex.clamp(
        0,
        skills.length + commands.length - 1,
      );
      if (index < commands.length) {
        if (!commands[index].enabled) return;
        unawaited(_selectMentionCommand(commands[index]));
        return;
      }
      if (skills.isEmpty) return;
      _selectSlashSkill(skills[index - commands.length]);
      return;
    }
    final commands = _filteredSlashCommands;
    if (commands.isEmpty) return;
    final index = _slashMenuSelectedIndex.clamp(0, commands.length - 1);
    if (!commands[index].enabled) return;
    unawaited(_selectSlashCommand(commands[index]));
  }

  void _selectSlashSkill(CodexSkill skill) {
    setState(() {
      _selectedSkillPaths.add(skill.path);
      _slashMenuDismissed = true;
    });
    composer.clear();
  }

  Future<void> _selectMentionCommand(ComposerSlashCommand command) async {
    composer.clear();
    setState(() => _slashMenuDismissed = true);
    switch (command.kind) {
      case ComposerSlashCommandKind.files:
        await _showAttachmentPicker();
      case ComposerSlashCommandKind.workspaceContext:
        if (controller.workspacePath != null) {
          setState(() => _includeWorkspace = true);
        }
      case ComposerSlashCommandKind.goal:
        _enterGoalMode();
      case ComposerSlashCommandKind.planMode:
        if (!controller.canSteer) _togglePlanMode();
      case ComposerSlashCommandKind.recordSkill:
        setState(() => _recordSkill = !_recordSkill);
      case ComposerSlashCommandKind.mcpStatus ||
          ComposerSlashCommandKind.codeReview ||
          ComposerSlashCommandKind.sideChat ||
          ComposerSlashCommandKind.forkChat ||
          ComposerSlashCommandKind.compact ||
          ComposerSlashCommandKind.feedback ||
          ComposerSlashCommandKind.archive ||
          ComposerSlashCommandKind.reasoning ||
          ComposerSlashCommandKind.model ||
          ComposerSlashCommandKind.newChat:
        return;
    }
  }

  Future<String> _readSkillContent(CodexSkill skill) async {
    const maximumBytes = 160000;
    final file = File(skill.path);
    final length = await file.length();
    final stream = length > maximumBytes
        ? file.openRead(0, maximumBytes)
        : file.openRead();
    final content = await stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    return length > maximumBytes ? '$content\n\n… 技能内容已截断。' : content;
  }

  void _showSkillDetails(CodexSkill skill) {
    final content = _readSkillContent(skill);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) =>
            ComposerSkillDetailsDialog(skill: skill, content: content),
      ),
    );
  }

  void _dismissSlashMenu() {
    if (!_showComposerMenu) return;
    setState(() => _slashMenuDismissed = true);
  }

  void _handleEscape() {
    if (_showComposerMenu) {
      _dismissSlashMenu();
      return;
    }
    if (_codeReviewOptionsVisible) {
      _codeReviewBranchRequest++;
      composer.clear();
      setState(() {
        _codeReviewOptionsVisible = false;
        _codeReviewBranchesLoading = false;
        _codeReviewBranchesError = null;
      });
      return;
    }
    if (_mcpStatusVisible) {
      _dismissMcpStatus();
      return;
    }
    final composing = composer.value.composing;
    if (_imeCompositionActive ||
        (composing.isValid && !composing.isCollapsed)) {
      return;
    }
    if (controller.canStop) unawaited(controller.stopCurrentTurn());
  }

  Future<void> _selectSlashCommand(ComposerSlashCommand command) async {
    setState(() => _slashMenuDismissed = true);
    switch (command.kind) {
      case ComposerSlashCommandKind.workspaceContext:
        if (controller.workspacePath != null) {
          setState(() => _includeWorkspace = true);
        }
        composer.clear();
      case ComposerSlashCommandKind.files:
        composer.clear();
        await _showAttachmentPicker();
      case ComposerSlashCommandKind.goal:
        _enterGoalMode();
      case ComposerSlashCommandKind.planMode:
        if (controller.canSteer) return;
        _togglePlanMode();
        composer.clear();
      case ComposerSlashCommandKind.recordSkill:
        setState(() => _recordSkill = !_recordSkill);
        composer.clear();
      case ComposerSlashCommandKind.mcpStatus:
        composer.value = const TextEditingValue(
          text: '/',
          selection: TextSelection.collapsed(offset: 1),
        );
        setState(() {
          _slashMenuDismissed = true;
          _mcpStatusVisible = true;
          _codeReviewOptionsVisible = false;
        });
        unawaited(controller.refreshMcpServers());
      case ComposerSlashCommandKind.codeReview:
        composer.value = const TextEditingValue(
          text: '/',
          selection: TextSelection.collapsed(offset: 1),
        );
        setState(() {
          _slashMenuDismissed = true;
          _mcpStatusVisible = false;
        });
        unawaited(_showCodeReviewOptions());
      case ComposerSlashCommandKind.sideChat:
        composer.clear();
        await widget.onOpenSideChat?.call();
      case ComposerSlashCommandKind.forkChat:
        composer.clear();
        await _forkActiveThread();
      case ComposerSlashCommandKind.compact:
        composer.clear();
        await _confirmAndCompactThread();
      case ComposerSlashCommandKind.feedback:
        composer.clear();
        await _showFeedbackDialog();
      case ComposerSlashCommandKind.archive:
        composer.clear();
        await _archiveCurrentThread();
      case ComposerSlashCommandKind.reasoning:
        composer.clear();
        await _showReasoningPicker();
      case ComposerSlashCommandKind.model:
        composer.clear();
        await _showModelPicker();
      case ComposerSlashCommandKind.newChat:
        composer.clear();
        controller.createThread();
    }
  }

  void _showUnavailableSlashCommand(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 尚未由当前 Codex App Server 提供。')),
    );
  }

  Future<void> _forkActiveThread({bool ephemeral = false}) async {
    final sourceThreadId = controller.activeThreadId;
    if (sourceThreadId == null || !controller.canForkActiveThread) {
      _showArchiveFeedback('当前没有可创建分支的聊天。');
      return;
    }
    if (ephemeral) {
      _showUnavailableSlashCommand('侧边聊天界面');
      return;
    }
    await controller.forkActiveThread();
  }

  Future<void> _confirmAndCompactThread() async {
    if (!controller.canCompactActiveThread) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('composer-compact-dialog'),
        title: const Text('压缩此聊天？'),
        content: const Text('Codex 会用一份简洁摘要替换较早的对话内容，以释放上下文空间。'),
        actions: [
          TextButton(
            key: const Key('composer-compact-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('composer-compact-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('压缩'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.compactActiveThread();
    }
  }

  Future<void> _showFeedbackDialog() async {
    final reason = TextEditingController();
    var classification = 'bug';
    var includeLogs = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    final route =
        DialogRoute<({String classification, bool includeLogs, String reason})>(
          context: context,
          themes: themes,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              key: const Key('composer-feedback-dialog'),
              title: const Text('发送反馈'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('composer-feedback-classification'),
                      initialValue: classification,
                      decoration: const InputDecoration(labelText: '反馈类型'),
                      items: const [
                        DropdownMenuItem(value: 'bug', child: Text('问题')),
                        DropdownMenuItem(value: 'feature', child: Text('功能建议')),
                        DropdownMenuItem(value: 'other', child: Text('其他')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => classification = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('composer-feedback-reason'),
                      controller: reason,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '反馈内容（可选）',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      key: const Key('composer-feedback-include-logs'),
                      contentPadding: EdgeInsets.zero,
                      value: includeLogs,
                      title: const Text('包含诊断日志'),
                      subtitle: const Text('仅在勾选后随反馈上传运行时诊断信息'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) =>
                          setDialogState(() => includeLogs = value ?? false),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const Key('composer-feedback-cancel'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const Key('composer-feedback-submit'),
                  onPressed: () => Navigator.of(dialogContext).pop((
                    classification: classification,
                    includeLogs: includeLogs,
                    reason: reason.text,
                  )),
                  child: const Text('发送'),
                ),
              ],
            ),
          ),
        );
    final result = await navigator.push(route);
    await route.completed;
    reason.dispose();
    if (result == null || !mounted) return;
    final submitted = await controller.submitFeedback(
      classification: result.classification,
      includeLogs: result.includeLogs,
      reason: result.reason,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(submitted ? '反馈已发送。' : '反馈发送失败，请稍后重试。')),
    );
  }

  Future<void> _archiveCurrentThread() async {
    final targetController = controller;
    final activeThread = _activeComposerThread;
    if (activeThread == null) {
      _showArchiveFeedback('当前没有可归档的聊天。');
      return;
    }
    final result = await targetController.archiveThread(activeThread);
    if (!mounted || controller != targetController) return;
    if (result.archivedIds.contains(activeThread.id)) return;
    if (result.runningThreadIds.contains(activeThread.id)) {
      _showArchiveFeedback('当前聊天仍在运行，请先停止任务。');
    } else if (result.updatingThreadIds.contains(activeThread.id)) {
      _showArchiveFeedback('当前聊天正在更新，请稍后重试。');
    } else if (result.unavailableThreadIds.contains(activeThread.id)) {
      _showArchiveFeedback('Codex 运行时当前不可用，无法归档聊天。');
    } else {
      _showArchiveFeedback('当前聊天未能归档，请稍后重试。');
    }
  }

  void _showArchiveFeedback(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showReasoningPicker() async {
    if (!controller.canSelectReasoningEffort) return;
    final selected = await showDialog<ReasoningEffort>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const Key('composer-reasoning-dialog'),
        title: const Text('推理'),
        children: [
          for (final effort in controller.reasoningEffortOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, effort),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: controller.reasoningEffort == effort
                        ? const Icon(Icons.check, size: 17)
                        : null,
                  ),
                  Text(effort.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) await controller.setReasoningEffort(selected);
  }

  Future<void> _showModelPicker() async {
    if (!controller.canSelectModel) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const Key('composer-model-dialog'),
        title: const Text('模型'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: controller.selectedModelId == null
                      ? const Icon(Icons.check, size: 17)
                      : null,
                ),
                const Text('默认'),
              ],
            ),
          ),
          for (final option in controller.modelOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option.id),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: controller.selectedModelId == option.id
                        ? const Icon(Icons.check, size: 17)
                        : null,
                  ),
                  Text(option.displayName),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      await controller.setModel(selected.isEmpty ? null : selected);
    }
  }

  Future<void> _showCodeReviewOptions() async {
    final workspace = controller.workspacePath;
    final request = ++_codeReviewBranchRequest;
    setState(() {
      _codeReviewOptionsVisible = true;
      _codeReviewBranchesLoading = true;
      _codeReviewBranchesError = null;
      _codeReviewBaseBranches = const [];
    });
    try {
      final branches = await controller.listGitReviewBaseBranches();
      if (!mounted ||
          request != _codeReviewBranchRequest ||
          workspace != controller.workspacePath) {
        return;
      }
      setState(() => _codeReviewBaseBranches = branches);
    } catch (error) {
      if (!mounted ||
          request != _codeReviewBranchRequest ||
          workspace != controller.workspacePath) {
        return;
      }
      setState(() => _codeReviewBranchesError = error.toString());
    } finally {
      if (mounted &&
          request == _codeReviewBranchRequest &&
          workspace == controller.workspacePath) {
        setState(() => _codeReviewBranchesLoading = false);
      }
    }
  }

  void _dismissMcpStatus() {
    if (!_mcpStatusVisible) return;
    composer.clear();
    setState(() => _mcpStatusVisible = false);
  }

  Future<void> _reviewUncommittedChanges() async {
    if (_reviewSubmissionPending) return;
    setState(() => _reviewSubmissionPending = true);
    final submitted = await controller.startCodeReview(const {
      'type': 'uncommittedChanges',
    });
    if (!mounted) return;
    setState(() {
      _reviewSubmissionPending = false;
      _codeReviewOptionsVisible = !submitted;
    });
  }

  void _reviewAgainstBaseBranch(String branch) {
    setState(() {
      _codeReviewOptionsVisible = false;
      _reviewSubmissionPending = true;
    });
    unawaited(_startBranchReview(branch));
  }

  Future<void> _startBranchReview(String branch) async {
    final submitted = await controller.startCodeReview({
      'type': 'baseBranch',
      'branch': branch,
    });
    if (!mounted) return;
    setState(() {
      _reviewSubmissionPending = false;
      _codeReviewOptionsVisible = !submitted;
    });
  }

  void _releaseDetachedAttachmentResources() {
    final attachedPaths = _attachments
        .map((attachment) => attachment.path)
        .toSet();
    final detachedBookmarkPaths = _securityBookmarks.keys
        .where(
          (path) =>
              !attachedPaths.contains(path) &&
              !controller.isAttachmentPathReferenced(path),
        )
        .toList(growable: false);
    for (final path in detachedBookmarkPaths) {
      _releaseSecurityBookmark(path);
    }
    controller.releaseDetachedTemporaryAttachments();
  }

  void _releaseAllAttachmentResources() {
    final bookmarkPaths = _securityBookmarks.keys.toList(growable: false);
    for (final path in bookmarkPaths) {
      _releaseSecurityBookmark(path);
    }
    final temporaryPaths = _temporaryAttachmentPaths.toList(growable: false);
    _temporaryAttachmentPaths.clear();
    for (final path in temporaryPaths) {
      controller.releaseTemporaryAttachment(path);
    }
  }

  void _releaseAttachmentResources(String path) {
    _releaseSecurityBookmark(path);
    if (_temporaryAttachmentPaths.remove(path)) {
      controller.releaseTemporaryAttachment(path);
    }
  }

  void _releaseSecurityBookmark(String path) {
    final bookmark = _securityBookmarks.remove(path);
    if (bookmark != null) unawaited(_stopAccessingBookmark(bookmark));
  }

  Future<void> _stopAccessingBookmark(Uint8List bookmark) async {
    try {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    } on MissingPluginException {
      // The host platform does not require macOS security-scoped access.
    } on PlatformException {
      // The resource is already unavailable; there is nothing else to release.
    }
  }

  String get _activityLabel =>
      controller.status == RuntimeStatus.ready ? '任务已就绪' : '等待运行时连接';

  bool get _showsActivityPill {
    if (controller.status == RuntimeStatus.running) return false;
    final threadId = controller.activeThreadId;
    if (threadId == null) return false;
    return controller.status != RuntimeStatus.ready ||
        !controller.isCompletedThreadAcknowledged(threadId);
  }

  Future<bool> _submit() async {
    final missingTemporaryAttachments = <ComposerAttachment>[];
    for (final attachment in _attachments) {
      final isClipboardTemporary =
          attachment.isTemporary ||
          attachment.path
              .replaceAll('\\', '/')
              .contains('/CodexDeskClipboard/');
      // 剪贴板图片位于本地临时卷。这里保持同步检查，避免组件销毁在校验完成
      // 与控制器同步取得持久化引用之间排入删除请求。
      // Clipboard images live on the local temporary volume. Keep this check
      // synchronous so disposal cannot enqueue deletion between validation
      // and the controller's synchronous persistence retain.
      if (isClipboardTemporary && !File(attachment.path).existsSync()) {
        missingTemporaryAttachments.add(attachment);
      }
    }
    if (missingTemporaryAttachments.isNotEmpty) {
      for (final attachment in missingTemporaryAttachments) {
        _releaseAttachmentResources(attachment.path);
      }
      if (mounted) {
        setState(() {
          _attachments.removeWhere(
            (attachment) => missingTemporaryAttachments.contains(attachment),
          );
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('剪贴板图片已失效，请重新粘贴后再发送。')));
      }
      return false;
    }
    final rawComposerText = composer.text.trim();
    final inlineGoal = !_goalMode
        ? RegExp(
            r'^/(?:goal|目标)\s+(.+)$',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(rawComposerText)
        : null;
    final inlinePlan = !_goalMode && !controller.canSteer
        ? RegExp(
            r'^/(?:plan|计划模式)\s+(.+)$',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(rawComposerText)
        : null;
    final inlineGoalText = inlineGoal?.group(1)?.trim();
    final inlinePlanPrompt = inlinePlan?.group(1)?.trim();
    final goalText =
        inlineGoalText ?? (_goalMode ? _combinedComposerText : _goal);
    if (goalText != null && goalText.runes.length > 4000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目标不能超过 4000 个字符。')));
      return false;
    }
    if (inlinePlanPrompt?.isNotEmpty == true && !_planMode) {
      setState(() => _planMode = true);
    }
    final submission = ComposerSubmission(
      // Codex Goal mode uses the objective as both the first prompt and the
      // completion criteria. A prior draft is restored only when Goal mode is
      // cancelled; submitting intentionally sends the goal text itself.
      prompt: inlineGoalText ?? inlinePlanPrompt ?? rawComposerText,
      attachments: List.unmodifiable(_attachments),
      pastedTexts: List.unmodifiable(
        _pastedTexts.map((pastedText) => pastedText.text),
      ),
      includeWorkspace: _includeWorkspace,
      goal: goalText,
      planMode: _planMode,
      recordSkill: _recordSkill,
      skills: _selectedSkills,
    );
    final submitted = controller.canSteer
        ? await widget.onQueueSteer(submission)
        : await widget.onSend(submission);
    if (!submitted || !mounted) return false;
    final submittedTemporaryPaths = submission.attachments
        .where((attachment) => attachment.isTemporary)
        .map((attachment) => attachment.path)
        .toList(growable: false);
    setState(() {
      composer.clear();
      _attachments.clear();
      _pastedTexts.clear();
      _selectedSkillPaths.clear();
      _includeWorkspace = false;
      _recordSkill = false;
      // A goal is persisted on the thread by the successful submission.  It
      // belongs to that task from here on, rather than remaining as a draft
      // context chip for every later composer submission.
      _goal = null;
      _goalBeforeGoalMode = null;
      _draftBeforeGoalMode = null;
      _goalMode = false;
    });
    for (final path in submittedTemporaryPaths) {
      _temporaryAttachmentPaths.remove(path);
      controller.releaseTemporaryAttachment(path);
    }
    if (controller.status != RuntimeStatus.running) {
      _releaseDetachedAttachmentResources();
    }
    return true;
  }

  /// 先让平台输入法处理确认候选的 Enter，后续 Enter 才提交 Composer 内容。
  /// Lets a platform IME finish its candidate-confirmation Enter before a
  /// later Enter submits the Composer text.
  void _submitFromKeyboard() {
    final composing = composer.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    if (_imeCompositionJustEnded) {
      _imeCompositionJustEnded = false;
      _imeCompositionDeferral?.cancel();
      return;
    }
    unawaited(_submit());
  }

  Future<void> _handleAddAction(AddMenuAction action) async {
    switch (action.kind) {
      case AddMenuActionKind.files:
        await _showAttachmentPicker();
      case AddMenuActionKind.workspace:
        setState(() => _includeWorkspace = !_includeWorkspace);
      case AddMenuActionKind.goal:
        _enterGoalMode(preserveDraft: true);
      case AddMenuActionKind.plan:
        if (!controller.canSteer) _togglePlanMode();
      case AddMenuActionKind.recordSkill:
        setState(() => _recordSkill = !_recordSkill);
      case AddMenuActionKind.skill:
        final path = action.value;
        if (path == null) return;
        setState(() {
          if (!_selectedSkillPaths.add(path)) {
            _selectedSkillPaths.remove(path);
          }
        });
    }
  }

  Future<void> _showAttachmentPicker() async {
    final choice = await showDialog<AttachmentPickerKind>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('attachment-picker-dialog'),
        title: const Text('文件和文件夹'),
        content: const Text('选择要随下一条消息发送的文件，或添加一个文件夹路径作为任务上下文。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          OutlinedButton.icon(
            key: const Key('pick-folder-button'),
            onPressed: () =>
                Navigator.pop(dialogContext, AttachmentPickerKind.folder),
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: const Text('文件夹'),
          ),
          FilledButton.icon(
            key: const Key('pick-files-button'),
            onPressed: () =>
                Navigator.pop(dialogContext, AttachmentPickerKind.files),
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('文件'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      final attachments = switch (choice) {
        AttachmentPickerKind.files =>
          (await openFiles(confirmButtonText: '附加文件'))
              .map(
                (file) =>
                    ComposerAttachment(path: file.path, isDirectory: false),
              )
              .toList(growable: false),
        AttachmentPickerKind.folder => [
          if (await getDirectoryPath(confirmButtonText: '附加文件夹')
              case final path?)
            ComposerAttachment(path: path, isDirectory: true),
        ],
      };
      if (!mounted || attachments.isEmpty) return;
      _addAttachments(attachments);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开文件选择器。')));
    }
  }

  Future<void> _pasteFromClipboard() async {
    final items = await _clipboardFileReader.readItems();
    if (!mounted) return;
    if (items.isNotEmpty) {
      if (!controller.canSend && !controller.canQueueTurnSteer) {
        return;
      }
      _addAttachments(
        items.map(
          (item) => ComposerAttachment(
            path: item.path,
            isDirectory: item.isDirectory,
            isTemporary: item.isTemporary,
          ),
        ),
      );
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pastedText = data?.text;
    if (!mounted || pastedText == null || pastedText.isEmpty) return;
    if (_shouldCollapsePastedText(pastedText)) {
      _replaceComposerSelection('');
      setState(() {
        _pastedTexts.add(
          ComposerPastedText(id: ++_nextPastedTextId, text: pastedText),
        );
      });
      return;
    }
    _replaceComposerSelection(pastedText);
  }

  bool _shouldCollapsePastedText(String text) {
    var characters = 0;
    var lineBreaks = 0;
    for (final rune in text.runes) {
      characters++;
      if (rune == 0x0A) lineBreaks++;
      if (characters > _collapsedPasteCharacterThreshold ||
          lineBreaks >= _collapsedPasteLineThreshold) {
        return true;
      }
    }
    return false;
  }

  String get _combinedComposerText => [
    composer.text.trim(),
    ..._pastedTexts.map((pastedText) => pastedText.text.trim()),
  ].where((text) => text.isNotEmpty).join('\n\n');

  void _replaceComposerSelection(String replacement) {
    final current = composer.text;
    final selection = composer.selection;
    final rawStart = selection.isValid ? selection.start : current.length;
    final rawEnd = selection.isValid ? selection.end : current.length;
    final start = rawStart.clamp(0, current.length);
    final end = rawEnd.clamp(0, current.length);
    final lower = start < end ? start : end;
    final upper = start < end ? end : start;
    composer.value = TextEditingValue(
      text: current.replaceRange(lower, upper, replacement),
      selection: TextSelection.collapsed(offset: lower + replacement.length),
    );
  }

  void _showPastedTextInComposer(ComposerPastedText pastedText) {
    if (!_pastedTexts.any((item) => item.id == pastedText.id)) return;
    _replaceComposerSelection(pastedText.text);
    setState(() {
      _pastedTexts.removeWhere((item) => item.id == pastedText.id);
    });
  }

  void _removePastedText(int id) {
    setState(() => _pastedTexts.removeWhere((item) => item.id == id));
  }

  Widget _buildComposerContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    void paste() {
      editableTextState.hideToolbar();
      unawaited(_pasteFromClipboard());
    }

    var hasPaste = false;
    final items = editableTextState.contextMenuButtonItems
        .map((item) {
          if (item.type != ContextMenuButtonType.paste) return item;
          hasPaste = true;
          return item.copyWith(onPressed: paste);
        })
        .toList(growable: true);
    if (!hasPaste) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: paste,
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  Future<void> _handleDroppedFiles(List<DropItem> items) async {
    if (items.isEmpty ||
        !mounted ||
        (!controller.canSend && !controller.canQueueTurnSteer)) {
      return;
    }
    final attachments = <ComposerAttachment>[];
    for (final item in items) {
      final path = item.path;
      if (path.isEmpty) continue;
      if (item.extraAppleBookmark case final bookmark?
          when bookmark.isNotEmpty && !_securityBookmarks.containsKey(path)) {
        var accessStarted = false;
        try {
          accessStarted = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
        } on MissingPluginException {
          // The host platform does not require macOS security-scoped access.
        } on PlatformException {
          // Keep the attachment usable on unsandboxed hosts when scope setup fails.
        }
        if (!mounted) {
          if (accessStarted) await _stopAccessingBookmark(bookmark);
          return;
        }
        if (accessStarted) _securityBookmarks[path] = bookmark;
      }
      attachments.add(
        ComposerAttachment(path: path, isDirectory: item is DropItemDirectory),
      );
    }
    if (!mounted || attachments.isEmpty) return;
    _addAttachments(attachments);
  }

  void _addAttachments(Iterable<ComposerAttachment> attachments) {
    if (!controller.canSend && !controller.canQueueTurnSteer) return;
    setState(() {
      for (final attachment in attachments) {
        if (attachment.path.isEmpty) continue;
        if (attachment.isTemporary) {
          if (_temporaryAttachmentPaths.add(attachment.path)) {
            controller.retainTemporaryAttachment(attachment.path);
          }
        }
        final index = _attachments.indexWhere(
          (existing) => existing.path == attachment.path,
        );
        if (index < 0) {
          _attachments.add(attachment);
        } else {
          final existing = _attachments[index];
          _attachments[index] = ComposerAttachment(
            path: attachment.path,
            isDirectory: existing.isDirectory || attachment.isDirectory,
            isTemporary: existing.isTemporary || attachment.isTemporary,
          );
        }
      }
    });
  }

  void _removeAttachment(String path) {
    _releaseAttachmentResources(path);
    setState(() => _attachments.removeWhere((item) => item.path == path));
  }

  Future<void> _showImagePreview(String path) async {
    if (!mounted) return;
    await showLocalImagePreview(context, path);
  }

  void _enterGoalMode({bool preserveDraft = false}) {
    if (_goalMode) return;
    final originalDraft = composer.text;
    final existingGoal = _goal;
    composer.value = TextEditingValue(
      text: existingGoal ?? '',
      selection: TextSelection.collapsed(offset: (existingGoal ?? '').length),
    );
    setState(() {
      _draftBeforeGoalMode = preserveDraft ? originalDraft : null;
      _goalBeforeGoalMode = existingGoal;
      _goal = null;
      _goalMode = true;
    });
  }

  void _leaveGoalMode() {
    final restoredDraft = _draftBeforeGoalMode;
    composer.value = TextEditingValue(
      text: restoredDraft ?? '',
      selection: TextSelection.collapsed(offset: (restoredDraft ?? '').length),
    );
    setState(() {
      _draftBeforeGoalMode = null;
      _goal = _goalBeforeGoalMode;
      _goalBeforeGoalMode = null;
      _goalMode = false;
    });
  }

  void _togglePlanMode() {
    if (controller.canSteer) return;
    setState(() => _planMode = !_planMode);
  }

  List<PopupMenuEntry<AddMenuAction>> _buildAddMenu(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final workspace = controller.workspacePath;
    final workspaceName = workspace == null ? '当前项目' : _pathLabel(workspace);
    final entries = <PopupMenuEntry<AddMenuAction>>[
      AddMenuHeader(label: '添加', palette: palette),
      AddMenuItem(
        key: const Key('add-files-menu-item'),
        value: const AddMenuAction(AddMenuActionKind.files),
        icon: Icons.attach_file,
        label: '文件和文件夹',
        selected: _attachments.isNotEmpty,
      ),
      AddMenuItem(
        key: const Key('add-workspace-menu-item'),
        value: const AddMenuAction(AddMenuActionKind.workspace),
        icon: Icons.terminal_outlined,
        label: '附加 $workspaceName',
        selected: _includeWorkspace,
        enabled: workspace != null,
      ),
      AddMenuItem(
        key: const Key('add-goal-menu-item'),
        value: const AddMenuAction(AddMenuActionKind.goal),
        icon: Icons.track_changes_outlined,
        label: '目标',
        description: _goal ?? '设置要持续追求的目标',
        selected: _goal?.isNotEmpty == true,
      ),
      AddMenuItem(
        key: const Key('add-plan-mode-menu-item'),
        value: const AddMenuAction(AddMenuActionKind.plan),
        icon: Icons.lightbulb_outline,
        label: '计划模式',
        description: controller.canSteer
            ? '任务运行时不可用'
            : _planMode
            ? '已开启计划模式'
            : '开启计划模式',
        selected: _planMode,
        enabled: !controller.canSteer,
      ),
      AddMenuItem(
        key: const Key('record-skill-menu-item'),
        value: const AddMenuAction(AddMenuActionKind.recordSkill),
        icon: Icons.radio_button_checked,
        label: '录制技能',
        description: _recordSkill ? '将本次流程整理为技能' : null,
        selected: _recordSkill,
      ),
      AddMenuHeader(label: '插件', palette: palette),
    ];
    final enabledSkills = controller.skills
        .where((skill) => skill.enabled)
        .toList(growable: false);
    if (controller.skillsLoading && enabledSkills.isEmpty) {
      entries.add(
        AddMenuMessage(key: Key('composer-skills-loading'), label: '正在读取可用技能…'),
      );
    } else if (enabledSkills.isEmpty) {
      entries.add(
        AddMenuMessage(
          key: const Key('composer-skills-empty'),
          label: controller.skillsError ?? '当前项目没有可用技能',
        ),
      );
    } else {
      for (final skill in enabledSkills) {
        entries.add(
          AddMenuItem(
            key: ValueKey('composer-skill-${skill.name}'),
            value: AddMenuAction(AddMenuActionKind.skill, skill.path),
            icon: _skillIcon(skill.name),
            label: skill.label,
            description: skill.summary,
            selected: _selectedSkillPaths.contains(skill.path),
          ),
        );
      }
    }
    return entries;
  }

  IconData _skillIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.contains('sheet') || lower.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (lower.contains('presentation') || lower.contains('slide')) {
      return Icons.slideshow_outlined;
    }
    if (lower.contains('document') || lower.contains('doc')) {
      return Icons.description_outlined;
    }
    return Icons.auto_awesome_outlined;
  }

  String _pathLabel(String path) {
    final segments = path
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return segments.isEmpty ? path : segments.last;
  }

  /// 构建支持 Enter 发送、Shift+Enter 换行的任务输入面板。
  /// Builds the task composer that sends with Enter and inserts lines with Shift+Enter.
  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        conversationContentHorizontalInset,
        8,
        conversationContentHorizontalInset,
        18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.pendingTurnSteers.isNotEmpty)
            PendingTurnSteerQueue(
              pendingItems: controller.pendingTurnSteers,
              sendingAny: controller.pendingTurnSteerSending,
              isSending: controller.isPendingTurnSteerSending,
              onSend: (pending) => controller.sendPendingTurnSteer(pending),
              onDiscard: (pending) =>
                  controller.discardPendingTurnSteer(pending),
            ),
          if (_showComposerMenu) ...[
            ComposerSlashCommandMenu(
              commands: _showMentionMenu
                  ? _filteredMentionCommands
                  : _filteredSlashCommands,
              skills: _showMentionMenu ? _filteredMentionSkills : const [],
              showSkills: _showMentionMenu,
              skillsLoading: controller.skillsLoading,
              skillsError: controller.skillsError,
              searchQuery: _currentMentionQuery ?? _currentSlashQuery ?? '',
              commandScrollKeys: _slashCommandScrollKeys,
              skillScrollKeys: _slashSkillScrollKeys,
              selectedIndex: _slashMenuSelectedIndex.clamp(
                0,
                math.max(
                  0,
                  (_showMentionMenu
                              ? _filteredMentionSkills
                              : _filteredSlashCommands)
                          .length +
                      (_showMentionMenu ? _filteredMentionCommands.length : 0) -
                      1,
                ),
              ),
              onSelected: (command) {
                unawaited(
                  _showMentionMenu
                      ? _selectMentionCommand(command)
                      : _selectSlashCommand(command),
                );
              },
              onSkillSelected: _selectSlashSkill,
              menuKey: _showMentionMenu
                  ? const Key('composer-mention-menu')
                  : const Key('composer-slash-menu'),
              semanticLabel: _showMentionMenu ? '添加上下文与插件' : '快捷指令',
              commandSectionLabel: '添加',
              skillSectionLabel: '插件',
              showSkillScope: false,
              emptyResultLabel: _showMentionMenu ? '没有匹配的添加项或插件' : null,
            ),
            const SizedBox(height: 8),
          ],
          if (_mcpStatusVisible) ...[
            ComposerMcpStatusPanel(
              servers: controller.mcpServers,
              loading: controller.mcpServersLoading,
              error: controller.mcpServersError,
            ),
            const SizedBox(height: 8),
          ],
          if (_codeReviewOptionsVisible) ...[
            ComposerCodeReviewOptionsPanel(
              baseBranches: _codeReviewBaseBranches,
              loading: _codeReviewBranchesLoading,
              error: _codeReviewBranchesError,
              reviewSubmissionPending: _reviewSubmissionPending,
              onReviewUncommitted: () {
                unawaited(_reviewUncommittedChanges());
              },
              onReviewBranch: _reviewAgainstBaseBranch,
            ),
            const SizedBox(height: 8),
          ],
          Stack(
            key: const Key('composer-surface-stack'),
            clipBehavior: Clip.none,
            children: [
              DropTarget(
                onDragEntered: (_) {
                  if ((controller.canSend || controller.canQueueTurnSteer) &&
                      mounted) {
                    setState(() => _draggingFiles = true);
                  }
                },
                onDragExited: (_) {
                  if (mounted) setState(() => _draggingFiles = false);
                },
                onDragDone: (details) {
                  if (mounted) setState(() => _draggingFiles = false);
                  if (!controller.canSend && !controller.canQueueTurnSteer) {
                    return;
                  }
                  unawaited(_handleDroppedFiles(details.files));
                },
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      constraints: const BoxConstraints(minHeight: 126),
                      padding: const EdgeInsets.fromLTRB(16, 13, 12, 10),
                      decoration: BoxDecoration(
                        color: _draggingFiles
                            ? Color.alphaBlend(
                                palette.active.withValues(alpha: 0.08),
                                palette.field,
                              )
                            : palette.field,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _draggingFiles
                              ? palette.active
                              : palette.controlBorder,
                          width: _draggingFiles ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_pastedTexts.isNotEmpty) ...[
                            ConstrainedBox(
                              key: const Key('composer-pasted-text-region'),
                              constraints: const BoxConstraints(maxHeight: 110),
                              child: Scrollbar(
                                child: SingleChildScrollView(
                                  key: const Key('composer-pasted-text-scroll'),
                                  primary: false,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 7,
                                      runSpacing: 7,
                                      children: [
                                        for (final pastedText in _pastedTexts)
                                          ComposerPastedTextCard(
                                            key: ValueKey(
                                              'composer-pasted-text-${pastedText.id}',
                                            ),
                                            id: pastedText.id,
                                            label: pastedText.previewLabel,
                                            onShowInComposer: () =>
                                                _showPastedTextInComposer(
                                                  pastedText,
                                                ),
                                            onRemove: () => _removePastedText(
                                              pastedText.id,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          ConstrainedBox(
                            key: const Key('composer-field-region'),
                            constraints: const BoxConstraints(
                              minHeight: 64,
                              maxHeight: 124,
                            ),
                            child: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: composer,
                              child: TextField(
                                key: const Key('composer-field'),
                                controller: composer,
                                enabled:
                                    controller.canSend ||
                                    controller.canQueueTurnSteer,
                                contextMenuBuilder: _buildComposerContextMenu,
                                minLines: 2,
                                maxLines: 5,
                                textInputAction: TextInputAction.newline,
                                style: TextStyle(
                                  color: palette.trace,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: _goalMode
                                      ? '描述你的目标，定义可衡量的成果，以获得最佳效果'
                                      : '随心输入',
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
                                final imeIsComposing =
                                    composing.isValid && !composing.isCollapsed;
                                return CallbackShortcuts(
                                  bindings: {
                                    if (_showComposerMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.arrowDown,
                                      ): () =>
                                          _moveSlashMenuSelection(1),
                                    if (_showComposerMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.arrowUp,
                                      ): () =>
                                          _moveSlashMenuSelection(-1),
                                    if (_showComposerMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.tab,
                                      ): _selectFocusedSlashCommand,
                                    if (!_showComposerMenu &&
                                        !controller.canSteer &&
                                        !_goalMode)
                                      const SingleActivator(
                                        LogicalKeyboardKey.tab,
                                        shift: true,
                                      ): _togglePlanMode,
                                    const SingleActivator(
                                      LogicalKeyboardKey.escape,
                                    ): _handleEscape,
                                    // Do not register Enter while the IME owns
                                    // an active composition. This lets macOS
                                    // cancel or confirm its candidate instead
                                    // of having the composer consume the key.
                                    if (!imeIsComposing &&
                                        _codeReviewOptionsVisible)
                                      const SingleActivator(
                                        LogicalKeyboardKey.enter,
                                      ): () => unawaited(
                                        _reviewUncommittedChanges(),
                                      ),
                                    if (!imeIsComposing &&
                                        _mcpStatusVisible &&
                                        !_codeReviewOptionsVisible)
                                      const SingleActivator(
                                        LogicalKeyboardKey.enter,
                                      ): _dismissMcpStatus,
                                    if (!imeIsComposing &&
                                        !_showComposerMenu &&
                                        !_codeReviewOptionsVisible &&
                                        !_mcpStatusVisible)
                                      const SingleActivator(
                                        LogicalKeyboardKey.enter,
                                      ): _submitFromKeyboard,
                                    if (!imeIsComposing && _showComposerMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.enter,
                                      ): _selectFocusedSlashCommand,
                                    const SingleActivator(
                                      LogicalKeyboardKey.keyV,
                                      meta: true,
                                    ): () {
                                      unawaited(_pasteFromClipboard());
                                    },
                                    const SingleActivator(
                                      LogicalKeyboardKey.keyV,
                                      control: true,
                                    ): () {
                                      unawaited(_pasteFromClipboard());
                                    },
                                  },
                                  child: child!,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_hasComposerChips) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  for (final attachment in _attachments)
                                    ComposerContextChip(
                                      key: ValueKey(
                                        'composer-attachment-${attachment.path}',
                                      ),
                                      icon:
                                          !attachment.isDirectory &&
                                              isImagePath(attachment.path)
                                          ? Icons.image_outlined
                                          : Icons.attach_file,
                                      thumbnailPath:
                                          !attachment.isDirectory &&
                                              isImagePath(attachment.path)
                                          ? attachment.path
                                          : null,
                                      label: _pathLabel(attachment.path),
                                      onRemove: () =>
                                          _removeAttachment(attachment.path),
                                      onPreview:
                                          !attachment.isDirectory &&
                                              isImagePath(attachment.path)
                                          ? () => _showImagePreview(
                                              attachment.path,
                                            )
                                          : null,
                                    ),
                                  if (_includeWorkspace)
                                    ComposerContextChip(
                                      key: const Key('composer-workspace-chip'),
                                      icon: Icons.terminal_outlined,
                                      label: controller.workspacePath == null
                                          ? '当前项目'
                                          : _pathLabel(
                                              controller.workspacePath!,
                                            ),
                                      onRemove: () => setState(
                                        () => _includeWorkspace = false,
                                      ),
                                    ),
                                  if (_goal case final goal?)
                                    ComposerContextChip(
                                      key: const Key('composer-goal-chip'),
                                      icon: Icons.track_changes_outlined,
                                      label: goal,
                                      onRemove: () =>
                                          setState(() => _goal = null),
                                    ),
                                  if (_planMode)
                                    ComposerContextChip(
                                      key: const Key('composer-plan-mode-chip'),
                                      icon: Icons.lightbulb_outline,
                                      label: '计划模式',
                                      onRemove: controller.canSteer
                                          ? null
                                          : _togglePlanMode,
                                    ),
                                  if (_recordSkill)
                                    ComposerContextChip(
                                      key: const Key(
                                        'composer-record-skill-chip',
                                      ),
                                      icon: Icons.radio_button_checked,
                                      label: '录制技能',
                                      onRemove: () =>
                                          setState(() => _recordSkill = false),
                                    ),
                                  for (final skill in _selectedSkills)
                                    ComposerSelectedSkillChip(
                                      skill: skill,
                                      onOpen: () => _showSkillDetails(skill),
                                      onRemove: () => setState(
                                        () => _selectedSkillPaths.remove(
                                          skill.path,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 9),
                          ],
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final showAttachment =
                                  constraints.maxWidth >= 420;
                              final showApproval = constraints.maxWidth >= 340;
                              final showApprovalLabel =
                                  constraints.maxWidth >=
                                  (_goalMode ? 520 : 460);
                              final showGoalMode =
                                  _goalMode && constraints.maxWidth >= 400;
                              final showModel = constraints.maxWidth >= 240;
                              return Row(
                                children: [
                                  if (showAttachment)
                                    PopupMenuButton<AddMenuAction>(
                                      key: const Key('composer-add-button'),
                                      enabled:
                                          controller.canSend ||
                                          controller.canQueueTurnSteer,
                                      tooltip: '添加上下文',
                                      icon: const Icon(Icons.add, size: 20),
                                      constraints: const BoxConstraints(
                                        minWidth: 390,
                                        maxWidth: 470,
                                        maxHeight: 620,
                                      ),
                                      color: palette.field,
                                      surfaceTintColor: Colors.transparent,
                                      elevation: 10,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        side: BorderSide(
                                          color: palette.controlBorder,
                                        ),
                                      ),
                                      menuPadding: const EdgeInsets.fromLTRB(
                                        8,
                                        8,
                                        8,
                                        10,
                                      ),
                                      onOpened: () {
                                        if (controller.skills.isEmpty &&
                                            !controller.skillsLoading) {
                                          unawaited(controller.refreshSkills());
                                        }
                                      },
                                      onSelected: (action) =>
                                          unawaited(_handleAddAction(action)),
                                      itemBuilder: _buildAddMenu,
                                    ),
                                  if (showApproval)
                                    PopupMenuButton<ApprovalMode>(
                                      tooltip:
                                          '审批模式：${controller.approvalMode.label}',
                                      onSelected: controller.setApprovalMode,
                                      itemBuilder: (context) => ApprovalMode
                                          .values
                                          .map(
                                            (mode) => CheckedPopupMenuItem(
                                              value: mode,
                                              checked:
                                                  controller.approvalMode ==
                                                  mode,
                                              child: Text(mode.label),
                                            ),
                                          )
                                          .toList(growable: false),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.verified_user_outlined,
                                              size: 16,
                                            ),
                                            if (showApprovalLabel) ...[
                                              const SizedBox(width: 5),
                                              Text(
                                                controller.approvalMode.label,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (showGoalMode) ...[
                                    Container(
                                      width: 1,
                                      height: 16,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      color: palette.controlBorder,
                                    ),
                                    Semantics(
                                      button: true,
                                      label: '目标，点击退出目标输入',
                                      child: InkWell(
                                        key: const Key(
                                          'composer-goal-mode-control',
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: _leaveGoalMode,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.track_changes_outlined,
                                                size: 16,
                                                color: palette.muted,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                '目标',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: palette.muted,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  if (showModel) ...[
                                    Builder(
                                      builder: (context) {
                                        final usage = _contextUsage;
                                        return ComposerContextUsageButton(
                                          usedTokens: usage.used,
                                          maximumTokens: usage.maximum,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    ComposerModelControls(
                                      controller: controller,
                                      compact: constraints.maxWidth < 430,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (controller.canStop)
                                    IconButton.filled(
                                      tooltip: '停止当前任务',
                                      onPressed: controller.stopCurrentTurn,
                                      style: IconButton.styleFrom(
                                        backgroundColor: scheme.primary,
                                        foregroundColor: scheme.onPrimary,
                                        fixedSize: const Size.square(36),
                                        padding: EdgeInsets.zero,
                                        shape: const CircleBorder(),
                                      ),
                                      icon: const Icon(Icons.stop, size: 19),
                                    )
                                  else
                                    IconButton.filled(
                                      tooltip: '发送任务',
                                      onPressed: controller.canSend
                                          ? _submit
                                          : null,
                                      style: IconButton.styleFrom(
                                        backgroundColor: scheme.primary,
                                        foregroundColor: scheme.onPrimary,
                                        fixedSize: const Size.square(36),
                                        padding: EdgeInsets.zero,
                                        shape: const CircleBorder(),
                                      ),
                                      icon: const Icon(
                                        Icons.arrow_upward,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (_draggingFiles)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Semantics(
                            key: const Key('composer-drop-overlay'),
                            liveRegion: true,
                            label: '松开即可添加文件',
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.active.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.raised,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: palette.active.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.18,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.file_upload_outlined,
                                        size: 20,
                                        color: palette.active,
                                      ),
                                      const SizedBox(width: 9),
                                      Text(
                                        '松开即可添加文件',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: palette.trace,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (controller.fileChanges.isNotEmpty)
                Positioned(
                  key: const Key('composer-file-change-overlay'),
                  top: -18,
                  left: 0,
                  right: 0,
                  // This pill overlaps the timeline purely for display. It
                  // must not become a pointer-scroll barrier while content
                  // moves behind the floating composer.
                  child: IgnorePointer(
                    child: Center(
                      child: ComposerFileChangePill(
                        changes: controller.fileChanges,
                        turnDiff: controller.turnDiff,
                      ),
                    ),
                  ),
                ),
              if (controller.fileChanges.isEmpty &&
                  controller.pendingTurnSteer == null &&
                  _showsActivityPill)
                Positioned(
                  top: -44,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: ComposerActivityPill(label: _activityLabel),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
