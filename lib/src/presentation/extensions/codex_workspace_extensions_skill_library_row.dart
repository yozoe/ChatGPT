// Extracted class from codex_workspace_extensions.dart.
import 'package:chatgpt/src/presentation/workspace/codex_workspace_dependencies.dart';

class SkillLibraryRow extends StatelessWidget {
  const SkillLibraryRow({super.key, required this.skill});
  final CodexSkill skill;

  IconData get _icon {
    final name = skill.name.toLowerCase();
    if (name.contains('plugin')) return Icons.extension_outlined;
    if (name.contains('image')) return Icons.image_outlined;
    if (name.contains('doc') || name.contains('pdf')) {
      return Icons.description_outlined;
    }
    return Icons.auto_awesome_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YeknomPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Icon(_icon, size: 21, color: palette.trace),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  skill.summary.isEmpty ? skill.path : skill.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.check, size: 19, color: palette.ack),
        ],
      ),
    );
  }
}
