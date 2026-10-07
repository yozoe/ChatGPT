import 'app_controller_live_turn_activity.dart';
import 'services/codex_app_server_support.dart';

/// Converts App Server item payloads into concise live activity descriptions.
///
/// This mapper is deliberately stateless. It does not decide whether an item
/// belongs to the active turn and it does not mutate the conversation timeline.
class CodexLiveTurnActivityMapper {
  LiveTurnActivity? map(JsonMap item) {
    final type = _label(item['type']);
    final itemId = _label(item['id']);
    if (type.isEmpty) return null;
    if (type == 'skill' ||
        (type == 'dynamicToolCall' && isSkillReadActivity(item))) {
      return LiveTurnActivity(
        itemId: itemId,
        kind: 'skillRead',
        label: skillReadLabel(item),
      );
    }
    if (type == 'reasoning') {
      final summary = reasoningSummaryFromItem(item);
      return LiveTurnActivity(
        itemId: itemId,
        kind: type,
        label: summary.isEmpty ? '正在分析' : summary,
      );
    }
    if (type == 'commandExecution') {
      final commandAction = commandActionLiveActivity(item);
      if (commandAction != null) {
        return LiveTurnActivity(
          itemId: itemId,
          kind: commandAction.$1,
          label: commandAction.$2,
          detail: commandAction.$3,
        );
      }
    }
    if (isCollaborationActivityKind(type)) {
      final status = collaborationStatus(item, live: true);
      return LiveTurnActivity(
        itemId: itemId,
        kind: type,
        label: collaborationName(item),
        detail: status.$2,
        linkedThreadId: collaborationThreadId(item),
        prompt: _label(item['prompt']),
        status: status.$1,
      );
    }
    final (label, detail) = switch (type) {
      'agentMessage' => ('正在撰写回复', ''),
      'plan' => ('正在整理计划', ''),
      'commandExecution' => ('正在运行命令', _label(item['command'])),
      'mcpToolCall' => (
        '正在调用 MCP 工具',
        joinLiveActivityDetail(item['server'], item['tool']),
      ),
      'dynamicToolCall' => (
        '正在调用动态工具',
        joinLiveActivityDetail(item['namespace'], item['tool']),
      ),
      'webSearch' => webSearchLiveActivity(item),
      'imageView' => ('正在查看图片', _label(item['path'])),
      'imageGeneration' => ('正在生成图片', ''),
      'sleep' => (
        '正在等待',
        _label(item['durationMs']).isEmpty
            ? ''
            : '${_label(item['durationMs'])} ms',
      ),
      'fileChange' => ('正在编辑文件', ''),
      'contextCompaction' => ('正在压缩对话上下文', ''),
      'enteredReviewMode' => ('正在进入审查模式', ''),
      'exitedReviewMode' => ('正在退出审查模式', ''),
      'userMessage' => (null, ''),
      _ => ('正在执行操作', ''),
    };
    if (label == null) return null;
    return LiveTurnActivity(
      itemId: itemId,
      kind: type,
      label: label,
      detail: detail,
    );
  }

  (String, String, String)? commandActionLiveActivity(JsonMap item) {
    final rawActions =
        item['commandActions'] ??
        item['command_actions'] ??
        item['parsedCmd'] ??
        item['parsed_cmd'];
    if (rawActions is! Iterable) return null;
    final actions = rawActions.whereType<Map>().toList(growable: false);
    if (actions.length != 1) return null;
    final action = JsonMap.from(actions.single);
    switch (_label(action['type'])) {
      case 'read':
        final target = _fileActivityTarget(
          action['name'],
          fallback: action['path'],
        );
        return ('fileRead', '正在读取', target);
      case 'search':
        final query = _label(action['query']);
        final folder = _fileActivityTarget(action['path']);
        final detail = switch ((query, folder)) {
          ('', '') => '文件夹中的文件',
          ('', final folder) => '$folder 文件夹中的文件',
          (final query, '') => '“$query”',
          (final query, final folder) => '“$query” · $folder 文件夹',
        };
        return ('fileSearch', '正在搜索', detail);
      case 'listFiles':
        final target = _fileActivityTarget(action['path']);
        return (
          'fileList',
          '正在列出',
          target.isEmpty ? '当前文件夹中的文件' : '$target 文件夹中的文件',
        );
    }
    return null;
  }

