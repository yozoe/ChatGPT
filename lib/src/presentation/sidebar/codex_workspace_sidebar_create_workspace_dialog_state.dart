// Extracted class from codex_workspace_sidebar.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, use_key_in_widget_constructors
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_support.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_create_workspace_dialog.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_name_field.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar_workspace_sources_card.dart';

class CreateWorkspaceDialogState extends State<CreateWorkspaceDialog> {
  final _nameController = TextEditingController();
  final _sourceDirectories = <String>[];
  bool _draggingDirectory = false;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 打开系统目录选择器并更新弹窗中的源文件夹。
  /// Opens the native directory picker and updates the source folder in the dialog.
  Future<void> _chooseDirectory() async {
    try {
      final path = await getDirectoryPath(
        confirmButtonText: _sourceDirectories.isEmpty ? '选择文件夹' : '添加文件夹',
      );
      if (!mounted || path == null || path.trim().isEmpty) return;
      _appendDirectories([path]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器。')));
    }
  }

  /// 接收桌面拖入的目录；文件或空路径会被拒绝并提示用户。
  /// Accepts a desktop-dropped directory and rejects files or empty paths with feedback.
  void _acceptDroppedDirectories(List<DropItem> items) {
    final directories = items
        .whereType<DropItemDirectory>()
        .map((item) => item.path)
        .where((path) => path.trim().isNotEmpty)
        .toList();
    if (directories.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请拖入一个文件夹。')));
      return;
    }
    _appendDirectories(directories);
  }

  void _appendDirectories(Iterable<String> paths) {
    final additions = paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty && !_sourceDirectories.contains(path))
        .toList();
    if (additions.isEmpty || !mounted) return;
    setState(() => _sourceDirectories.addAll(additions));
  }

  /// 校验源文件夹并创建工作区，成功后关闭弹窗。
  /// Validates the source folder, creates the workspace, and closes the dialog on success.
  Future<void> _createProject() async {
    if (_sourceDirectories.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先添加一个源文件夹。')));
      return;
    }
    setState(() => _creating = true);
    final created = await widget.onCreate(
      List.unmodifiable(_sourceDirectories),
      _nameController.text,
    );
    if (!mounted) return;
    if (created) {
      Navigator.of(context).pop();
    } else {
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final hasSourceDirectory = _sourceDirectories.isNotEmpty;
    final sourceColor = _draggingDirectory ? palette.active : palette.border;
    return Dialog(
      key: const Key('create-workspace-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: palette.module,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 28, 32, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        key: const Key('create-workspace-dialog-title'),
                        '创建项目',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                      ),
                    ),
                    IconButton(
                      key: const Key('close-create-workspace-dialog'),
                      tooltip: '关闭',
                      onPressed: _creating
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                WorkspaceNameField(
                  controller: _nameController,
                  hintText: '项目名称',
                  borderColor: palette.border,
                ),
                const SizedBox(height: 25),
                Text(
                  '源文件夹',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                DropTarget(
                  key: const Key('create-workspace-folder-drop-target'),
                  onDragEntered: (_) {
                    if (mounted) setState(() => _draggingDirectory = true);
                  },
                  onDragExited: (_) {
                    if (mounted) setState(() => _draggingDirectory = false);
                  },
                  onDragDone: (details) {
                    if (mounted) setState(() => _draggingDirectory = false);
                    _acceptDroppedDirectories(details.files);
                  },
                  child: Semantics(
                    button: true,
                    label: '添加 Codex 可读取和编辑的文件夹',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('create-workspace-folder-picker'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: _creating || hasSourceDirectory
                            ? null
                            : _chooseDirectory,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          constraints: const BoxConstraints(minHeight: 190),
                          decoration: BoxDecoration(
                            color: _draggingDirectory
                                ? Color.alphaBlend(
                                    palette.active.withValues(alpha: 0.08),
                                    palette.module,
                                  )
                                : palette.module,
                            border: Border.all(
                              color: sourceColor,
                              width: _draggingDirectory ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: hasSourceDirectory
                              ? WorkspaceSourcesCard(
                                  primary: _sourceDirectories.first,
                                  additional: _sourceDirectories
                                      .skip(1)
                                      .toList(),
                                  onRemovePrimary: _creating
                                      ? null
                                      : () => setState(
                                          () => _sourceDirectories.removeAt(0),
                                        ),
                                  onRemoveAdditional: (path) async {
                                    if (!_creating) {
                                      setState(
                                        () => _sourceDirectories.remove(path),
                                      );
                                    }
                                  },
                                  onAdd: _creating
                                      ? null
                                      : () async {
                                          await _chooseDirectory();
                                          return true;
                                        },
                                )
                              : Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                      vertical: 24,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _draggingDirectory
                                              ? Icons
                                                    .drive_folder_upload_outlined
                                              : Icons
                                                    .create_new_folder_outlined,
                                          size: 20,
                                          color: palette.muted,
                                        ),
                                        const SizedBox(height: 13),
                                        Text(
                                          _draggingDirectory
                                              ? '松开即可添加文件夹'
                                              : '添加 Codex 可读取和编辑的文件夹',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: palette.trace,
                                            fontSize: 14,
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
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('cancel-create-workspace'),
                      onPressed: _creating
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.muted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 20),
                    FilledButton(
                      key: const Key('create-workspace-confirm'),
                      onPressed: _creating ? null : _createProject,
                      style: FilledButton.styleFrom(
                        foregroundColor: palette.module,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: Text(
                        _creating ? '创建中…' : '创建项目',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
