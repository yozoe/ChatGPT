// Shared declarations extracted from codex_workspace_timeline.dart.
// ignore_for_file: unused_import, unnecessary_import, duplicate_import, invalid_annotation_target
import 'dart:math' as math;
import 'package:markdown/markdown.dart' as md;
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline_agent_linked_image.dart';
// ignore_for_file: use_key_in_widget_constructors

import 'dart:math' as math;

import 'package:markdown/markdown.dart' as md;

import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';

/// Couples a timeline entry to its stable source index while it is grouped.

/// A completed turn's duration pill and its disclosure content, matching the
/// Codex desktop timeline where the duration controls the turn details.

String activitySummary(List<TimelineEntry> entries) {
  final actions = <String>{};
  for (final entry in entries) {
    if (isAutoApprovalActivity(entry)) continue;
    final label = '${entry.title}\n${entry.detail}'.toLowerCase();
    if (entry.kind == TimelineKind.command) {
      actions.add('运行了命令');
    } else if (label.contains('read') || label.contains('读取')) {
      actions.add('读取了文件');
    } else if (label.contains('search') || label.contains('搜索')) {
      actions.add('进行了搜索');
    } else {
      actions.add('使用了工具');
    }
  }
  if (actions.isEmpty) return '已批准了操作';
  return '已${actions.join('并')}';
}

String activityLabel(TimelineEntry entry) {
  if (entry.kind == TimelineKind.command) {
    final command = entry.detail.split('\n').first.trim();
    return command.isEmpty ? '已运行命令' : '已运行 $command';
  }
  return entry.title.isEmpty ? '已使用工具' : entry.title;
}

IconData activityIcon(TimelineEntry entry) {
  if (entry.kind == TimelineKind.command) return Icons.terminal_outlined;
  final label = '${entry.title}\n${entry.detail}'.toLowerCase();
  if (label.contains('read') || label.contains('读取')) {
    return Icons.menu_book_outlined;
  }
  if (label.contains('search') || label.contains('搜索')) {
    return Icons.search;
  }
  if (label.contains('image') || label.contains('图片')) {
    return Icons.image_outlined;
  }
  return Icons.build_outlined;
}

/// 缓存未变化消息的渲染子树，避免流式增量反复解析所有既有 Markdown。
/// Caches unchanged message subtrees so streaming deltas do not repeatedly parse all prior Markdown.

/// Keeps completed skill and subagent lifecycle events visible at their real
/// position in the conversation instead of collapsing them as generic tools.

/// Keeps timestamp disclosure local to one user bubble so pointer movement in
/// one message cannot rebuild or alter another conversation item.

String messageTimeLabel(DateTime createdAt) {
  final local = createdAt.toLocal();
  return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
}

/// Displays a server-declared current activity. Unlike the generic thinking
/// row, this wording is only used when App Server has identified the item.

IconData? liveActivityIcon(String kind) => switch (kind) {
  'reasoning' => null,
  'skillRead' => Icons.auto_stories_outlined,
  'fileRead' => Icons.menu_book_outlined,
  'fileSearch' => Icons.search,
  'fileList' => Icons.folder_outlined,
  'fileChange' => Icons.edit_outlined,
  'agentMessage' => Icons.rate_review_outlined,
  'webSearch' => Icons.search,
  'mcpToolCall' || 'dynamicToolCall' => Icons.build_outlined,
  'imageView' || 'imageGeneration' => Icons.image_outlined,
  'sleep' => Icons.schedule_outlined,
  'enteredReviewMode' || 'exitedReviewMode' => Icons.fact_check_outlined,
  'collabToolCall' => Icons.auto_awesome,
  _ => Icons.more_horiz,
};

/// A quiet, temporary command indicator matching Codex's activity stream.
/// It is replaced by the existing collapsible command history once complete.

/// 为实时活动文字提供与“正在思考”一致的低干扰扫光效果。
/// Applies the same subtle moving highlight used by “thinking” to live
/// activity labels while respecting the platform's reduced-motion setting.

/// 在任务运行期间每秒更新“已处理”时长，完成后由固定的“耗时”记录替代。
/// Updates the in-progress “processed” time each second; completion replaces
/// it with the permanent “duration” timeline record.

