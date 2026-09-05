import 'package:flutter/material.dart';

/// Produces a lightweight, selectable syntax-highlighted span for common
/// workspace source and configuration files.
class WorkspaceCodeSyntaxHighlighter {
  WorkspaceCodeSyntaxHighlighter({required bool dark})
    : keywordColor = dark ? const Color(0xFFC792EA) : const Color(0xFF7C3FA0),
      stringColor = dark ? const Color(0xFF8BD49C) : const Color(0xFF287A3D),
      commentColor = dark ? const Color(0xFF737A80) : const Color(0xFF737B84),
      numberColor = dark ? const Color(0xFFF2B86B) : const Color(0xFFA85B16),
      variableColor = dark ? const Color(0xFFE6B673) : const Color(0xFF8A5B13),
      typeColor = dark ? const Color(0xFF82AAFF) : const Color(0xFF285AA6);

  final Color keywordColor;
  final Color stringColor;
  final Color commentColor;
  final Color numberColor;
  final Color variableColor;
  final Color typeColor;

  static const Set<String> _commonKeywords = {
    'abstract',
    'as',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'defer',
    'do',
    'else',
    'enum',
    'export',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'from',
    'func',
    'function',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'let',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'override',
    'package',
    'private',
    'protected',
    'public',
    'required',
    'return',
    'sealed',
    'static',
    'struct',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
  };

  static const Set<String> _shellKeywords = {
    'case',
    'do',
    'done',
    'elif',
    'else',
    'esac',
    'fi',
    'for',
    'function',
    'if',
    'in',
    'select',
    'set',
    'then',
    'time',
    'until',
    'while',
  };

  TextSpan highlight({required String content, required String path}) {
    final extension = _extension(path);
    final hashComments = {
      'py',
      'rb',
      'sh',
      'bash',
      'zsh',
      'yaml',
      'yml',
      'toml',
      'conf',
    }.contains(extension);
    final shell = {'sh', 'bash', 'zsh'}.contains(extension);
    final slashComments = {
      'c',
      'cc',
      'cpp',
      'css',
      'dart',
      'go',
      'java',
      'js',
      'kt',
      'kts',
      'm',
      'mm',
      'rs',
      'scss',
      'swift',
      'ts',
    }.contains(extension);
    final spans = <InlineSpan>[];
    var index = 0;
    while (index < content.length) {
      final character = content[index];
      if (hashComments && character == '#') {
        final end = _lineEnd(content, index);
        _append(spans, content.substring(index, end), commentColor);
        index = end;
        continue;
      }
      if (slashComments && content.startsWith('//', index)) {
        final end = _lineEnd(content, index);
        _append(spans, content.substring(index, end), commentColor);
        index = end;
        continue;
      }
      if (slashComments && content.startsWith('/*', index)) {
        final marker = content.indexOf('*/', index + 2);
        final end = marker < 0 ? content.length : marker + 2;
        _append(spans, content.substring(index, end), commentColor);
        index = end;
        continue;
      }
      if (content.startsWith('<!--', index)) {
        final marker = content.indexOf('-->', index + 4);
        final end = marker < 0 ? content.length : marker + 3;
        _append(spans, content.substring(index, end), commentColor);
        index = end;
        continue;
      }
      if (character == '"' || character == "'" || character == '`') {
        final end = _quotedEnd(content, index, character);
        _append(spans, content.substring(index, end), stringColor);
        index = end;
        continue;
      }
      if (character == r'$') {
        final end = _variableEnd(content, index);
        if (end > index + 1) {
          _append(spans, content.substring(index, end), variableColor);
          index = end;
          continue;
        }
      }
      if (_isDigit(character) ||
          (character == '.' &&
              index + 1 < content.length &&
              _isDigit(content[index + 1]))) {
        final end = _numberEnd(content, index);
        _append(spans, content.substring(index, end), numberColor);
        index = end;
        continue;
      }
      if (_isIdentifierStart(character)) {
        final end = _identifierEnd(content, index);
        final word = content.substring(index, end);
        final isKeyword =
            _commonKeywords.contains(word) ||
            (shell && _shellKeywords.contains(word));
        if (isKeyword) {
          _append(spans, word, keywordColor);
        } else if (_looksLikeType(word)) {
          _append(spans, word, typeColor);
        } else {
          _append(spans, word, null);
        }
        index = end;
        continue;
      }
      final end = _plainEnd(
        content,
        index,
        hashComments: hashComments,
        slashComments: slashComments,
      );
      _append(spans, content.substring(index, end), null);
      index = end;
    }
    return TextSpan(children: spans);
  }

  static String _extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
    if ({'dockerfile', 'makefile', 'gemfile'}.contains(name)) return 'sh';
    final separator = name.lastIndexOf('.');
    return separator < 0 ? '' : name.substring(separator + 1);
  }

  static int _lineEnd(String content, int start) {
    final end = content.indexOf('\n', start);
    return end < 0 ? content.length : end;
  }

  static int _quotedEnd(String content, int start, String quote) {
    var index = start + 1;
    while (index < content.length) {
      if (content[index] == '\\') {
        index += 2;
        continue;
      }
      if (content[index] == quote) return index + 1;
      index++;
    }
    return content.length;
  }

  static int _variableEnd(String content, int start) {
    var index = start + 1;
    if (index < content.length && content[index] == '{') {
      final end = content.indexOf('}', index + 1);
      return end < 0 ? start + 1 : end + 1;
    }
    while (index < content.length && _isIdentifierPart(content[index])) {
      index++;
    }
    return index;
  }

  static int _numberEnd(String content, int start) {
    var index = start;
    while (index < content.length &&
        RegExp(r'[0-9A-Fa-f_xX.]').hasMatch(content[index])) {
      index++;
    }
    return index;
  }

  static int _identifierEnd(String content, int start) {
    var index = start + 1;
    while (index < content.length && _isIdentifierPart(content[index])) {
      index++;
    }
    return index;
  }

  static int _plainEnd(
    String content,
    int start, {
    required bool hashComments,
    required bool slashComments,
  }) {
    var index = start + 1;
    while (index < content.length) {
      final character = content[index];
      final startsToken =
          (hashComments && character == '#') ||
          (slashComments && character == '/') ||
          character == '"' ||
          character == "'" ||
          character == '`' ||
          character == r'$' ||
          _isDigit(character) ||
          _isIdentifierStart(character) ||
          (character == '.' &&
              index + 1 < content.length &&
              _isDigit(content[index + 1])) ||
          content.startsWith('<!--', index);
      if (startsToken) return index;
      index++;
    }
    return content.length;
  }

  static bool _isIdentifierStart(String character) {
    final code = character.codeUnitAt(0);
    return code == 95 ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
  }

  static bool _isIdentifierPart(String character) =>
      _isIdentifierStart(character) || _isDigit(character);

  static bool _isDigit(String character) =>
      character.codeUnitAt(0) >= 48 && character.codeUnitAt(0) <= 57;

  static bool _looksLikeType(String word) =>
      word.length > 1 && word.codeUnitAt(0) >= 65 && word.codeUnitAt(0) <= 90;

  static void _append(List<InlineSpan> spans, String text, Color? color) {
    if (text.isEmpty) return;
    spans.add(
      TextSpan(
        text: text,
        style: color == null ? null : TextStyle(color: color),
      ),
    );
  }
}
