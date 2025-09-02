import 'dart:ui';

import 'package:beam_reader/engine/elements/layout_blocks/inline_element.dart';

class IndentInlineElement extends InlineElement{
  final double indentWidth;

  IndentInlineElement({required this.indentWidth});
  @override
  void paint(Canvas canvas, Offset offset) {

  }

  @override
  void performLayout(double maxWidth) {
    width = indentWidth;
    height = 0;
    baseline = 0;
  }

}