/// Formats a live duration without giving the running state a final outcome.
String formatLiveElapsedDuration(Duration duration) {
  final seconds = duration.inSeconds;
  final hours = seconds ~/ Duration.secondsPerHour;
  final minutes =
      (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final remainingSeconds = seconds % Duration.secondsPerMinute;
  final parts = <String>[];
  if (hours > 0) parts.add('$hours 小时');
  if (minutes > 0 || hours > 0) parts.add('$minutes 分钟');
  parts.add('$remainingSeconds 秒');
  return parts.join(' ');
}

/// A quiet, live turn indicator shown while Codex is deciding its next step.
/// It yields to the command row when App Server reports an active command.
/// Codex 正在决定下一步时显示的安静状态提示；App Server 报告活动命令后让位给命令行。

/// 在用户消息中展示随消息发送的本地图片缩略图。
/// Renders thumbnails for local images sent alongside a user message.

/// Keeps an unfinished reply, or a completed reply still preflighting local
/// links, on one append-only text layout. Parsing partial Markdown on every
/// token can repeatedly reinterpret an open list, link, or code fence and
/// change earlier block heights; a forced strut also prevents late fallback
/// glyphs from changing the current line's ascent or descent.
/// 未完成回复或仍在预检本地链接的完成回复使用单一、只追加的文本布局；避免
/// 不完整 Markdown 反复改变既有块结构，并以固定 strut 防止字体回退改变行高。

/// Hides inline Markdown destinations as soon as `[label](` is complete.
/// Agent file links commonly contain long absolute paths which are invisible
/// in final Markdown but otherwise wrap across several lines while streaming,
/// then collapse to one file row at completion. Keeping only the visible label
/// makes the streaming and final layouts use comparable text widths.
String stableStreamingAgentText(String data) {
  final output = StringBuffer();
  var cursor = 0;
  var codeDelimiterLength = 0;
  var codeDelimiter = 0;
  var codeIsFence = false;
  while (cursor < data.length) {
    final codeUnit = data.codeUnitAt(cursor);
    final possibleCodeDelimiter = codeUnit == 0x60 || codeUnit == 0x7e;
    if (possibleCodeDelimiter &&
        (codeDelimiterLength > 0
            ? codeUnit == codeDelimiter
            : codeUnit == 0x60 || isMarkdownFenceStart(data, cursor))) {
      var delimiterEnd = cursor;
      while (delimiterEnd < data.length &&
          data.codeUnitAt(delimiterEnd) == codeUnit) {
        delimiterEnd++;
      }
      final delimiterLength = delimiterEnd - cursor;
      if (codeDelimiterLength == 0) {
        final fence =
            delimiterLength >= 3 && isMarkdownFenceStart(data, cursor);
        if (codeUnit == 0x7e && !fence) {
          output.writeCharCode(codeUnit);
          cursor++;
          continue;
        }
        codeDelimiterLength = delimiterLength;
        codeDelimiter = codeUnit;
        codeIsFence = fence;
      } else if (codeIsFence
          ? delimiterLength >= codeDelimiterLength &&
                isMarkdownFenceStart(data, cursor) &&
                isMarkdownFenceEnd(data, delimiterEnd)
          : delimiterLength == codeDelimiterLength) {
        codeDelimiterLength = 0;
        codeDelimiter = 0;
        codeIsFence = false;
      }
      output.write(data.substring(cursor, delimiterEnd));
      cursor = delimiterEnd;
      continue;
    }
    if (codeDelimiterLength > 0) {
      output.writeCharCode(data.codeUnitAt(cursor++));
      continue;
    }
    if (data.codeUnitAt(cursor) == 0x5c && cursor + 1 < data.length) {
      output
        ..writeCharCode(data.codeUnitAt(cursor++))
        ..writeCharCode(data.codeUnitAt(cursor++));
      continue;
    }
    final image = data.startsWith('![', cursor);
    if (data.codeUnitAt(cursor) != 0x5b && !image) {
      output.writeCharCode(data.codeUnitAt(cursor++));
      continue;
    }

    final labelStart = cursor + (image ? 2 : 1);
    var labelEnd = -1;
    var escaped = false;
    for (var index = labelStart; index + 1 < data.length; index++) {
      final codeUnit = data.codeUnitAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (codeUnit == 0x5c) {
        escaped = true;
        continue;
      }
      if (codeUnit == 0x5d && data.codeUnitAt(index + 1) == 0x28) {
        labelEnd = index;
        break;
      }
    }
    if (labelEnd < 0) {
      output.writeCharCode(data.codeUnitAt(cursor++));
      continue;
    }

    final label = data.substring(labelStart, labelEnd);
    final destinationStart = labelEnd + 2;
    cursor = destinationStart;
    var depth = 1;
    escaped = false;
    while (cursor < data.length && depth > 0) {
      final codeUnit = data.codeUnitAt(cursor++);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (codeUnit == 0x5c) {
        escaped = true;
      } else if (codeUnit == 0x28) {
        depth++;
      } else if (codeUnit == 0x29) {
        depth--;
      }
    }
    if (depth > 0) {
      // The destination is still receiving tokens. Showing the temporary
      // Markdown label now and replacing it with a file basename later is the
      // exact width collapse that made file references jitter.
      break;
    }
    final destination = data.substring(destinationStart, cursor - 1);
    output.write(image ? label : stableStreamingLinkLabel(label, destination));
  }
  return output.toString();
}

bool isMarkdownFenceStart(String data, int offset) {
  final lineStart = offset == 0 ? 0 : data.lastIndexOf('\n', offset - 1) + 1;
  final indentation = offset - lineStart;
  if (indentation > 3) return false;
  for (var index = lineStart; index < offset; index++) {
    if (data.codeUnitAt(index) != 0x20) return false;
  }
  return true;
}

bool isMarkdownFenceEnd(String data, int offset) {
  for (var index = offset; index < data.length; index++) {
    final codeUnit = data.codeUnitAt(index);
    if (codeUnit == 0x0a || codeUnit == 0x0d) return true;
    if (codeUnit != 0x20 && codeUnit != 0x09) return false;
  }
  return true;
}

String stableStreamingLinkLabel(String label, String destination) {
  if (!isPotentialLocalMarkdownHref(destination)) return label;
  try {
    final uri = Uri.tryParse(destination);
    var path = uri?.scheme == 'file'
        ? uri!.toFilePath()
        : Uri.decodeComponent(uri?.path ?? destination);
    path = path.replaceFirst(RegExp(r':\d+(?::\d+)?$'), '');
    final fileName = path.split(RegExp(r'[/\\]')).last;
    return fileName.isEmpty ? label : fileName;
  } on FormatException {
    return label;
  } on UnsupportedError {
    return label;
  }
}

/// 将已完成的 Codex 回复按 GitHub Flavored Markdown 渲染，并保持与工作台主题一致。
/// Renders completed Codex replies as GitHub Flavored Markdown while matching the workbench theme.

Set<String> localMarkdownLinkHrefs(String data) {
  final hrefs = <String>{};
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parse(data);

  void visit(Iterable<md.Node> values) {
    for (final node in values) {
      if (node is! md.Element) continue;
      if (node.tag == 'a') {
        final href = node.attributes['href'];
        if (href != null && isPotentialLocalMarkdownHref(href)) {
          hrefs.add(href);
        }
      }
      visit(node.children ?? const <md.Node>[]);
    }
  }

  visit(nodes);
  return hrefs;
}

bool isPotentialLocalMarkdownHref(String href) {
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(href)) return true;
  final uri = Uri.tryParse(href);
  return uri == null || uri.scheme.isEmpty || uri.scheme == 'file';
}

