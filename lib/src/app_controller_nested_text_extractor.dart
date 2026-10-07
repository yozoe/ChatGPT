/// Extracts the first displayable text from nested App Server payloads.
///
/// Protocol notifications may wrap a message in `delta`, `text`, or
/// `message` fields, and compatible servers may nest those values in maps or
/// lists. The controller owns the surrounding timeline behavior; this class
/// only performs deterministic payload traversal.
class CodexNestedTextExtractor {
  const CodexNestedTextExtractor._();

  static String firstDisplayableText(Object? value) {
    if (value is String) return value;
    if (value is Map) {
      for (final key in ['delta', 'text', 'message']) {
        final found = firstDisplayableText(value[key]);
        if (found.isNotEmpty) return found;
      }
      for (final candidate in value.values) {
        final found = firstDisplayableText(candidate);
        if (found.isNotEmpty) return found;
      }
    }
    if (value is Iterable) {
      for (final candidate in value) {
        final found = firstDisplayableText(candidate);
        if (found.isNotEmpty) return found;
      }
    }
    return '';
  }
}
