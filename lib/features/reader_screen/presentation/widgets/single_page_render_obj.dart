import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import '../../../../engine/elements/layout_blocks/multi_column_page.dart';
import '../../../../engine/elements/layout_blocks/inline_element.dart';
import '../../../../engine/elements/layout_blocks/text_inline_element.dart';

class SinglePageRenderObj extends RenderBox {
  MultiColumnPage _page;
  double _lineSpacing;
  bool _allowSoftHyphens;

  // === selection config ===
  bool _enableSelection;
  bool _doubleTapSelectsWord;
  bool _tripleTapSelectsLine;
  bool _holdToSelect;
  bool _clearSelectionOnSingleTap;

  void Function(String explanation)? onFootnoteTap;
  void Function(int start, int end)? onSelectionChanged;

  // ===== selection state =====
  int? _selBase;   // anchor
  int? _selExtent; // moving end
  bool get _hasSelection => _enableSelection && _selBase != null && _selExtent != null;
  int get _selStart => _hasSelection ? math.min(_selBase!, _selExtent!) : 0;
  int get _selEnd   => _hasSelection ? math.max(_selBase!, _selExtent!) : 0;

  // Long-press gating
  Timer? _longPressTimer;
  int? _activePointer;
  Offset? _downPosition;
  bool _selectMode = false; // активируется по long-press или после double/triple-click
  bool _tapTriggeredSelection = false; // выделение началось тапом (dbl/triple)

  // Multi-tap detection
  Duration? _lastTapUpTime;
  Offset?   _lastTapUpPosition;
  int _lastTapCount = 0; // 0,1,2 — на третий считаем triple

  final Paint _selectionPaint = Paint()..color = const Color(0x333B82F6);

  SinglePageRenderObj({
    required MultiColumnPage page,
    required double lineSpacing,
    required bool allowSoftHyphens,
    required bool enableSelection,
    bool doubleTapSelectsWord = true,
    bool tripleTapSelectsLine = true,
    bool holdToSelect = true,
    bool clearSelectionOnSingleTap = false,
    this.onFootnoteTap,
    this.onSelectionChanged,
  })  : _page = page,
        _lineSpacing = lineSpacing,
        _allowSoftHyphens = allowSoftHyphens,
        _enableSelection = enableSelection,
        _doubleTapSelectsWord = doubleTapSelectsWord,
        _tripleTapSelectsLine = tripleTapSelectsLine,
        _holdToSelect = holdToSelect,
        _clearSelectionOnSingleTap = clearSelectionOnSingleTap;

  // ===== setters =====
  set page(MultiColumnPage value) {
    if (_page != value) {
      _page = value;
      markNeedsLayout();
      markNeedsPaint();
    }
  }
  set lineSpacing(double value) {
    if (_lineSpacing != value) {
      _lineSpacing = value;
      markNeedsLayout();
      markNeedsPaint();
    }
  }
  set allowSoftHyphens(bool value) {
    if (_allowSoftHyphens != value) {
      _allowSoftHyphens = value;
      markNeedsLayout();
      markNeedsPaint();
    }
  }
  set enableSelection(bool value) {
    if (_enableSelection != value) {
      _enableSelection = value;
      if (!_enableSelection) {
        _clearSelection(notify: true);
        _selectMode = false;
        _cancelLongPressTimer();
      }
      markNeedsPaint();
    }
  }
  set doubleTapSelectsWord(bool value) => _doubleTapSelectsWord = value;
  set tripleTapSelectsLine(bool value)  => _tripleTapSelectsLine = value;
  set holdToSelect(bool value)          => _holdToSelect = value;
  set clearSelectionOnSingleTap(bool v) => _clearSelectionOnSingleTap = v;

  // ==== helpers for spaces (justify) ====
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
  int _textLen(InlineElement e) => e is TextInlineElement ? e.text.length : 0;