/// Builds normal web links as text and upgrades existing project-local files
/// to Codex-style file rows after the workspace boundary has been verified.

/// Forces content after a Markdown hard break onto a new wrap run. The
/// renderer otherwise keeps custom inline widgets, such as project file links,
/// beside a two-line text box and visually centers them against the blank line.

String agentMarkdownLinkLabel(md.Element element, String fallback) {
  final buffer = StringBuffer();

  void appendNodes(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is md.Text) {
        buffer.write(node.text);
        continue;
      }
      if (node is! md.Element) continue;
      if (node.tag == 'img') {
        buffer.write(node.attributes['alt'] ?? '');
      } else if (node.tag == 'br') {
        buffer.write('\n');
      } else {
        appendNodes(node.children ?? const <md.Node>[]);
      }
    }
  }

  appendNodes(element.children ?? const <md.Node>[]);
  final label = buffer.toString();
  return label.trim().isEmpty ? fallback : label;
}

/// Resolves a Markdown destination asynchronously so the renderer never
/// treats a missing, out-of-project, or escaping symbolic link as a file row.

List<InlineSpan> agentMarkdownLinkSpans(
  List<md.Node> nodes, {
  required TextStyle? style,
  required TextStyle? codeStyle,
  required String? workspacePath,
}) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    if (node is md.Text) {
      spans.add(TextSpan(text: node.text, style: style));
      continue;
    }
    if (node is! md.Element) continue;
    if (node.tag == 'br') {
      spans.add(TextSpan(text: '\n', style: style));
      continue;
    }
    if (node.tag == 'img') {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: AgentLinkedImage(
            source: node.attributes['src'] ?? '',
            alt: node.attributes['alt'] ?? '',
            workspacePath: workspacePath,
            fallbackStyle: style,
          ),
        ),
      );
      continue;
    }
    final childStyle = switch (node.tag) {
      'strong' => style?.copyWith(fontWeight: FontWeight.w700),
      'em' => style?.copyWith(fontStyle: FontStyle.italic),
      'code' => style?.merge(codeStyle),
      'del' => style?.copyWith(
        decoration: TextDecoration.combine([
          if (style.decoration != null) style.decoration!,
          TextDecoration.lineThrough,
        ]),
      ),
      _ => style,
    };
    spans.addAll(
      agentMarkdownLinkSpans(
        node.children ?? const <md.Node>[],
        style: childStyle,
        codeStyle: codeStyle,
        workspacePath: workspacePath,
      ),
    );
  }
  return spans;
}

