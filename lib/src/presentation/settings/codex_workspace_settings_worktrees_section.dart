import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/domain/local_worktree_record.dart';
import 'package:chatgpt/src/domain/worktree_settings.dart';

class SettingsWorktreesSection extends StatelessWidget {
  const SettingsWorktreesSection({
    super.key,
    required this.rootController,
    required this.retentionController,
    required this.settings,
    required this.worktrees,
    required this.loading,
    required this.error,
    required this.buildSettingRow,
    required this.onSaveSettings,
    required this.onRestoreWorktree,
    required this.onRefresh,
  });

  final TextEditingController rootController;
  final TextEditingController retentionController;
  final WorktreeSettings settings;
  final List<LocalWorktreeRecord> worktrees;
  final bool loading;
  final String? error;
  final Widget Function({
    required String title,
    required String description,
    Widget? trailing,
  })
  buildSettingRow;
  final Future<void> Function(WorktreeSettings next) onSaveSettings;
  final Future<void> Function(LocalWorktreeRecord record) onRestoreWorktree;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: 38,
      fontWeight: FontWeight.w500,
    );
    final body = <Widget>[];
    if (loading) {
      body.add(const Center(child: CircularProgressIndicator()));
    } else if (error != null) {
      body.add(Text('无法读取工作树：$error', key: const Key('worktrees-error-state')));
    } else if (worktrees.isEmpty) {
      body.add(const Center(child: Text('ChatGPT 创建的工作树将显示在此处')));
    } else {
      body.addAll(
        worktrees.map(
          (item) => ListTile(
            title: Text(item.worktreeId),
            subtitle: Text(item.worktreePath),
            trailing: item.state == LocalWorktreeState.removed
                ? TextButton(
                    key: Key('worktree-restore-${item.worktreeId}'),
                    onPressed: () => onRestoreWorktree(item),
                    child: const Text('恢复'),
                  )
                : Text(item.state.name),
          ),
        ),
      );
    }
    return ListView(
      key: const Key('settings-worktrees-page'),
      padding: const EdgeInsets.fromLTRB(72, 36, 72, 72),
      children: <Widget>[
        Text('Worktrees', style: heading),
        const SizedBox(height: 28),
        Card(
          child: Column(
            children: <Widget>[
              buildSettingRow(
                title: '工作树根目录',
                description: 'ChatGPT 创建托管工作树的目录。此目录使用默认位置。',
                trailing: SizedBox(
                  width: 260,
                  child: TextField(
                    key: const Key('worktree-root-field'),
                    controller: rootController,
                    onSubmitted: (value) => onSaveSettings(
                      settings.copyWith(rootPath: value.trim()),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              buildSettingRow(
                title: '创建工作树时获取更新',
                description: '创建每个新工作树时获取 Git 远端更新。',
                trailing: Switch(
                  key: const Key('worktree-fetch-toggle'),
                  value: settings.fetchBeforeCreate,
                  onChanged: (value) => onSaveSettings(
                    settings.copyWith(fetchBeforeCreate: value),
                  ),
                ),
              ),
              const Divider(height: 1),
              buildSettingRow(
                title: '自动删除工作树',
                description: '超出保留数量后自动清理已完成的托管工作树。',
                trailing: Switch(
                  key: const Key('worktree-cleanup-toggle'),
                  value: settings.autoCleanup,
                  onChanged: (value) =>
                      onSaveSettings(settings.copyWith(autoCleanup: value)),
                ),
              ),
              const Divider(height: 1),
              buildSettingRow(
                title: '自动删除限制',
                description: '要保留的托管工作树数量。',
                trailing: SizedBox(
                  width: 72,
                  child: TextField(
                    key: const Key('worktree-retention-field'),
                    controller: retentionController,
                    keyboardType: TextInputType.number,
                    onSubmitted: (value) {
                      final limit = int.tryParse(value);
                      if (limit == null || limit < 1) return;
                      onSaveSettings(settings.copyWith(retentionLimit: limit));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 34),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '尚无工作树',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const Key('worktrees-refresh'),
              tooltip: '刷新工作树',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_outlined),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...body,
      ],
    );
  }
}
