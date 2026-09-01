import 'dart:convert';

import 'package:chatgpt/src/domain/workspace_configuration.dart';
import 'package:chatgpt/src/domain/scheduled_task.dart';
import 'codex_keychain_storage.dart';

/// 将本机 Codex Desk 偏好保存到项目目录之外。
/// Stores local Codex Desk preferences outside user projects.
class RuntimeConfigurationStore {
  RuntimeConfigurationStore({CodexKeychainStorage? storage})
    : _storage = storage ?? CodexKeychainStorage();

  static const _executableKey = 'codex_desk.runtime.executable.v1';
  static const _workspaceKey = 'codex_desk.workspace.last_path.v1';
  static const _additionalWorkspacesKey =
      'codex_desk.workspace.additional_paths.v1';
  static const _workspacesKey = 'codex_desk.workspaces.v2';
  static const _pinnedWorkspacesKey = 'codex_desk.workspaces.pinned.v1';
  static const _reasoningEffortKey = 'codex_desk.reasoning_effort.v1';
  static const _modelKey = 'codex_desk.model.selected.v1';
  static const _approvalModeKey = 'codex_desk.approval_mode.v1';
  static const _browserEnabledKey = 'codex_desk.browser.enabled.v1';
  static const _scheduledTasksKey = 'codex_desk.scheduled_tasks.v1';

  final CodexKeychainStorage _storage;

  /// 读取用户覆盖的 Codex 可执行文件路径。
  /// Reads the user-overridden Codex executable path.
  Future<String?> readExecutable() => _storage.read(key: _executableKey);

  /// 保存用户选择的 Codex 可执行文件路径。
  /// Saves the user-selected Codex executable path.
  Future<void> saveExecutable(String executable) {
    return _storage.write(key: _executableKey, value: executable);
  }

  /// 删除已保存的可执行文件路径，恢复自动发现。
  /// Deletes the saved executable path and restores automatic discovery.
  Future<void> clear() => _storage.delete(key: _executableKey);

  /// 读取上次成功选择的本地项目路径。
  /// Reads the last successfully selected local workspace path.
  Future<String?> readWorkspace() => _storage.read(key: _workspaceKey);

  /// 保存最近选择的本地项目路径。
  /// Saves the most recently selected local workspace path.
  Future<void> saveWorkspace(String workspace) {
    return _storage.write(key: _workspaceKey, value: workspace);
  }

  /// 清除失效或不再使用的本地项目路径。
  /// Clears an invalid or no-longer-used local workspace path.
  Future<void> clearWorkspace() => _storage.delete(key: _workspaceKey);

