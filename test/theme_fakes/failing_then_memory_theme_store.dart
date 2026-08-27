// Extracted theme test double.
// ignore_for_file: must_be_immutable
import 'package:chatgpt/src/services/theme_preferences_store.dart';

final class FailingThenMemoryThemeStore implements CodexThemePreferencesStore {
  final List<CodexThemePreferences> saved = [];
  var saveAttempts = 0;

  @override
  Future<CodexThemePreferences> load() async => CodexThemePreferences.defaults;

  @override
  Future<void> save(CodexThemePreferences preferences) async {
    saveAttempts++;
    if (saveAttempts == 1) throw StateError('first save failed');
    saved.add(preferences);
  }
}
