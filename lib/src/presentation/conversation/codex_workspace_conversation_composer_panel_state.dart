// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_pending_turn_steer_queue.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_model_controls.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_activity_pill.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_file_change_pill.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_panel.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_add_menu_action.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_composer_attachment.dart';
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
  final List<ComposerAttachment> _attachments = [];
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
  bool _reviewSubmissionInFlight = false;
  bool _settingReviewPrompt = false;
  String? _codeReviewBranchesError;
  List<String> _codeReviewBaseBranches = const [];
  int _codeReviewBranchRequest = 0;
  bool _imeCompositionActive = false;
  bool _imeCompositionJustEnded = false;
  bool _slashMenuDismissed = false;
  int _slashMenuSelectedIndex = 0;
  String _slashMenuQuery = '';
  Timer? _imeCompositionDeferral;
  late int _handledRecordSkillRequest;
  String? _goal;

  CodexController get controller => widget.controller;
  TextEditingController get composer => widget.composer;

  List<CodexSkill> get _selectedSkills => controller.skills
      .where(
        (skill) => skill.enabled && _selectedSkillPaths.contains(skill.path),
      )
      .toList(growable: false);

  List<CodexSkill> get _slashSkills =>
      controller.skills.where((skill) => skill.enabled).toList(growable: false);

  List<CodexSkill> get _filteredSlashSkills {
    final query = _currentSlashQuery?.trim().toLowerCase();
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
    for (final attachment in _attachments) {
      characters += attachment.path.runes.length + 256;
    }
    for (final skill in _selectedSkills) {
      characters += skill.name.runes.length + skill.description.runes.length;
    }
    return (used: (characters / 4).ceil(), maximum: 258000);
  }

  bool get _hasComposerContext =>
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
    if (_reviewSubmissionPending) {
      unawaited(_submitPendingReviewWhenPossible());
    }
  }

  /// 在平台已清除组合范围后，仍将确认输入法候选的 Enter 视为输入法操作。
  /// Keeps the Enter that confirms an IME candidate from being mistaken for a
  /// new send after the platform has already cleared the composing range.
  void _handleComposerEditingChanged() {
    final slashQuery = _currentSlashQuery;
    if (!_settingReviewPrompt && _reviewSubmissionPending) {
      _reviewSubmissionPending = false;
      _reviewSubmissionInFlight = false;
    }
    if (slashQuery != _slashMenuQuery) {
      _slashMenuQuery = slashQuery ?? '';
      _slashMenuDismissed = false;
      _slashMenuSelectedIndex = 0;
    }
    if (slashQuery != null &&
        controller.skills.isEmpty &&
        !controller.skillsLoading) {
      unawaited(controller.refreshSkills());
    }
    if (!_settingReviewPrompt && slashQuery != '') {
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

  bool get _showSlashMenu => _currentSlashQuery != null && !_slashMenuDismissed;

  bool get _showSlashSkills => _currentSlashQuery != null;

  List<ComposerSlashCommand> get _slashCommands => const [
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.workspaceContext,
      label: 'IDE 上下文',
      description: '附加当前项目作为本次任务的上下文',
      icon: Icons.auto_awesome_outlined,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.mcpStatus,
      label: 'MCP',
      description: '检查当前 MCP 服务器状态',
      icon: Icons.hub_outlined,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.codeReview,
      label: '代码审查',
      description: '审查当前未提交的更改',
      icon: Icons.fact_check_outlined,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.files,
      label: '文件和文件夹',
      description: '为本次任务添加文件或目录',
      icon: Icons.attach_file,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.goal,
      label: '目标',
      description: '设置需要持续追求的任务结果',
      icon: Icons.track_changes_outlined,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.planMode,
      label: '计划模式',
      description: '让 Codex 先整理实施计划',
      icon: Icons.lightbulb_outline,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.recordSkill,
      label: '录制技能',
      description: '将这次流程整理成可复用技能',
      icon: Icons.radio_button_checked,
    ),
    ComposerSlashCommand(
      kind: ComposerSlashCommandKind.newChat,
      label: '新聊天',
      description: '清空当前输入并开始一个新任务',
      icon: Icons.add_comment_outlined,
    ),
  ];

  List<ComposerSlashCommand> get _filteredSlashCommands {
    final query = _currentSlashQuery;
    if (query == null) return const [];
    return _slashCommands
        .where((command) => command.matches(query))
        .toList(growable: false);
  }

  void _moveSlashMenuSelection(int delta) {
    final itemCount = _showSlashSkills
        ? _filteredSlashSkills.length + _filteredSlashCommands.length
        : _filteredSlashCommands.length;
    if (itemCount == 0) return;
    setState(() {
      _slashMenuSelectedIndex = (_slashMenuSelectedIndex + delta).clamp(
        0,
        itemCount - 1,
      );
    });
    _scrollFocusedSlashMenuItemIntoView();
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
    final commands = _filteredSlashCommands;
    if (_showSlashSkills) {
      final skills = _filteredSlashSkills;
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
    if (_showSlashSkills) {
      final skills = _filteredSlashSkills;
      final commands = _filteredSlashCommands;
      if (skills.isEmpty && commands.isEmpty) return;
      final index = _slashMenuSelectedIndex.clamp(
        0,
        skills.length + commands.length - 1,
      );
      if (index < commands.length) {
        unawaited(_selectSlashCommand(commands[index]));
        return;
      }
      if (skills.isEmpty) return;
      _selectSlashSkill(skills[index - commands.length]);
      return;
    }
    final commands = _filteredSlashCommands;
    if (commands.isEmpty) return;
    final index = _slashMenuSelectedIndex.clamp(0, commands.length - 1);
    unawaited(_selectSlashCommand(commands[index]));
  }

  void _selectSlashSkill(CodexSkill skill) {
    setState(() {
      _selectedSkillPaths.add(skill.path);
      _slashMenuDismissed = true;
    });
    composer.clear();
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
    if (!_showSlashMenu) return;
    setState(() => _slashMenuDismissed = true);
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
        composer.clear();
        setState(() {
          _goal = null;
          _goalMode = true;
        });
      case ComposerSlashCommandKind.planMode:
        setState(() => _planMode = !_planMode);
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
      case ComposerSlashCommandKind.newChat:
        composer.clear();
        controller.createThread();
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
    _settingReviewPrompt = true;
    composer.value = const TextEditingValue(
      text: '审查当前未提交的更改。',
      selection: TextSelection.collapsed(offset: 11),
    );
    _settingReviewPrompt = false;
    setState(() => _reviewSubmissionPending = true);
    await _submitPendingReviewWhenPossible();
  }

  Future<void> _submitPendingReviewWhenPossible() async {
    if (!_reviewSubmissionPending || _reviewSubmissionInFlight) return;
    if (!controller.canSend && !controller.canSteer) return;
    setState(() => _reviewSubmissionInFlight = true);
    final submitted = await _submit();
    if (!mounted) return;
    setState(() {
      _reviewSubmissionInFlight = false;
      if (submitted) {
        _reviewSubmissionPending = false;
        _codeReviewOptionsVisible = false;
      }
    });
  }

  void _reviewAgainstBaseBranch(String branch) {
    final prompt = '审查当前分支相对于 $branch 的更改。';
    setState(() => _codeReviewOptionsVisible = false);
    composer.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
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
      if (isClipboardTemporary && !await File(attachment.path).exists()) {
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
    final submission = ComposerSubmission(
      prompt: composer.text.trim(),
      attachments: List.unmodifiable(_attachments),
      includeWorkspace: _includeWorkspace,
      goal: _goalMode ? composer.text.trim() : _goal,
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
      _selectedSkillPaths.clear();
      _includeWorkspace = false;
      _recordSkill = false;
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
        await _editGoal();
      case AddMenuActionKind.plan:
        setState(() => _planMode = !_planMode);
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
    final current = composer.text;
    final selection = composer.selection;
    final rawStart = selection.isValid ? selection.start : current.length;
    final rawEnd = selection.isValid ? selection.end : current.length;
    final start = rawStart.clamp(0, current.length);
    final end = rawEnd.clamp(0, current.length);
    final lower = start < end ? start : end;
    final upper = start < end ? end : start;
    composer.value = TextEditingValue(
      text: current.replaceRange(lower, upper, pastedText),
      selection: TextSelection.collapsed(offset: lower + pastedText.length),
    );
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

  Future<void> _editGoal() async {
    var draft = _goal ?? '';
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('composer-goal-dialog'),
        title: const Text('设置目标'),
        content: SizedBox(
          width: 480,
          child: TextFormField(
            key: const Key('composer-goal-field'),
            initialValue: draft,
            onChanged: (value) => draft = value,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '描述这个任务需要持续追求的结果'),
          ),
        ),
        actions: [
          if (_goal?.isNotEmpty == true)
            TextButton(
              key: const Key('clear-composer-goal'),
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('清除'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('save-composer-goal'),
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('设置'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _goal = result.isEmpty ? null : result);
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
        description: _planMode ? '已开启计划模式' : '开启计划模式',
        selected: _planMode,
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
          if (_showSlashMenu) ...[
            ComposerSlashCommandMenu(
              commands: _filteredSlashCommands,
              skills: _filteredSlashSkills,
              showSkills: _showSlashSkills,
              skillsLoading: controller.skillsLoading,
              skillsError: controller.skillsError,
              searchQuery: _currentSlashQuery ?? '',
              commandScrollKeys: _slashCommandScrollKeys,
              skillScrollKeys: _slashSkillScrollKeys,
              selectedIndex: _slashMenuSelectedIndex.clamp(
                0,
                math.max(
                  0,
                  (_showSlashSkills
                              ? _filteredSlashSkills
                              : _filteredSlashCommands)
                          .length +
                      (_showSlashSkills ? _filteredSlashCommands.length : 0) -
                      1,
                ),
              ),
              onSelected: (command) {
                unawaited(_selectSlashCommand(command));
              },
              onSkillSelected: _selectSlashSkill,
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
                          ConstrainedBox(
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
                                    if (_showSlashMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.arrowDown,
                                      ): () =>
                                          _moveSlashMenuSelection(1),
                                    if (_showSlashMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.arrowUp,
                                      ): () =>
                                          _moveSlashMenuSelection(-1),
                                    if (_showSlashMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.tab,
                                      ): _selectFocusedSlashCommand,
                                    if (_showSlashMenu)
                                      const SingleActivator(
                                        LogicalKeyboardKey.escape,
                                      ): _dismissSlashMenu,
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
                                        !_showSlashMenu &&
                                        !_codeReviewOptionsVisible &&
                                        !_mcpStatusVisible)
                                      const SingleActivator(
                                        LogicalKeyboardKey.enter,
                                      ): _submitFromKeyboard,
                                    if (!imeIsComposing && _showSlashMenu)
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
                          if (_hasComposerContext) ...[
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
                                      onRemove: () =>
                                          setState(() => _planMode = false),
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
                                        onTap: () =>
                                            setState(() => _goalMode = false),
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
