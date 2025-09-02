import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'package:beam_reader/engine/elements/layout_blocks/inline_element.dart';

class TextInlineElement extends InlineElement{
  final String text;
  final TextStyle style;

  TextInlineElement({required this.text, required this.style});

  ui.Paragraph? _paragraphCache;

  // @override
  // List<Rect> getInteractiveRects(Offset offset) {
  //   // TODO: implement getInteractiveRects
  //   throw UnimplementedError();
  // }

  @override
  void paint(Canvas canvas, Offset offset) {
    canvas.drawParagraph(_paragraphCache!, offset);
  }

  @override
  void performLayout(double maxWidth) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
      ),
    );
    builder.pushStyle(ui.TextStyle(
      color: style.color,
      fontSize: style.fontSize,
      fontFamily: style.fontFamily,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      height: style.height,
    ));
    builder.addText(text);
    final paragraph = builder.build();
    _paragraphCache = paragraph;

    paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
    width = paragraph.maxIntrinsicWidth;
    height = paragraph.height;
    final metrics = paragraph.computeLineMetrics();
    if (metrics.isNotEmpty) {
      baseline = metrics.first.ascent;
    } else {
      baseline = height;
    }

  }
  int countSpacesInRange(int start, int end) {
    final s = start.clamp(0, text.length);
    final e = end.clamp(0, text.length);
    var k = 0;
    for (var i = s; i < e; i++) {
      if (text.codeUnitAt(i) == 0x20) k++;
    }
    return k;
  }
  List<ui.TextBox> selectionBoxes(int start, int end) {
    final p = _paragraphCache;
    if (p == null) return const [];
    final s = start.clamp(0, text.length);
    final e = end.clamp(0, text.length);
    if (e <= s) return const [];
    return p.getBoxesForRange(s, e);
  }
  int caretOffsetForX(double localX) {
    final p = _paragraphCache;
    if (p == null) return 0;
    // Для однострочного параграфа достаточно любой Y внутри строки (0 тоже ок).
    final pos = p.getPositionForOffset(Offset(localX, 0));
    var off = pos.offset;
    if (off < 0) off = 0;
    if (off > text.length) off = text.length;
    return off;
  }
}