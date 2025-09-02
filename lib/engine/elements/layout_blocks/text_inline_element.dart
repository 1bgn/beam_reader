import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'package:beam_reader/engine/elements/layout_blocks/inline_element.dart';

class TextInlineParagraph extends InlineElement{
  final String text;
  final TextStyle style;

  TextInlineParagraph({required this.text, required this.style});

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
}