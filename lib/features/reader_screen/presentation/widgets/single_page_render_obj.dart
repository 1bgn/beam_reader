import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import '../../../../engine/elements/layout_blocks/multi_column_page.dart';
import '../../../../engine/elements/layout_blocks/text_inline_element.dart';

class SinglePageRenderObj extends RenderBox {
  MultiColumnPage _page;
  double _lineSpacing;
  bool _allowSoftHyphens;
  void Function(String explanation)? onFootnoteTap;

  SinglePageRenderObj({
    required MultiColumnPage page,
    required double lineSpacing,
    required bool allowSoftHyphens,
    this.onFootnoteTap,
  })  : _page = page,
        _lineSpacing = lineSpacing,
        _allowSoftHyphens = allowSoftHyphens;

  set page(MultiColumnPage value) {
    if (_page != value) {
      _page = value;
      markNeedsLayout();
    }
  }

  set lineSpacing(double value) {
    if (_lineSpacing != value) {
      _lineSpacing = value;
      markNeedsLayout();
    }
  }

  set allowSoftHyphens(bool value) {
    if (_allowSoftHyphens != value) {
      _allowSoftHyphens = value;
      markNeedsLayout();
    }
  }
  bool _hasNormalSpaces(String s) {
    for (final c in s.codeUnits) {
      if (c == 0x20) return true; // U+0020
    }
    return false;
  }

  int _countNormalSpaces(String s) {
    int k = 0;
    for (final c in s.codeUnits) {
      if (c == 0x20) k++;
    }
    return k;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    final colWidth = _page.columnWidth;
    final spacing  = _page.columnSpacing;

    double dxCol = offset.dx;
    for (int colIndex = 0; colIndex < _page.columns.length; colIndex++) {
      final colLines = _page.columns[colIndex];
      double dy = offset.dy;

      for (final line in colLines) {
        // ширина «контейнера» строки внутри колонки
        final containerWidth = (line.containerOffsetFactor == 0)
            ? colWidth
            : (colWidth * line.containerOffsetFactor);

        final baseX = dxCol + line.containerOffset;
        final extraSpace = containerWidth - line.width;

        // justify только если не последняя строка абзаца, не после \n и есть что тянуть
        final shouldJustify = line.textAlign == TextAlign.justify
            && !line.isSectionEnd
            && !line.endsWithHardBreak
            && line.spacesCount > 0
            && extraSpace > 0;

        final perGap = shouldJustify ? (extraSpace / line.spacesCount) : 0.0;

        final isRTL = (line.textDirection == TextDirection.rtl);
        double dx;
        switch (line.textAlign) {
          case TextAlign.left:
            dx = isRTL ? (baseX + extraSpace) : baseX;
            break;
          case TextAlign.right:
            dx = isRTL ? baseX : (baseX + extraSpace);
            break;
          case TextAlign.center:
            dx = baseX + extraSpace / 2;
            break;
          case TextAlign.justify:
            dx = baseX; // extraSpace размажем вручную по пробелам
            break;
          default:
            dx = baseX;
            break;
        }

        for (final elem in line.elements) {
          final baselineShift = line.baseline - elem.baseline;
          final elemOffset = Offset(dx, dy + baselineShift);
          elem.paint(canvas, elemOffset);

          dx += elem.width;

          if (perGap > 0 && elem is TextInlineElement && _hasNormalSpaces(elem.text)) {
            dx += perGap * _countNormalSpaces(elem.text);
          }
        }

        dy += line.height + _lineSpacing;
      }

      dxCol += colWidth + spacing;
    }
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerDownEvent) {
      _handleTap(event.localPosition);
    }
  }

  void _handleTap(Offset localPosition) {
    final colWidth = _page.columnWidth;
    final spacing  = _page.columnSpacing;

    for (int colIndex = 0; colIndex < _page.columns.length; colIndex++) {
      final colLines = _page.columns[colIndex];
      final colX = colIndex * (colWidth + spacing);

      double dy = 0.0;
      for (final line in colLines) {
        final containerWidth = (line.containerOffsetFactor == 0)
            ? colWidth
            : (colWidth * line.containerOffsetFactor);
        final baseX = colX + line.containerOffset;
        final extraSpace = containerWidth - line.width;

        final shouldJustify = line.textAlign == TextAlign.justify
            && !line.isSectionEnd
            && !line.endsWithHardBreak
            && line.spacesCount > 0
            && extraSpace > 0;
        final perGap = shouldJustify ? (extraSpace / line.spacesCount) : 0.0;

        final isRTL = (line.textDirection == TextDirection.rtl);
        double dx;
        switch (line.textAlign) {
          case TextAlign.left:
            dx = isRTL ? (baseX + extraSpace) : baseX;
            break;
          case TextAlign.right:
            dx = isRTL ? baseX : (baseX + extraSpace);
            break;
          case TextAlign.center:
            dx = baseX + extraSpace / 2;
            break;
          case TextAlign.justify:
            dx = baseX;
            break;
          default:
            dx = baseX;
            break;
        }

        // если нужны кликабельные зоны — тут же шагайте по элементам,
        // добавляя perGap AFTER каждого обычного пробела, чтобы позиции совпали
        for (final elem in line.elements) {
          final baselineShift = line.baseline - elem.baseline;
          final elemOffset = Offset(dx, dy + baselineShift);

          // пример, если вернёшь getInteractiveRects():
          // for (final rect in elem.getInteractiveRects(elemOffset)) {
          //   if (rect.contains(localPosition)) { ... }
          // }

          dx += elem.width;
          if (perGap > 0 && elem is TextInlineElement && _hasNormalSpaces(elem.text)) {
            dx += perGap * _countNormalSpaces(elem.text);
          }
        }

        dy += line.height + _lineSpacing;
      }
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
  }
}