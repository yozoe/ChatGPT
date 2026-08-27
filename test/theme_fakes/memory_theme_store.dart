// Extracted theme test double.
import 'package:chatgpt/src/services/theme_preferences_store.dart';

final class MemoryThemeStore implements CodexThemePreferencesStore {
  final List<CodexThemePreferences> saved = [];

  @override
  Future<CodexThemePreferences> load() async => CodexThemePreferences.defaults;

  @override
  Future<void> save(CodexThemePreferences preferences) async {
    saved.add(preferences);
  }
}
