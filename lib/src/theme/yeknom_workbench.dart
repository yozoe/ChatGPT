import 'package:flutter/material.dart';

export 'yeknom_workbench_theme.dart';

/// Project-owned replacement for the former external UI kit theme.
///
/// The public names are kept so persisted preferences and the existing
/// presentation code remain source-compatible while the dependency is gone.
enum YeknomColorPreset {
  workbench,
  cobalt,
  orchid,
  graphite,
  obsidian,
  midnight,
  blackberry,
  sage,
}

@immutable
class YeknomPalette extends ThemeExtension<YeknomPalette> {
  const YeknomPalette({
    required this.dark,
    required this.bench,
    required this.module,
    required this.sidebar,
    required this.trace,
    required this.signal,
    required this.active,
    required this.ack,
    required this.fault,
    required this.warning,
    required this.onSignal,
    required this.muted,
    required this.faint,
    required this.border,
    required this.controlBorder,
    required this.field,
    required this.raised,
    required this.selected,
    required this.signalSelected,
  });

  factory YeknomPalette.fromBrightness(Brightness brightness) =>
      YeknomPalette.fromPreset(YeknomColorPreset.midnight, brightness);

  factory YeknomPalette.fromPreset(
    YeknomColorPreset preset,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    final accent = switch ((preset, dark)) {
      (YeknomColorPreset.workbench, true) => const Color(0xFF8FA8C8),
      (YeknomColorPreset.workbench, false) => const Color(0xFF3E648B),
      (YeknomColorPreset.cobalt, true) => const Color(0xFF78AAE0),
      (YeknomColorPreset.cobalt, false) => const Color(0xFF285F9E),
      (YeknomColorPreset.orchid, true) => const Color(0xFFB59AE8),
      (YeknomColorPreset.orchid, false) => const Color(0xFF684BA5),
      (YeknomColorPreset.graphite, true) => const Color(0xFF9CBAC1),
      (YeknomColorPreset.graphite, false) => const Color(0xFF526B72),
      (YeknomColorPreset.obsidian, true) => const Color(0xFF99A2A8),
      (YeknomColorPreset.obsidian, false) => const Color(0xFF41484D),
      (YeknomColorPreset.midnight, true) => const Color(0xFF85A9EB),
      (YeknomColorPreset.midnight, false) => const Color(0xFF345F9F),
      (YeknomColorPreset.blackberry, true) => const Color(0xFFB69AE1),
      (YeknomColorPreset.blackberry, false) => const Color(0xFF69479C),
      (YeknomColorPreset.sage, true) => const Color(0xFF8FB7BE),
      (YeknomColorPreset.sage, false) => const Color(0xFF466C72),
    };
    final bench = dark ? const Color(0xFF171717) : const Color(0xFFF5F5F5);
    final module = dark ? const Color(0xFF242424) : Colors.white;
    final sidebar = dark ? const Color(0xFF282A2B) : const Color(0xFFF7F7F7);
    // Codex keeps text deliberately quiet against the graphite surfaces:
    // primary copy is light gray rather than pure white, while secondary and
    // tertiary labels step down without becoming low-contrast.
    final trace = dark ? const Color(0xFFD2D2D2) : const Color(0xFF262626);
    final muted = dark ? const Color(0xFF9A9A9A) : const Color(0xFF6A6A6A);
    final border = dark ? const Color(0xFF343434) : const Color(0xFFD7D7D7);
    final field = dark ? const Color(0xFF202020) : const Color(0xFFF0F0F0);
    final raised = dark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF);
    final selected = dark ? const Color(0xFF3A3A3A) : const Color(0xFFE5EAF1);
    final signal = dark ? const Color(0xFFE3A45F) : const Color(0xFF9A5F1A);
    final ack = dark ? const Color(0xFF45D391) : const Color(0xFF237A4E);
    final fault = dark ? const Color(0xFFF17878) : const Color(0xFFB74747);
    final warning = dark ? const Color(0xFFE7AA65) : const Color(0xFF98611F);
    return YeknomPalette(
      dark: dark,
      bench: bench,
      module: module,
      sidebar: sidebar,
      trace: trace,
      signal: signal,
      active: accent,
      ack: ack,
      fault: fault,
      warning: warning,
      onSignal: dark ? const Color(0xFF171717) : Colors.white,
      muted: muted,
      faint: muted.withValues(alpha: 0.62),
      border: border,
      controlBorder: dark ? const Color(0xFF555555) : const Color(0xFFBDBDBD),
      field: field,
      raised: raised,
      selected: selected,
      signalSelected: dark ? const Color(0xFF3B3024) : const Color(0xFFF2E6D6),
    );
  }

  static YeknomPalette of(BuildContext context) =>
      Theme.of(context).extension<YeknomPalette>() ??
      YeknomPalette.fromBrightness(Theme.of(context).brightness);

  final bool dark;
  final Color bench;
  final Color module;
  final Color sidebar;
  final Color trace;
  final Color signal;
  final Color active;
  final Color ack;
  final Color fault;
  final Color warning;
  final Color onSignal;
  final Color muted;
  final Color faint;
  final Color border;
  final Color controlBorder;
  final Color field;
  final Color raised;
  final Color selected;
  final Color signalSelected;

  @override
  YeknomPalette copyWith({
    bool? dark,
    Color? bench,
    Color? module,
    Color? sidebar,
    Color? trace,
    Color? signal,
    Color? active,
    Color? ack,
    Color? fault,
    Color? warning,
    Color? onSignal,
    Color? muted,
    Color? faint,
    Color? border,
    Color? controlBorder,
    Color? field,
    Color? raised,
    Color? selected,
    Color? signalSelected,
  }) => YeknomPalette(
    dark: dark ?? this.dark,
    bench: bench ?? this.bench,
    module: module ?? this.module,
    sidebar: sidebar ?? this.sidebar,
    trace: trace ?? this.trace,
    signal: signal ?? this.signal,
    active: active ?? this.active,
    ack: ack ?? this.ack,
    fault: fault ?? this.fault,
    warning: warning ?? this.warning,
    onSignal: onSignal ?? this.onSignal,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    border: border ?? this.border,
    controlBorder: controlBorder ?? this.controlBorder,
    field: field ?? this.field,
    raised: raised ?? this.raised,
    selected: selected ?? this.selected,
    signalSelected: signalSelected ?? this.signalSelected,
  );

  @override
  YeknomPalette lerp(covariant YeknomPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return copyWith(
      dark: t < 0.5 ? dark : other.dark,
      bench: mix(bench, other.bench),
      module: mix(module, other.module),
      sidebar: mix(sidebar, other.sidebar),
      trace: mix(trace, other.trace),
      signal: mix(signal, other.signal),
      active: mix(active, other.active),
      ack: mix(ack, other.ack),
      fault: mix(fault, other.fault),
      warning: mix(warning, other.warning),
      onSignal: mix(onSignal, other.onSignal),
      muted: mix(muted, other.muted),
      faint: mix(faint, other.faint),
      border: mix(border, other.border),
      controlBorder: mix(controlBorder, other.controlBorder),
      field: mix(field, other.field),
      raised: mix(raised, other.raised),
      selected: mix(selected, other.selected),
      signalSelected: mix(signalSelected, other.signalSelected),
    );
  }
}
