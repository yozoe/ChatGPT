import 'package:chatgpt/src/app_controller_nested_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers displayable protocol keys before arbitrary map values', () {
    expect(
      CodexNestedTextExtractor.firstDisplayableText({
        'fallback': {'text': 'fallback'},
        'message': {'delta': 'preferred'},
      }),
      'preferred',
    );
  });

  test('walks nested maps and iterables', () {
    expect(
      CodexNestedTextExtractor.firstDisplayableText([
        null,
        {
          'payload': [
            42,
            {'text': 'found'},
          ],
        },
      ]),
      'found',
    );
  });

  test('returns an empty string when no displayable text exists', () {
    expect(
      CodexNestedTextExtractor.firstDisplayableText({
        'delta': 42,
        'nested': [null, false],
      }),
      isEmpty,
    );
  });
}
