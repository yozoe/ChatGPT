/// Owns the generation that guards asynchronous thread environment restores.
///
/// A thread switch may start several storage and filesystem reads. Advancing
/// this generation makes results from an older switch harmless without mixing
/// the restore lifecycle with configuration-write generations.
class CodexThreadEnvironmentRestoreState {
  int restoreGeneration = 0;

  int nextGeneration() => ++restoreGeneration;

  bool isCurrent(int generation) => generation == restoreGeneration;

  void invalidate() {
    restoreGeneration++;
  }
}