Future<void> openAgentMarkdownDestination(
  BuildContext context, {
  required String href,
  required String? workspacePath,
}) async {
  // A reference resolved while rendering is presentation data only. Always
  // authorize the target again at activation time so a file replaced by a
  // symbolic link cannot escape the workspace boundary.
  final resolvedReference = workspacePath == null
      ? null
      : await resolveWorkspaceFileReference(
          href: href,
          workspacePath: workspacePath,
        );
  if (resolvedReference != null && isMarkdownFilePath(resolvedReference.path)) {
    if (context.mounted) {
      await showWorkspaceMarkdownPreview(
        context,
        reference: resolvedReference,
        workspacePath: workspacePath!,
      );
    }
    return;
  }

  final opened = await openAgentMarkdownLink(
    href: href,
    workspacePath: workspacePath,
    launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开此链接或项目内文件。')));
  }
}

/// 在保留测试控制器注入能力的同时，从 Riverpod 读取应用级控制器。
/// Reads the app controller from Riverpod while preserving explicit test injection.

enum ThreadStatusIndicator { completed, error }

const completedThreadIndicatorColor = Color(0xFF0A84FF);

/// Maps App Server thread status values to the compact sidebar outcome marks.
/// 将 App Server 线程状态映射为侧栏紧凑的结果提示图标。
ThreadStatusIndicator? threadStatusIndicator(String? status) {
  final normalized = status?.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z]'),
    '',
  );
  return switch (normalized) {
    'idle' ||
    'completed' ||
    'complete' ||
    'done' ||
    'success' ||
    'succeeded' => ThreadStatusIndicator.completed,
    'systemerror' ||
    'error' ||
    'failed' ||
    'failure' ||
    'errored' => ThreadStatusIndicator.error,
    _ => null,
  };
}

enum ThreadAction { pin, rename, archive, delete }

enum ThemeAction {
  system,
  light,
  dark,
  workbench,
  cobalt,
  orchid,
  graphite,
  obsidian,
  midnight,
  blackberry,
  sage;

  /// 返回对应配色预设；显示模式操作没有预设。
  /// Returns the corresponding color preset; display-mode actions have none.
  YeknomColorPreset? get preset => switch (this) {
    ThemeAction.workbench => YeknomColorPreset.workbench,
    ThemeAction.cobalt => YeknomColorPreset.cobalt,
    ThemeAction.orchid => YeknomColorPreset.orchid,
    ThemeAction.graphite => YeknomColorPreset.graphite,
    ThemeAction.obsidian => YeknomColorPreset.obsidian,
    ThemeAction.midnight => YeknomColorPreset.midnight,
    ThemeAction.blackberry => YeknomColorPreset.blackberry,
    ThemeAction.sage => YeknomColorPreset.sage,
    _ => null,
  };
}

/// 返回显示模式的本地化名称。
/// Returns the localized name for a display mode.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

/// 返回显示模式在顶部栏中使用的图标。
/// Returns the icon used for a display mode in the top bar.
IconData themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

/// 返回 UI Kit 配色预设的本地化名称。
/// Returns the localized name for a UI Kit color preset.
String themePresetLabel(YeknomColorPreset preset) => switch (preset) {
  YeknomColorPreset.workbench => '工作台',
  YeknomColorPreset.cobalt => '钴蓝',
  YeknomColorPreset.orchid => '兰紫',
  YeknomColorPreset.graphite => '石墨',
  YeknomColorPreset.obsidian => '黑曜',
  YeknomColorPreset.midnight => '午夜',
  YeknomColorPreset.blackberry => '黑莓',
  YeknomColorPreset.sage => '鼠尾草',
};
