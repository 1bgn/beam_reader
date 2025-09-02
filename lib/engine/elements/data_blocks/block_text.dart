import 'package:beam_reader/engine/elements/data_blocks/text_run.dart';


import '../../fb2_transform.dart';
import 'element_text.dart';
import 'inline_text.dart';

/// Один визуальный блок вывода (абзац/строка/заголовок/автор и т. п.)
class BlockText extends ElementText {
  /// Имя блочного тега (например, "p" / "v" / "title" / "text-author")
  @override
  final String tag;

  /// Для устойчивой группировки: id исходного блочного узла (если есть).
  /// Если парсер его не присваивает, можно генерить хэш пути.
  final String id;

  /// Содержимое блока — в виде последовательности inline-узлов
  final List<InlineText> inlines;

  /// Глубина вложенности (сколько раз мы вошли в section/body/poem/stanza)
  final int depth;

  /// Семантика (для рендера можно принимать решения по ней)
  Fb2BlockTag get kind => fb2BlockTagFromName(tag);

  const BlockText({
    required this.tag,
    required this.id,
    required this.inlines,
    required super.path,
    this.depth = 0,
    super.attrs = const {},
  });

  /// Plain-текст всего блока без стилей
  String toPlainText() {
    final buf = StringBuffer();
    for (final n in inlines) {
      if (n is TextRun) {
        buf.write(n.text);
      } else if (n is InlineSpan) {
        buf.write(n.toPlainText());
      }
    }
    return buf.toString();
  }

  /// Удобно для отладки
  @override
  String toString() => 'BlockText<$tag>#${id.substring(0, id.length > 8 ? 8 : id.length)} '
      'depth=$depth text="${toPlainText()}"';
}
