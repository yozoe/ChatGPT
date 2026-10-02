/// One selectable answer advertised by App Server's `request_user_input` tool.
class PendingUserInputOption {
  const PendingUserInputOption({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}
