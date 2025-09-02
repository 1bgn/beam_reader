import 'inline_text.dart';

/// Обычный текстовый кусок внутри строки
class TextRun extends InlineText {
  final String text;

  const TextRun({
    required this.text,
    required super.path,
  });

  @override
  String get tag => '#text';

  @override
  String toString() => 'TextRun("$text")';
}