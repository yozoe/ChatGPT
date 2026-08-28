import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Builds the compact Codex-style mark used when a plugin has no own logo.
Widget buildCodexPluginMark({required Color color, double size = 22}) {
  return SizedBox(
    width: size,
    height: size,
    child: SvgPicture.string(
      codexPluginMarkSvg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

const codexPluginMarkSvg = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M18.3 8.05A7.5 7.5 0 1 0 19.45 15.4" stroke="currentColor" stroke-width="1.65" stroke-linecap="round"/>
  <path d="M18.25 5.7V8.2H20.7" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M9.1 8.45H13.4L15.55 10.6V14.9L13.4 17.05H9.1L6.95 14.9V10.6L9.1 8.45Z" stroke="currentColor" stroke-width="1.65" stroke-linejoin="round"/>
  <path d="M10.35 11.05H12.95L13.9 12V14.1L12.3 15.55H10.35" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
