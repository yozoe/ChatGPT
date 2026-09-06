class ComposerPastedText {
  ComposerPastedText({required this.id, required this.text})
    : previewLabel = _buildPreviewLabel(text);

  static const _previewCharacterLimit = 96;
  static const _previewScanLimit = 384;

  final int id;
  final String text;
  final String previewLabel;

  static String _buildPreviewLabel(String text) {
    final preview = StringBuffer();
    var scanned = 0;
    var written = 0;
    var pendingSpace = false;
    for (final rune in text.runes) {
      if (scanned++ >= _previewScanLimit || written >= _previewCharacterLimit) {
        break;
      }
      if (_isWhitespaceRune(rune)) {
        if (preview.isNotEmpty) pendingSpace = true;
        continue;
      }
      if (pendingSpace && written < _previewCharacterLimit) {
        preview.write(' ');
        written++;
        pendingSpace = false;
      }
      if (written >= _previewCharacterLimit) break;
      preview.writeCharCode(rune);
      written++;
    }
    return preview.isEmpty ? '粘贴的文本' : preview.toString();
  }

  static bool _isWhitespaceRune(int rune) =>
      rune <= 0x20 ||
      rune == 0x85 ||
      rune == 0xA0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000 ||
      rune == 0xFEFF;
}
