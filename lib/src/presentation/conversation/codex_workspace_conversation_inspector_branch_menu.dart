import 'dart:math' as math;

import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/theme/yeknom_workbench.dart';
import 'package:flutter/material.dart';

/// 在分支行左侧显示 Codex 风格的本地分支选择弹层。
/// Shows a Codex-style local branch picker to the left of its anchor row.
Future<void> showInspectorBranchMenu(
  BuildContext context, {
  required BuildContext anchorContext,
  required CodexController controller,
}) async {
  final workspace = controller.workspacePath;
  if (workspace == null) return;
  final currentBranch = controller.gitProjectStatus?.branch;
  final changedFiles = controller.gitProjectStatus?.changes.length ?? 0;
  List<String> branches = const [];
  String? loadError;
  try {
    branches = await controller.listGitBranches(workspace: workspace);
  } catch (error) {
    loadError = error.toString().replaceFirst('Bad state: ', '');
  }
  if (!context.mounted ||
      !anchorContext.mounted ||
      controller.workspacePath != workspace) {
    return;
  }

  final anchorBox = anchorContext.findRenderObject() as RenderBox?;
  if (anchorBox == null || !anchorBox.hasSize) return;
  final anchorOffset = anchorBox.localToGlobal(Offset.zero);
  final anchorRect = anchorOffset & anchorBox.size;
  final screenSize = MediaQuery.sizeOf(context);
  const popupWidth = 300.0;
  final popupHeight = math.min(
    360.0,
    math.max(
      190.0,
      102.0 +
          math.min(branches.length, 6) * 38.0 +
          (changedFiles > 0 ? 16.0 : 0.0),
    ),
  );
  final left = math.max(
    8.0,
    math.min(
      anchorRect.left - popupWidth - 8,
      screenSize.width - popupWidth - 8,
    ),
  );
  final top = math.max(
    8.0,
    math.min(anchorRect.top - 6, screenSize.height - popupHeight - 8),
  );
  var query = '';

  final selection = await showGeneralDialog<({String? branch, bool create})>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭分支菜单',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: Alignment.topRight,
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final palette = YeknomPalette.of(context);
          final normalizedQuery = query.trim().toLowerCase();
          final filteredBranches = branches
              .where(
                (branch) =>
                    normalizedQuery.isEmpty ||
                    branch.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);
          return Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: popupWidth,
                  height: popupHeight,
                  child: Container(
                    key: const Key('inspector-branch-menu'),
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                    decoration: BoxDecoration(
                      color: palette.field,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.controlBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.34),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('inspector-branch-search'),
                          autofocus: true,
                          onChanged: (value) =>
                              setModalState(() => query = value),
                          style: TextStyle(color: palette.trace, fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText:
                                '搜索${workspaceName(controller.workspacePath)}分支',
                            hintStyle: TextStyle(
                              color: palette.muted,
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 16,
                              color: palette.muted,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 30,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 5),
                          child: Text(
                            '分支',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: loadError != null
                              ? Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    '无法读取分支：$loadError',
                                    style: TextStyle(
                                      color: palette.fault,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : filteredBranches.isEmpty
                              ? Center(
                                  child: Text(
                                    '没有匹配的分支',
                                    style: TextStyle(
                                      color: palette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: filteredBranches.length,
                                  itemBuilder: (context, index) {
                                    final branch = filteredBranches[index];
                                    final selected = branch == currentBranch;
                                    return InkWell(
                                      key: ValueKey(
                                        'inspector-branch-option-$branch',
                                      ),
                                      borderRadius: BorderRadius.circular(7),
                                      onTap: () => Navigator.of(
                                        dialogContext,
                                      ).pop((branch: branch, create: false)),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? palette.raised
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.account_tree_outlined,
                                              size: 15,
                                              color: palette.muted,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    branch,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: palette.trace,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  if (selected &&
                                                      changedFiles > 0)
                                                    Text(
                                                      '未提交：$changedFiles 个文件',
                                                      style: TextStyle(
                                                        color: palette.muted,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (selected)
                                              Icon(
                                                Icons.check,
                                                size: 15,
                                                color: palette.trace,
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Divider(height: 1, color: palette.controlBorder),
                        InkWell(
                          key: const Key('inspector-create-branch'),
                          borderRadius: BorderRadius.circular(7),
                          onTap: () => Navigator.of(
                            dialogContext,
                          ).pop((branch: null, create: true)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 16, color: palette.trace),
                                const SizedBox(width: 7),
                                Text(
                                  '创建并检出新分支...',
                                  style: TextStyle(
                                    color: palette.trace,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  if (!context.mounted ||
      selection == null ||
      selection.branch == currentBranch ||
      controller.workspacePath != workspace) {
    return;
  }

  if (selection.create) {
    final branch = await showCreateInspectorBranchDialog(context);
    if (!context.mounted ||
        branch == null ||
        controller.workspacePath != workspace) {
      return;
    }
    final succeeded = await controller.createAndCheckoutGitBranch(
      branch,
      workspace: workspace,
    );
    if (!succeeded && context.mounted) {
      showInspectorBranchError(context, controller.gitOperationError);
    }
    return;
  }

  final branch = selection.branch;
  if (branch == null) return;
  final succeeded = await controller.checkoutGitBranch(
    branch,
    workspace: workspace,
  );
  if (!succeeded && context.mounted) {
    showInspectorBranchError(context, controller.gitOperationError);
  }
}

String workspaceName(String? path) {
  if (path == null || path.trim().isEmpty) return '项目';
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? '项目' : parts.last;
}

Future<String?> showCreateInspectorBranchDialog(BuildContext context) {
  var branch = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('创建并检出新分支'),
      content: TextField(
        key: const Key('inspector-new-branch-field'),
        autofocus: true,
        onChanged: (value) => branch = value,
        onSubmitted: (value) {
          final name = value.trim();
          if (name.isNotEmpty) Navigator.of(dialogContext).pop(name);
        },
        decoration: const InputDecoration(hintText: '分支名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = branch.trim();
            if (name.isNotEmpty) Navigator.of(dialogContext).pop(name);
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
}

void showInspectorBranchError(BuildContext context, String? error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error ?? '无法切换 Git 分支。')));
}
