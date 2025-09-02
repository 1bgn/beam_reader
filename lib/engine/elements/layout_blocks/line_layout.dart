import 'package:flutter/cupertino.dart';

import 'inline_element.dart';

class LineLayout {
  List<InlineElement> elements = [];
  double width = 0;
  double height = 0;
  double maxAscent = 0;
  double maxDescent = 0;
  bool isSectionEnd = false;      // последняя строка абзаца
  bool endsWithHardBreak = false; // закончилась явным \n
  int  spacesCount = 0;           // количество обычных пробелов ' ' в строке
  TextAlign textAlign = TextAlign.left;
  TextDirection textDirection = TextDirection.ltr;
  double containerOffset = 0;
  double containerOffsetFactor = 1.0;
  int startTextOffset = 0;
  double get baseline => maxAscent;
}