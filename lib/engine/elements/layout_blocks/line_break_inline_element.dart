import 'dart:ui';

import 'inline_element.dart';

class LineBreakInlineElement extends InlineElement {
  @override
  void performLayout(double maxWidth) {
    width = 0;
    height = 0;
    baseline = 0;
  }

  @override
  void paint(Canvas canvas, Offset offset) {}
}
