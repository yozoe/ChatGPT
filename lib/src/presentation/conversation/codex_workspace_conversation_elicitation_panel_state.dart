// Extracted class from codex_workspace_conversation.dart.
// ignore_for_file: unused_import, unnecessary_import, use_key_in_widget_constructors
import 'dart:math' as math;
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';
import 'package:chatgpt/src/presentation/extensions/codex_workspace_extensions.dart';
import 'package:chatgpt/src/presentation/sidebar/codex_workspace_sidebar.dart';
import 'package:chatgpt/src/presentation/timeline/codex_workspace_timeline.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_support.dart';
import 'package:chatgpt/src/presentation/conversation/codex_workspace_conversation_elicitation_panel.dart';

/// 管理动态 elicitation 表单的初始值、触摸状态和提交载荷。
/// Manages dynamic elicitation form defaults, touched state, validation, and submission payloads.
class ElicitationPanelState extends State<ElicitationPanel> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, Object?> _selectedValues = {};
  final Set<String> _touched = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.elicitation.fields) {
      if (field.isBoolean || field.options.isNotEmpty) {
        _selectedValues[field.name] =
            field.defaultValue ??
            (field.options.isNotEmpty ? field.options.first : false);
      } else {
        _textControllers[field.name] = TextEditingController(
          text: field.defaultValue?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 将表单控件转换为 MCP elicitation 接口需要的内容对象。
  /// Converts form controls into the content object required by MCP elicitation.
  JsonMap _content() {
    final content = <String, dynamic>{};
    for (final field in widget.elicitation.fields) {
      if (field.isBoolean || field.options.isNotEmpty) {
        if (field.required ||
            field.defaultValue != null ||
            _touched.contains(field.name)) {
          content[field.name] = _selectedValues[field.name];
        }
        continue;
      }
      final raw = _textControllers[field.name]!.text;
      if (raw.isEmpty && !field.required && field.defaultValue == null) {
        continue;
      }
      content[field.name] = switch (field.type) {
        'integer' => int.parse(raw),
        'number' => num.parse(raw),
        _ => raw,
      };
    }
    return content;
  }

  /// 校验动态字段后提交回答，并由控制器处理请求生命周期。
  /// Validates dynamic fields and submits the answer through the controller.
  Future<void> _accept() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await widget.onRespond(action: 'accept', content: _content());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.elicitation.mode == ElicitationMode.url) {
      return _buildUrlPermissionCard(context);
    }
    final palette = YeknomPalette.of(context);
    final elicitation = widget.elicitation;
    return Container(
      key: const Key('mcp-elicitation-panel'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.signalSelected,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.warning),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          key: const Key('mcp-elicitation-scroll'),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  elicitation.title,
                  style: TextStyle(
                    color: palette.signal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '来源：${elicitation.serverName}',
                  style: TextStyle(color: palette.signal),
                ),
                if (widget.taskLabel case final label?) ...[
                  const SizedBox(height: 4),
                  Text(
                    '来自后台任务：$label',
                    style: TextStyle(color: palette.signal),
                  ),
                ],
                const SizedBox(height: 8),
                SelectableText(elicitation.message),
                if (elicitation.mode == ElicitationMode.url) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    elicitation.url!,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '此链接不会自动打开；确认后由 MCP 服务器继续该流程。',
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ] else ...[
                  for (final field in elicitation.fields) ...[
                    const SizedBox(height: 10),
                    _buildField(field),
                  ],
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('mcp-elicitation-cancel'),
                      onPressed: widget.enabled
                          ? () => widget.onRespond(action: 'cancel')
                          : null,
                      child: const Text('取消'),
                    ),
                    OutlinedButton(
                      key: const Key('mcp-elicitation-decline'),
                      onPressed: widget.enabled
                          ? () => widget.onRespond(action: 'decline')
                          : null,
                      child: const Text('拒绝'),
                    ),
                    FilledButton(
                      key: const Key('mcp-elicitation-accept'),
                      onPressed: widget.enabled ? _accept : null,
                      child: Text(
                        elicitation.mode == ElicitationMode.url ? '继续' : '提交',
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

  Widget _buildUrlPermissionCard(BuildContext context) {
    final palette = YeknomPalette.of(context);
    final elicitation = widget.elicitation;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (widget.enabled) {
            unawaited(widget.onRespond(action: 'decline'));
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: const Key('mcp-elicitation-panel'),
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 600),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(12),
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
                  children: [
                    Icon(Icons.language, size: 15, color: palette.muted),
                    const SizedBox(width: 7),
                    Text(
                      'Browser',
                      style: TextStyle(
                        color: palette.trace,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  elicitation.message,
                  style: TextStyle(
                    color: palette.trace,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  elicitation.url!,
                  style: TextStyle(color: palette.signal, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      key: const Key('mcp-elicitation-decline'),
                      onPressed: widget.enabled
                          ? () => widget.onRespond(action: 'decline')
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.muted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('拒绝  Esc'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      key: const Key('mcp-elicitation-accept'),
                      onPressed: widget.enabled
                          ? () => widget.onRespond(action: 'accept')
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.field,
                        foregroundColor: palette.trace,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('允许一次  ↵'),
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

  Widget _buildField(ElicitationField field) {
    if (field.isBoolean) {
      final value = _selectedValues[field.name] as bool? ?? false;
      return CheckboxListTile(
        value: value,
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(field.title),
        subtitle: field.description == null ? null : Text(field.description!),
        onChanged: widget.enabled
            ? (next) => setState(() {
                _touched.add(field.name);
                _selectedValues[field.name] = next ?? false;
              })
            : null,
      );
    }
    if (field.options.isNotEmpty) {
      return DropdownButtonFormField<Object>(
        initialValue: _selectedValues[field.name],
        decoration: InputDecoration(
          labelText: field.required ? '${field.title} *' : field.title,
          helperText: field.description,
          isDense: true,
        ),
        items: [
          for (final option in field.options)
            DropdownMenuItem(value: option, child: Text(option.toString())),
        ],
        onChanged: widget.enabled
            ? (next) => setState(() {
                _touched.add(field.name);
                _selectedValues[field.name] = next;
              })
            : null,
      );
    }
    return TextFormField(
      key: ValueKey('mcp-elicitation-field-${field.name}'),
      controller: _textControllers[field.name],
      enabled: widget.enabled,
      keyboardType: field.isNumeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: field.required ? '${field.title} *' : field.title,
        helperText: field.description,
        isDense: true,
      ),
      validator: (value) {
        if (field.required && (value == null || value.isEmpty)) return '此项必填';
        if (value != null && value.isNotEmpty && field.isNumeric) {
          final valid = field.type == 'integer'
              ? int.tryParse(value) != null
              : num.tryParse(value) != null;
          if (!valid) return field.type == 'integer' ? '请输入整数' : '请输入数字';
        }
        return null;
      },
    );
  }
}