  // ===== selection set/clear with callback =====
  void _emitSelectionChanged() {
    if (onSelectionChanged != null && _hasSelection) {
      onSelectionChanged!(_selStart, _selEnd);
    }
  }
  void _setSelection(int? base, int? extent, {bool notify = true}) {
    _selBase = base;
    _selExtent = extent;
    if (notify && _hasSelection) _emitSelectionChanged();
    markNeedsPaint();
  }
  void _clearSelection({bool notify = false}) {
    final had = _hasSelection;
    _selBase = _selExtent = null;
    if (notify && had && onSelectionChanged != null) {
      // сообщаем «пустой» диапазон как снятие выделения
      onSelectionChanged!(0, 0);
    }
    markNeedsPaint();
  }

  // ===== selection geometry =====

  int? _offsetForPosition(Offset local) {
    final colWidth = _page.columnWidth;
    final spacing  = _page.columnSpacing;

    final colIndex = (local.dx / (colWidth + spacing)).floor();
    if (colIndex < 0 || colIndex >= _page.columns.length) return null;

    final colLines = _page.columns[colIndex];
    final colX = colIndex * (colWidth + spacing);

    double dy = 0.0;
    for (final line in colLines) {
      final lineTop = dy;
      final lineBottom = dy + line.height;

      if (local.dy >= lineTop && local.dy <= lineBottom) {
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

        int globalOffset = line.startTextOffset;
        for (final elem in line.elements) {
          final elemStartX = dx;
          final elemEndX   = dx + elem.width;

          if (local.dx < elemStartX) {
            return globalOffset;
          }
          if (local.dx <= elemEndX) {
            if (elem is TextInlineElement) {
              final localX = local.dx - elemStartX;
              final intra = elem.caretOffsetForX(localX);
              return globalOffset + intra;
            }
            return globalOffset;
          }

          dx += elem.width;

          if (perGap > 0 && elem is TextInlineElement && _hasNormalSpaces(elem.text)) {
            final gapW = perGap * _countNormalSpaces(elem.text);
            if (local.dx <= dx + gapW) {
              return globalOffset + _textLen(elem);
            }
            dx += gapW;
          }

          globalOffset += _textLen(elem);
        }
        return globalOffset;
      }
      dy += line.height + _lineSpacing;
    }
    return null;
  }

  ({TextInlineElement elem, int elemStart, int local})? _spanAtGlobalOffset(int g, {bool preferPrevOnBoundary = true}) {
    for (final col in _page.columns) {
      for (final line in col) {
        int pos = line.startTextOffset;
        for (final e in line.elements) {
          final len = _textLen(e);
          if (e is TextInlineElement) {
            final start = pos;
            final end   = pos + len;
            if (g > start && g < end) {
              return (elem: e, elemStart: start, local: g - start);
            }
            if (g == end && preferPrevOnBoundary) {
              return (elem: e, elemStart: start, local: len);
            }
            if (g == start && !preferPrevOnBoundary) {
              return (elem: e, elemStart: start, local: 0);
            }
          }
          pos += len;
        }
      }
    }
    return null;
  }