  /// 读取旧版当前工作区的附加目录；损坏数据会安全地视为空列表。
  /// Reads legacy additional directories for the current workspace, safely treating damaged data as an empty list.
  Future<List<String>> readAdditionalWorkspaces() async {
    final stored = await _storage.read(key: _additionalWorkspacesKey);
    if (stored == null || stored.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return const [];
      return decoded
          .whereType<String>()
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  /// 镜像保存当前工作区的旧版附加目录偏好；空列表会删除对应键。
  /// Mirrors the current workspace into the legacy additional-directory preference; an empty list removes its key.
  Future<void> saveAdditionalWorkspaces(List<String> workspaces) {
    if (workspaces.isEmpty) {
      return _storage.delete(key: _additionalWorkspacesKey);
    }
    return _storage.write(
      key: _additionalWorkspacesKey,
      value: jsonEncode(workspaces),
    );
  }

  /// 读取所有已保存工作区；损坏条目会被忽略，旧版单工作区数据由控制器迁移。
  /// Reads every saved workspace, ignoring damaged entries while the controller migrates legacy single-workspace data.
  Future<List<WorkspaceConfiguration>> readWorkspaces() async {
    final stored = await _storage.read(key: _workspacesKey);
    if (stored == null || stored.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(WorkspaceConfiguration.fromJson)
          .where((workspace) => workspace.primaryPath.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  /// 保存可切换工作区列表；空列表会删除对应偏好，但不会删除任何目录。
  /// Saves the switchable workspace list; an empty list removes only the preference and never deletes directories.
  Future<void> saveWorkspaces(List<WorkspaceConfiguration> workspaces) {
    if (workspaces.isEmpty) return _storage.delete(key: _workspacesKey);
    return _storage.write(
      key: _workspacesKey,
      value: jsonEncode(
        workspaces.map((workspace) => workspace.toJson()).toList(),
      ),
    );
  }

  /// Reads the locally pinned workspace paths.
  /// 读取本地置顶的工作区路径。
  Future<Set<String>> readPinnedWorkspaces() async {
    final stored = await _storage.read(key: _pinnedWorkspacesKey);
    if (stored == null || stored.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toSet();
    } on FormatException {
      return <String>{};
    }
  }

  /// Saves locally pinned workspace paths; an empty set removes the preference.
  /// 保存本地置顶的工作区路径；空集合会删除对应偏好。
  Future<void> savePinnedWorkspaces(Iterable<String> workspaces) {
    final paths = workspaces
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (paths.isEmpty) return _storage.delete(key: _pinnedWorkspacesKey);
    return _storage.write(key: _pinnedWorkspacesKey, value: jsonEncode(paths));
  }

  /// 读取用户保存的推理强度标识。
  /// Reads the user's saved reasoning-effort identifier.
  Future<String?> readReasoningEffort() =>
      _storage.read(key: _reasoningEffortKey);

  /// 保存推理强度；传入 `null` 时清除用户偏好。
  /// Saves reasoning effort; passing `null` clears the user preference.
  Future<void> saveReasoningEffort(String? effort) {
    if (effort == null) return _storage.delete(key: _reasoningEffortKey);
    return _storage.write(key: _reasoningEffortKey, value: effort);
  }

  /// 读取 Codex Desk 为后续新建任务保存的模型；`null` 表示跟随 Codex 配置。
  /// Reads the model Codex Desk saved for subsequent new tasks; `null` means follow Codex configuration.
  Future<String?> readModel() => _storage.read(key: _modelKey);

  /// 保存后续新建任务的模型；传入 `null` 时恢复为跟随 Codex 配置。
  /// Saves the model for subsequent new tasks; passing `null` restores configuration-following behavior.
  Future<void> saveModel(String? model) {
    if (model == null) return _storage.delete(key: _modelKey);
    return _storage.write(key: _modelKey, value: model);
  }

  /// 读取用户保存的审批模式标识；`null` 表示使用安全的请求批准默认值。
  /// Reads the user's saved approval-mode identifier; `null` uses the safe request-approval default.
  Future<String?> readApprovalMode() => _storage.read(key: _approvalModeKey);

  /// 保存审批模式；传入 `null` 时清除用户偏好并恢复默认行为。
  /// Saves the approval mode; passing `null` clears the user preference and restores default behavior.
  Future<void> saveApprovalMode(String? mode) {
    if (mode == null) return _storage.delete(key: _approvalModeKey);
    return _storage.write(key: _approvalModeKey, value: mode);
  }

  /// Reads whether agent-triggered in-app browser navigation is enabled.
  Future<bool> readBrowserEnabled() async {
    final stored = await _storage.read(key: _browserEnabledKey);
    if (stored == null) return true;
    return stored.trim().toLowerCase() != 'false';
  }

  /// Saves the local policy for agent-triggered in-app browser navigation.
  Future<void> saveBrowserEnabled(bool enabled) {
    return _storage.write(key: _browserEnabledKey, value: enabled.toString());
  }

  /// Reads locally scheduled prompts. Invalid entries are ignored so a damaged
  /// single schedule does not prevent the rest of the application from loading.
  Future<List<ScheduledTask>> readScheduledTasks() async {
    final stored = await _storage.read(key: _scheduledTasksKey);
    if (stored == null || stored.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return const [];
      return decoded
          .map((value) {
            try {
              return ScheduledTask.fromJson(value);
            } on FormatException {
              return null;
            }
          })
          .whereType<ScheduledTask>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  /// Saves scheduled prompts outside project folders; an empty list clears the
  /// preference without touching any project or conversation history.
  Future<void> saveScheduledTasks(Iterable<ScheduledTask> tasks) {
    final values = tasks.map((task) => task.toJson()).toList(growable: false);
    if (values.isEmpty) return _storage.delete(key: _scheduledTasksKey);
    return _storage.write(key: _scheduledTasksKey, value: jsonEncode(values));
  }
}
