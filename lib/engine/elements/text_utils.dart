import 'package:beam_reader/engine/elements/layout_blocks/inline_element.dart';
import 'package:beam_reader/engine/elements/layout_blocks/text_inline_element.dart';
import 'package:beam_reader/engine/elements/data_blocks/inline_text.dart';
import 'package:beam_reader/engine/elements/data_blocks/text_run.dart';

/// Считает total длину текста по InlineText-модели.
int inlineTextTotalLength(List<InlineText> nodes) {
  int sum = 0;
  void walk(InlineText n) {
    if (n is TextRun) { sum += n.text.length; return; }
    if (n is InlineSpan) { for (final c in n.children) walk(c); }
  }
  for (final n in nodes) walk(n);
  return sum;
}

/// Отрезает первые [skip] символов в плоском списке InlineElement (TextInlineElement),
/// сохраняя стили и пробелы.
List<InlineElement> sliceInlineElementsFromStart(List<InlineElement> elems, int skip) {
  if (skip <= 0) return elems;
  int left = skip;
  final out = <InlineElement>[];

  for (final e in elems) {
    if (e is! TextInlineElement) {
      // нон-текстовые элементы не «съедают» символы
      out.add(e);
      continue;
    }
    final t = e.text;
    if (left >= t.length) {
      left -= t.length;
      continue; // весь этот узел пропускаем
    } else if (left > 0) {
      out.add(TextInlineElement(text: t.substring(left), style: e.style));
      left = 0;
    } else {
      out.add(e);
    }
  }
  return out;
}
