import 'package:beam_reader/engine/elements/data_blocks/text_run.dart';

import 'element_text.dart';

/// Базовый класс для inline-узлов (phrasing content)
abstract class InlineText extends ElementText {
  const InlineText({
    required super.path,
    super.attrs = const {},
  });
}



/// Строчный span с тегом (emphasis, strong, a, sub, sup, code, style, date, …)
class InlineSpan extends InlineText {
  /// Имя inline-тега, например "emphasis" / "strong" / "a"
  @override
  final String tag;

  /// Внутри могут быть другие inline-узлы
  final List<InlineText> children;

  const InlineSpan({
    required this.tag,
    required this.children,
    required super.path,
    super.attrs = const {},
  });

  /// Свести поддерево к plain-тексту (без стилей)
  String toPlainText() {
    final buf = StringBuffer();

    void walk(InlineText n) {
      if (n is TextRun) {
        buf.write(n.text);
      } else if (n is InlineSpan) {
        for (final c in n.children) {
          walk(c);
        }
      }
    }

    for (final c in children) {
      walk(c);
    }
    return buf.toString();
  }

  @override
  String toString() => 'InlineSpan<$tag>(${children.length} children)';
}