  (String, String) webSearchLiveActivity(JsonMap item) {
    final action = item['action'];
    final actionMap = action is Map ? action : const <String, Object?>{};
    final actionType = _label(actionMap['type']);
    return switch (actionType) {
      'openPage' => ('正在打开网页', _label(actionMap['url'] ?? item['url'])),
      'findInPage' => (
        '正在页内查找',
        _label(actionMap['pattern'] ?? actionMap['query'] ?? item['query']),
      ),
      _ => ('正在搜索网页', _label(actionMap['query'] ?? item['query'])),
    };
  }

  bool isSkillReadActivity(JsonMap item) {
    final namespace = _label(item['namespace']).toLowerCase();
    final tool = _label(item['tool']).toLowerCase();
    final operation = '$namespace/$tool';
    final referencesSkill = operation.contains('skill');
    final readsContent = RegExp(r'read|load|open|fetch').hasMatch(operation);
    return referencesSkill && (readsContent || tool == 'skill');
  }

  String skillReadLabel(JsonMap item) {
    final skillName = skillNameFor(item);
    return skillName.isEmpty ? '正在读取技能' : '正在读取 $skillName 技能';
  }

  String skillNameFor(JsonMap item) {
    for (final value in [
      item['skillName'],
      item['skill'],
      item['skillPath'],
      item['path'],
      if (_label(item['type']) == 'skill') item['name'],
      item['arguments'],
      item['input'],
      item['params'],
    ]) {
      final name = _skillNameFromValue(value);
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  String joinLiveActivityDetail(Object? scope, Object? action) {
    final scopeLabel = _label(scope);
    final actionLabel = _label(action);
    if (scopeLabel.isEmpty) return actionLabel;
    if (actionLabel.isEmpty) return scopeLabel;
    return '$scopeLabel/$actionLabel';
  }

  String reasoningSummaryFromItem(JsonMap item) {
    final summaries = item['summary'];
    if (summaries is! Iterable) return '';
    for (final summary in summaries.toList().reversed) {
      final text = summary is Map ? _label(summary['text']) : _label(summary);
      final cleaned = cleanReasoningSummary(text);
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '';
  }

  String cleanReasoningSummary(String value) {
    var result = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    result = result.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    return result
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('`', '')
        .trim();
  }

  bool isCollaborationItem(JsonMap item) =>
      isCollaborationActivityKind(_label(item['type']));

  bool isCollaborationActivityKind(String kind) =>
      kind == 'collabToolCall' || kind == 'subAgentActivity';

  String collaborationActivityId(JsonMap item) {
    for (final key in [
      'agentThreadId',
      'agent_thread_id',
      'receiverThreadId',
      'receiver_thread_id',
      'newThreadId',
      'new_thread_id',
      'id',
    ]) {
      final value = _label(item[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String? collaborationThreadId(JsonMap item) {
    for (final key in [
      'agentThreadId',
      'agent_thread_id',
      'newThreadId',
      'new_thread_id',
      'receiverThreadId',
      'receiver_thread_id',
    ]) {
      final value = _label(item[key]);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String collaborationName(JsonMap item) {
    for (final value in [item['agentStatus'], item]) {
      final name = _collaborationNameFromValue(value);
      if (name.isNotEmpty) return name;
    }
    final prompt = _label(item['prompt']).toLowerCase();
    if (prompt.contains('review') || prompt.contains('审查')) {
      return 'Independent review';
    }
    final agentPath = _firstNonEmptyLabel([
      item['agentPath'],
      item['agent_path'],
    ]);
    if (agentPath.isNotEmpty) {
      return agentPath
              .split('/')
              .where((segment) => segment.isNotEmpty)
              .lastOrNull ??
          agentPath;
    }
    return 'Independent task';
  }

  bool isGenericCollaborationName(String value) =>
      value == 'Independent task' || value == '协作任务';

  (String, String) collaborationStatus(JsonMap item, {required bool live}) {
    var rawStatus = _collaborationStatusFromValue(item['agentStatus']);
    if (rawStatus.isEmpty && _label(item['type']) == 'subAgentActivity') {
      rawStatus = normalizedActivityValue(item['kind']);
    }
    final tool = normalizedActivityValue(item['tool']);
    if (rawStatus.isEmpty) {
      if (tool.contains('spawn')) {
        rawStatus = 'working';
      } else if (tool.contains('interrupt') || tool.contains('close')) {
        rawStatus = 'stopped';
      } else if (tool.contains('wait') || tool.contains('join')) {
        rawStatus = live ? 'working' : normalizedActivityValue(item['status']);
      } else {
        rawStatus = normalizedActivityValue(item['status']);
      }
    }
    final normalized = switch (rawStatus) {
      'pending' ||
      'starting' ||
      'started' ||
      'interacted' ||
      'active' ||
      'inprogress' ||
      'running' ||
      'working' => 'working',
      'completed' ||
      'complete' ||
      'done' ||
      'success' ||
      'succeeded' ||
      'idle' => 'completed',
      'failed' || 'failure' || 'error' || 'errored' => 'failed',
      'interrupted' ||
      'cancelled' ||
      'canceled' ||
      'stopped' ||
      'shutdown' => 'stopped',
      _ => live ? 'working' : 'unknown',
    };
    final label = switch (normalized) {
      'working' => '已开始工作',
      'completed' => '已完成',
      'failed' => '失败',
      'stopped' => '已停止',
      _ => '状态已更新',
    };
    return (normalized, label);
  }

  String normalizedActivityValue(Object? value) =>
      _label(value).toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  String _fileActivityTarget(Object? value, {Object? fallback}) {
    final raw = _label(value).isEmpty ? _label(fallback) : _label(value);
    if (raw.isEmpty) return '';
    final normalized = raw.replaceFirst(RegExp(r'[/\\]+$'), '');
    return normalized.split(RegExp(r'[/\\]')).last;
  }

  String _skillNameFromValue(Object? value) {
    if (value is String) return _displaySkillName(value);
    if (value is! Map) return '';
    for (final key in ['displayName', 'skillName', 'name', 'id', 'path']) {
      final name = _skillNameFromValue(value[key]);
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  String _displaySkillName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';
    final pathMatch = RegExp(
      r'([^/\\]+)[/\\]SKILL\.md$',
      caseSensitive: false,
    ).firstMatch(normalized);
    final name = pathMatch?.group(1) ?? normalized;
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(name)) return name;
    return name
        .split(RegExp(r'[-_]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _collaborationNameFromValue(Object? value) {
    if (value is! Map) return '';
    for (final key in [
      'displayName',
      'display_name',
      'taskName',
      'task_name',
      'agentName',
      'agent_name',
      'name',
      'label',
    ]) {
      final candidate = _label(value[key]);
      if (candidate.isNotEmpty && candidate.length <= 80) return candidate;
    }
    for (final candidate in value.values) {
      final nested = _collaborationNameFromValue(candidate);
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  String _collaborationStatusFromValue(Object? value) {
    if (value is String) return normalizedActivityValue(value);
    if (value is! Map) return '';
    for (final key in [
      'status',
      'state',
      'type',
      'agentStatus',
      'agent_status',
    ]) {
      final status = _collaborationStatusFromValue(value[key]);
      if (status.isNotEmpty) return status;
    }
    for (final candidate in value.values) {
      if (candidate is! Map) continue;
      final status = _collaborationStatusFromValue(candidate);
      if (status.isNotEmpty) return status;
    }
    return '';
  }

  String _firstNonEmptyLabel(Iterable<Object?> values) {
    for (final value in values) {
      final label = _label(value);
      if (label.isNotEmpty) return label;
    }
    return '';
  }

  String _label(Object? value) => value?.toString().trim() ?? '';
}
