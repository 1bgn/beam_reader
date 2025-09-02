import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import '../../../../engine/elements/layout_blocks/multi_column_page.dart';

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

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerDownEvent) {
      _handleTap(event.localPosition);
    }
  }

  void _handleTap(Offset localPosition) {
    final colWidth = _page.columnWidth;
    final spacing = _page.columnSpacing;

    for (int colIndex = 0; colIndex < _page.columns.length; colIndex++) {
      final colLines = _page.columns[colIndex];
      final colX = colIndex * (colWidth + spacing);

      double dy = 0.0;
      for (final line in colLines) {
        final lineTop = dy;

        // Упрощённая логика выравнивания
        double dx = colX;
        final extraSpace = colWidth - line.width;
        final isRTL = (line.textDirection == TextDirection.rtl);
        switch (line.textAlign) {
          case TextAlign.left:
            dx = isRTL ? (colX + extraSpace) : colX;
            break;
          case TextAlign.right:
            dx = isRTL ? colX : (colX + extraSpace);
            break;
          case TextAlign.center:
            dx = colX + extraSpace / 2;
            break;
          case TextAlign.justify:
            dx = colX;
            break;
          default:
            break;
        }

        for (final elem in line.elements) {
          final baselineShift = line.baseline - elem.baseline;
          final elemOffset = Offset(dx, lineTop + baselineShift);

          // final rects = elem.getInteractiveRects(elemOffset);
          // for (final rect in rects) {
          //   if (rect.contains(localPosition)) {
          //     if (elem is FootnoteInlineElement) {
          //       onFootnoteTap?.call(elem.explanation);
          //       return;
          //     }
          //   }
          // }
          dx += elem.width;
        }

        dy += line.height + _lineSpacing;
      }
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    final colWidth = _page.columnWidth;
    final spacing = _page.columnSpacing;

    double dxCol = offset.dx;
    for (int colIndex = 0; colIndex < _page.columns.length; colIndex++) {
      final colLines = _page.columns[colIndex];
      double dy = offset.dy;
      for (final line in colLines) {
        double dx = dxCol;
        final extraSpace = colWidth - line.width;
        final isRTL = (line.textDirection == TextDirection.rtl);

        switch (line.textAlign) {
          case TextAlign.left:
            dx = isRTL ? (dxCol + extraSpace) : dxCol;
            break;
          case TextAlign.right:
            dx = isRTL ? dxCol : (dxCol + extraSpace);
            break;
          case TextAlign.center:
            dx = dxCol + extraSpace / 2;
            break;
          case TextAlign.justify:
            dx = dxCol;
            break;
          default:
            break;
        }

        for (final elem in line.elements) {
          final baselineShift = line.baseline - elem.baseline;
          final elemOffset = Offset(dx, dy + baselineShift);
          elem.paint(canvas, elemOffset);
          dx += elem.width;
        }

        dy += line.height + _lineSpacing;
      }
      dxCol += colWidth + spacing;
    }
  }
}