  bool _isSpaceCode(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  bool _selectWordAtPosition(Offset localPos) {
    final g = _offsetForPosition(localPos);
    if (g == null) return false;

    final hit = _spanAtGlobalOffset(g);
    if (hit == null) return false;

    final e = hit.elem;
    final start = hit.elemStart;
    final s = e.text;
    if (s.isEmpty) return false;

    int i = hit.local;
    if (i == s.length) i = s.length - 1;
    if (i < 0) return false;

    while (i >= 0 && _isSpaceCode(s.codeUnitAt(i))) i--;
    if (i < 0) return false;

    int L = i;
    while (L > 0 && !_isSpaceCode(s.codeUnitAt(L - 1))) L--;
    int R = i + 1;
    while (R < s.length && !_isSpaceCode(s.codeUnitAt(R))) R++;

    _setSelection(start + L, start + R);
    _selectMode = true;
    _tapTriggeredSelection = true;
    return true;
  }

  bool _selectLineAtPosition(Offset local) {
    final colWidth = _page.columnWidth;
    final spacing  = _page.columnSpacing;

    final colIndex = (local.dx / (colWidth + spacing)).floor();
    if (colIndex < 0 || colIndex >= _page.columns.length) return false;

    final colLines = _page.columns[colIndex];
    final colX = colIndex * (colWidth + spacing);

    double dy = 0.0;
    for (final line in colLines) {
      final top = dy;
      final bottom = dy + line.height;
      if (local.dy >= top && local.dy <= bottom) {
        int start = line.startTextOffset;
        int end = start;
        for (final e in line.elements) end += _textLen(e);
        _setSelection(start, end);
        _selectMode = true;
        _tapTriggeredSelection = true;
        return true;
      }
      dy += line.height + _lineSpacing;
    }
    return false;
  }

  void _paintSelectionForLine(Canvas canvas, Offset colOrigin, double colWidth, double perGap, line) {
    int lineStart = line.startTextOffset;
    int lineEnd   = lineStart;
    for (final e in line.elements) lineEnd += _textLen(e);

    final selStart = _selStart.clamp(lineStart, lineEnd);
    final selEnd   = _selEnd.clamp(lineStart, lineEnd);
    if (selStart >= selEnd) return;

    final containerWidth = (line.containerOffsetFactor == 0)
        ? colWidth
        : (colWidth * line.containerOffsetFactor);
    final baseX = colOrigin.dx + line.containerOffset;
    final extraSpace = containerWidth - line.width;

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

    final dyBase = colOrigin.dy;

    int pos = lineStart;
    for (final elem in line.elements) {
      final elemStart = pos;
      final elemEnd   = pos + _textLen(elem);

      final a = math.max(selStart, elemStart);
      final b = math.min(selEnd,   elemEnd);
      final hasSelectionHere = a < b;

      final baselineShift = line.baseline - elem.baseline;

      if (elem is TextInlineElement && hasSelectionHere) {
        final localStart = a - elemStart;
        final localEnd   = b - elemStart;

        final boxes = elem.selectionBoxes(localStart, localEnd);
        for (final tb in boxes) {
          final w = tb.right - tb.left;
          final h = tb.bottom - tb.top;
          final rect = Rect.fromLTWH(
            dx + tb.left,
            dyBase + baselineShift + tb.top,
            w,
            h,
          );
          canvas.drawRect(rect, _selectionPaint);
        }

        if (perGap > 0 && boxes.isNotEmpty) {
          final spacesInRange = elem.countSpacesInRange(localStart, localEnd);
          if (spacesInRange > 0) {
            final lastBox = boxes.last;
            final h = lastBox.bottom - lastBox.top;
            final extRect = Rect.fromLTWH(
              dx + lastBox.right,
              dyBase + baselineShift + lastBox.top,
              perGap * spacesInRange,
              h,
            );
            canvas.drawRect(extRect, _selectionPaint);
          }
        }
      }

      dx += elem.width;

      if (perGap > 0 && elem is TextInlineElement && _hasNormalSpaces(elem.text)) {
        dx += perGap * _countNormalSpaces(elem.text);
      }

      pos = elemEnd;
    }
  }

  // ===== RenderBox overrides =====

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
        final containerWidth = (line.containerOffsetFactor == 0)
            ? colWidth
            : (colWidth * line.containerOffsetFactor);
        final baseX = dxCol + line.containerOffset;
        final extraSpace = containerWidth - line.width;

        final shouldJustify = line.textAlign == TextAlign.justify
            && !line.isSectionEnd
            && !line.endsWithHardBreak
            && line.spacesCount > 0
            && extraSpace > 0;
        final perGap = shouldJustify ? (extraSpace / line.spacesCount) : 0.0;

        if (_hasSelection) {
          _paintSelectionForLine(canvas, Offset(dxCol, dy), colWidth, perGap, line);
        }

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
  bool hitTestSelf(Offset position) => true;

  void _startLongPressTimer() {
    _longPressTimer?.cancel();
    if (!_holdToSelect) return;
    _longPressTimer = Timer(kLongPressTimeout, () {
      if (!_enableSelection) return;
      if (_downPosition == null) return;
      final off = _offsetForPosition(_downPosition!);
      if (off != null) {
        _selectMode = true;
        _tapTriggeredSelection = false;
        _setSelection(off, off);
      }
    });
  }
  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }
  void _resetPointerTracking() {
    _activePointer = null;
    _downPosition = null;
    _selectMode = false;
    _tapTriggeredSelection = false;
    _cancelLongPressTimer();
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (!_enableSelection) return;

    if (event is PointerDownEvent) {
      if (_activePointer != null) return;
      _activePointer = event.pointer;
      _downPosition = event.localPosition;
      _selectMode = false;
      _tapTriggeredSelection = false;

      // Multi-tap detection (считаем относительно последнего UP)
      final withinTime = _lastTapUpTime != null &&
          (event.timeStamp - _lastTapUpTime!) <= kDoubleTapTimeout;
      final withinSlop = _lastTapUpPosition != null &&
          (event.localPosition - _lastTapUpPosition!).distance <= kDoubleTapSlop;

      int currentTapCount;
      if (withinTime && withinSlop) {
        currentTapCount = (_lastTapCount + 1).clamp(1, 3);
      } else {
        currentTapCount = 1;
      }

      // triple-click -> выделяем строку
      if (currentTapCount >= 3 && _tripleTapSelectsLine) {
        _cancelLongPressTimer();
        if (_selectLineAtPosition(event.localPosition)) {
          _selectMode = true;      // разрешаем тянуть дальше
          _lastTapCount = 0;       // сбрасываем последовательность
          return;
        }
      }

      // double-click -> слово
      if (currentTapCount == 2 && _doubleTapSelectsWord) {
        _cancelLongPressTimer();
        if (_selectWordAtPosition(event.localPosition)) {
          _selectMode = true;
          _lastTapCount = 2; // зафиксируем — UP завершит двойной
          return;
        }
      }

      // иначе ожидаем удержание (если включено)
      _startLongPressTimer();
    } else if (event is PointerMoveEvent) {
      if (_activePointer != event.pointer) return;

      // До активации — даём скроллу победить
      if (!_selectMode && _downPosition != null) {
        final delta = (event.localPosition - _downPosition!).distance;
        if (delta > kTouchSlop) {
          _cancelLongPressTimer();
        }
        return;
      }

      if (_selectMode) {
        final off = _offsetForPosition(event.localPosition);
        if (off != null) {
          _selExtent = off;
          _emitSelectionChanged();
          markNeedsPaint();
        }
      }
    } else if (event is PointerUpEvent) {
      if (_activePointer != event.pointer) return;

      // Обновляем данные для следующего multi-tap
      _lastTapUpTime = event.timeStamp;
      _lastTapUpPosition = event.localPosition;
      // если на этом DOWN мы уже считали тап как 2-й/3-й — продолжим цепочку
      final withinTime = _lastTapUpTime != null &&
          (event.timeStamp - _lastTapUpTime!) <= kDoubleTapTimeout;
      final withinSlop = _lastTapUpPosition != null &&
          (event.localPosition - _lastTapUpPosition!).distance <= kDoubleTapSlop;
      if (!(withinTime && withinSlop)) {
        _lastTapCount = 1;
      } else {
        _lastTapCount = (_lastTapCount + 1).clamp(1, 3);
      }

      // Если выделение не стартовало (ни long-press, ни dbl/triple),
      // и включена очистка — снимаем выделение одиночным тапом
      if (!_selectMode && !_tapTriggeredSelection && _clearSelectionOnSingleTap) {
        _clearSelection(notify: true);
      }

      _resetPointerTracking();
    } else if (event is PointerCancelEvent) {
      if (_activePointer != event.pointer) return;
      _resetPointerTracking();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
  }
}
