// Extracted class from pending_elicitation.dart.

class ElicitationField {
  const ElicitationField({
    required this.name,
    required this.type,
    required this.title,
    required this.required,
    this.description,
    this.defaultValue,
    this.options = const [],
  });

  final String name;
  final String type;
  final String title;
  final bool required;
  final String? description;
  final Object? defaultValue;
  final List<Object> options;

  bool get isBoolean => type == 'boolean';
  bool get isNumeric => type == 'number' || type == 'integer';
}
