import 'package:flutter/cupertino.dart';

import 'inline_element.dart';

class LineLayout {
  List<InlineElement> elements = [];
  double width = 0;
  double height = 0;
  double maxAscent = 0;
  double maxDescent = 0;
  bool isSectionEnd = false;
  TextAlign textAlign = TextAlign.left;
  TextDirection textDirection = TextDirection.ltr;
  // Новое свойство для хранения коэффициента контейнерного смещения
  double containerOffset = 0;
  double containerOffsetFactor = 1.0; // По умолчанию 1.0 (то есть весь доступный width)
  int startTextOffset = 0;
  double get baseline => maxAscent;
}