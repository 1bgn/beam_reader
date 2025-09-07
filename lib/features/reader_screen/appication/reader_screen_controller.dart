// lib/features/reader_screen/appication/reader_screen_controller.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xml/xml.dart';

import 'package:beam_reader/engine/xml_loader.dart';
import 'package:beam_reader/engine/advanced_layout_engine.dart';
import 'package:beam_reader/engine/elements/fb2_style_map.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/image_inline_element.dart';
import 'package:beam_reader/engine/elements/layout_blocks/line_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/paragraph_block.dart';
import 'package:beam_reader/engine/elements/layout_blocks/text_inline_element.dart';
import 'package:beam_reader/engine/elements/text_utils.dart';

import 'package:beam_reader/engine/elements/data_blocks/block_text.dart';
import 'package:beam_reader/engine/fb2_transform.dart';

/// Совместимость с UI: якорь «позиции в тексте»
class ReaderAnchor {
  final int blockIndex;
  final int charOffset;
  const ReaderAnchor(this.blockIndex, this.charOffset);
}

@LazySingleton()
class ReaderPagerController {
  final XmlLoader xmlLoader;
  ReaderPagerController(this.xmlLoader);

  /* ===== Сигналы ===== */
  final totalPages = signal<int>(0);

  /* ===== Книга ===== */
  List<BlockText> _blocks = [];
  late Map<String, Uint8List> _binaries;
  final Map<String, ui.Image> _imgCache = {};

  /* ===== Кэш страниц ===== */
  final List<CustomTextLayout> _pages = [];
  final List<_Cursor> _pageStarts = []; // откуда начиналась страница i
  final List<_Cursor> _pageEnds   = []; // где закончилась страница i
  _Cursor _cursor = const _Cursor(blockIndex: 0, charOffset: 0); // старт для следующей вперёд

  bool inited = false;

  /* ===== Параметры верстки ===== */
  static const _baseFontSize = 16.0;
  static const _lineHeight = 1.6;
  static const _pagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  /* ========================= API ========================= */

  Future<void> init(BuildContext context) async {
    if (inited) return;
    inited = true;

    final xml = XmlDocument.parse(await xmlLoader.loadBook());
    final transformer = Fb2Transformer();
    _blocks   = transformer.parseToBlocks(xml.rootElement);
    _binaries = extractBinaryMap(xml);

    _resetPagination(const ReaderAnchor(0, 0));
    await ensurePage(context, 0);
    await ensurePage(context, 1);
  }

  /// Возврат стартового курсора страницы (совместимость).
  ReaderAnchor anchorForPage(int index) {
    if (index < 0 || index >= _pageStarts.length) return const ReaderAnchor(0, 0);
    final c = _pageStarts[index];
    return ReaderAnchor(c.blockIndex, c.charOffset);
  }

  /// Полный пересчёт. Построит страницы вперёд от preserve и **backfill** страниц назад.
  /// Возвращает индекс страницы, на которую стоит перейти после пересчёта.
  Future<int> reflow(BuildContext context, {ReaderAnchor? preserve, int backfill = 3}) async {
    final keep = preserve ?? const ReaderAnchor(0, 0);
    _resetPagination(keep);

    // Сначала строим «текущую» и следующую вперёд — чтобы показать экран
    await ensurePage(context, 0);
    await ensurePage(context, 1);

    // Затем достроим несколько страниц НАЗАД, чтобы пользователь мог листать влево
    int builtBack = 0;
    for (; builtBack < backfill; builtBack++) {
      final prev = await _buildPrevPage(context, _pageStarts.isEmpty ? _cursor : _pageStarts.first);
      if (prev == null) break;
      // prepend
      _pages.insert(0, prev.layout);
      _pageStarts.insert(0, prev.start);
      _pageEnds.insert(0, prev.end);
    }
    if (builtBack > 0) {
      totalPages.value = _pages.length;
    }

    // вернуть индекс «текущей» страницы с учетом префикса
    return builtBack;
  }

  CustomTextLayout? getPage(int index) =>
      (index >= 0 && index < _pages.length) ? _pages[index] : null;

  /// Лениво гарантирует наличие страницы.
  Future<void> ensurePage(BuildContext context, int pageIndex) async {
    if (pageIndex < 0) return;
    if (pageIndex < _pages.length) return;

    while (_pages.length <= pageIndex) {
      final built = await _buildNextPage(context, _cursor);
      if (built == null) break;
      _pageStarts.add(_cursor);
      _pages.add(built.layout);
      _pageEnds.add(built.end);
      _cursor = built.end;
      totalPages.value = _pages.length;
    }
  }

  Future<void> prefetchAround(BuildContext ctx, int index, {int radius = 2}) async {
    for (int i = index - radius; i <= index + radius; i++) {
      if (i >= 0) {
        await ensurePage(ctx, i);
      }
    }
  }

  /* ====================== Внутренности ====================== */

  void _resetPagination(ReaderAnchor anchor) {
    _pages.clear();
    _pageStarts.clear();
    _pageEnds.clear();
    _cursor = _Cursor(blockIndex: anchor.blockIndex, charOffset: anchor.charOffset);
    totalPages.value = 0;
  }

  int _sectionOfBlock(int bi) {
    if (bi < 0 || bi >= _blocks.length) return -1;
    final s = _blocks[bi].attrs['__section'];
    return int.tryParse(s ?? '') ?? -1;
  }

  bool _isZeroLengthBlock(int bi) {
    if (bi < 0 || bi >= _blocks.length) return true;
    final b = _blocks[bi];
    if (b.tag == 'image' || b.tag == 'empty-line') return true;
    return inlineTextTotalLength(b.inlines) == 0;
  }

  bool _isAfter(_Cursor a, _Cursor b) =>
      (a.blockIndex > b.blockIndex) ||
          (a.blockIndex == b.blockIndex && a.charOffset > b.charOffset);

  bool _isAfterOrEq(_Cursor a, _Cursor b) =>
      a.blockIndex > b.blockIndex ||
          (a.blockIndex == b.blockIndex && a.charOffset >= b.charOffset);

  /* ---------- ресурсы изображений ---------- */

  Future<ui.Image?> _resolveImageForAttrs(Map<String, String>? attrs) async {
    if (attrs == null) return null;
    final href = attrs['href'] ?? attrs['xlink:href'];
    if (href == null || href.isEmpty) return null;
    final id = href.startsWith('#') ? href.substring(1) : href;

    final cached = _imgCache[id];
    if (cached != null) return cached;

    final bytes = _binaries[id];
    if (bytes == null) return null;

    final img = await decodeUiImage(bytes);
    _imgCache[id] = img;
    return img;
  }

  Future<void> _pushBlockSliceAsParagraphWithMeta({
    required BuildContext context,
    required int blockIndex,
    required BlockText block,
    required int skipCharsFromStart,
    required List<ParagraphBlock> paragraphs,
    required List<_ParaMeta> metas,
  }) async {
    final s = fb2BlockRenderStyle(
      tag: block.tag,
      depth: block.depth,
      baseFontSize: _baseFontSize,
      lineHeight: _lineHeight,
      color: Colors.black,
    );

    if (block.tag == 'empty-line') {
      paragraphs.add(
        ParagraphBlock(
          inlineElements: const [],
          textAlign: TextAlign.start,
          paragraphSpacing: s.paragraphSpacing,
        ),
      );
      metas.add(_ParaMeta(blockIndex, 0, 0));
      return;
    }

    if (block.tag == 'image') {
      final img = await _resolveImageForAttrs(block.attrs);
      if (img != null) {
        final mq = MediaQuery.of(context);
        final safeH = mq.size.height - mq.padding.top - mq.padding.bottom;
        final usableH = safeH - _pagePadding.vertical;
        final maxH = (usableH * 0.9).clamp(1.0, double.infinity);

        paragraphs.add(
          ParagraphBlock(
            inlineElements: [
              ImageInlineElement(
                image: img,
                maxHeight: maxH,
                radius: BorderRadius.circular(8),
              ),
            ],
            textAlign: s.textAlign,
            paragraphSpacing: s.paragraphSpacing,
            enableRedLine: false,
            firstLineIndent: 0,
            maxWidth: s.containerWidthFactor ?? 0.92,
            containerAlignment: s.containerAlign ?? TextAlign.center,
          ),
        );
      }
      metas.add(_ParaMeta(blockIndex, 0, 0));
      return;
    }

    final totalLen = inlineTextTotalLength(block.inlines);
    final full = buildInlineElements(block.inlines, s.textStyle);
    final sliced = sliceInlineElementsFromStart(full, skipCharsFromStart);
    paragraphs.add(
      ParagraphBlock(
        inlineElements: sliced,
        textAlign: s.textAlign,
        paragraphSpacing: s.paragraphSpacing,
        enableRedLine: skipCharsFromStart != 0 ? false : s.enableRedLine,
        firstLineIndent: s.firstLineIndent,
        maxWidth: s.containerWidthFactor,
        containerAlignment: s.containerAlign,
      ),
    );

    final textLenAfterSlice = (totalLen - skipCharsFromStart).clamp(0, totalLen);
    metas.add(_ParaMeta(blockIndex, skipCharsFromStart, textLenAfterSlice));
  }

  bool _lineEndsWithDrawnHyphen(LineLayout line) {
    for (int i = line.elements.length - 1; i >= 0; i--) {
      final e = line.elements[i];
      if (e is TextInlineElement && e.text.isNotEmpty) {
        return e.text.codeUnitAt(e.text.length - 1) == 0x2D; // '-'
      }
    }
    return false;
  }

  int _countParaCharsInLinesRange({
    required List<LineLayout> lines,
    required List<int> pidx,
    required int paraIndex,
    required int startLine,
    required int endLineInclusive,
  }) {
    if (lines.isEmpty) return 0;
    final s = startLine.clamp(0, lines.length - 1);
    final e = endLineInclusive.clamp(s, lines.length - 1);

    int total = 0;
    for (int li = s; li <= e; li++) {
      if (pidx[li] != paraIndex) continue;

      int lineChars = 0;
      for (final el in lines[li].elements) {
        if (el is TextInlineElement) {
          lineChars += el.text.replaceAll('\u00AD', '').length;
        }
      }
      if (_lineEndsWithDrawnHyphen(lines[li]) && lineChars > 0) lineChars -= 1;
      if (lineChars > 0) total += lineChars;
    }
    return total;
  }

  String _concatParagraphText(ParagraphBlock p) {
    final sb = StringBuffer();
    for (final e in p.inlineElements) {
      if (e is TextInlineElement) sb.write(e.text);
    }
    return sb.toString();
  }

  /* ===================== Построение страниц вперёд ===================== */

  Future<_BuiltPage?> _buildNextPage(BuildContext context, _Cursor start) async {
    if (start.blockIndex >= _blocks.length) return null;

    final mq = MediaQuery.of(context);
    final safeWidth = mq.size.width - mq.padding.left - mq.padding.right;
    final safeHeight = mq.size.height - mq.padding.top - mq.padding.bottom;
    final usableWidth = safeWidth - _pagePadding.horizontal;
    final usableHeight = safeHeight - _pagePadding.vertical;

    final paragraphs = <ParagraphBlock>[];
    final metas = <_ParaMeta>[];

    int bi = start.blockIndex;
    int skip = start.charOffset;

    final int pageSection = _sectionOfBlock(start.blockIndex);
    bool forcedSectionBreak = false;

    CustomTextLayout? layout;
    List<LineLayout> visible = [];
    double usedH = 0;

    int prevCount = -1;
    int stagnant = 0;
    const kMaxStagnant = 2;

    while (bi < _blocks.length) {
      if (paragraphs.isNotEmpty && _sectionOfBlock(bi) != pageSection) {
        forcedSectionBreak = true;
        break;
      }

      await _pushBlockSliceAsParagraphWithMeta(
        context: context,
        blockIndex: bi,
        block: _blocks[bi],
        skipCharsFromStart: skip,
        paragraphs: paragraphs,
        metas: metas,
      );
      bi++;
      skip = 0;

      final engine = AdvancedLayoutEngine(
        allowSoftHyphens: true,
        paragraphs: paragraphs,
        globalMaxWidth: usableWidth,
        globalTextAlign: TextAlign.justify,
      );
      layout = engine.layoutAllParagraphs();

      visible = [];
      usedH = 0;
      for (final line in layout.lines) {
        final h = line.height;
        if (usedH + h > usableHeight && visible.isNotEmpty) break;
        visible.add(line);
        usedH += h;
      }

      if (visible.length == prevCount) {
        stagnant++;
        if (stagnant >= kMaxStagnant) break;
      } else {
        stagnant = 0;
        prevCount = visible.length;
      }

      if (usedH >= usableHeight) break;

      if (bi < _blocks.length && _sectionOfBlock(bi) != pageSection) {
        forcedSectionBreak = true;
        break;
      }
    }

    if (layout == null) return null;

    // --- конец страницы (куда продолжать дальше) ---
    late _Cursor endCursor;

    if (visible.isEmpty) {
      int nb = metas.isNotEmpty ? metas.last.blockIndex + 1 : start.blockIndex + 1;
      while (nb < _blocks.length && _isZeroLengthBlock(nb)) nb++;
      endCursor = _Cursor(blockIndex: nb.clamp(0, _blocks.length), charOffset: 0);
    } else if (forcedSectionBreak) {
      endCursor = _Cursor(blockIndex: bi, charOffset: 0);
    } else {
      final pidx = layout.paragraphIndexOfLine;
      final lastLine = visible.length - 1;
      final lastPara = pidx[lastLine];

      final totalLinesPerPara = <int, int>{};
      for (final idx in pidx) {
        totalLinesPerPara[idx] = (totalLinesPerPara[idx] ?? 0) + 1;
      }
      final visibleLinesPerPara = <int, int>{};
      for (int i = 0; i <= lastLine; i++) {
        final pid = pidx[i];
        visibleLinesPerPara[pid] = (visibleLinesPerPara[pid] ?? 0) + 1;
      }

      final totalInLast = totalLinesPerPara[lastPara] ?? 0;
      final visibleInLast = visibleLinesPerPara[lastPara] ?? 0;
      final bool hasInvisibleParas = lastPara < (paragraphs.length - 1);

      final bool lastIsImage = paragraphs[lastPara].inlineElements.any((e) => e is ImageInlineElement);

      if (lastIsImage) {
        final meta = metas[lastPara];
        endCursor = _Cursor(blockIndex: meta.blockIndex + 1, charOffset: 0);
      } else if (visibleInLast < totalInLast) {
        int charsVisible = _countParaCharsInLinesRange(
          lines: visible,
          pidx: pidx,
          paraIndex: lastPara,
          startLine: 0,
          endLineInclusive: lastLine,
        );

        final endsWithHyphen = _lineEndsWithDrawnHyphen(visible[lastLine]);
        if (endsWithHyphen && charsVisible > 0) charsVisible -= 1;

        final paraText = _concatParagraphText(paragraphs[lastPara]);
        bool breaksInsideWord = false;
        if (charsVisible > 0 && charsVisible < paraText.length) {
          final prevCU = paraText.codeUnitAt(charsVisible - 1);
          final nextCU = paraText.codeUnitAt(charsVisible);
          bool isWord(int cu) => RegExp(r'[A-Za-zА-Яа-яЁё0-9]').hasMatch(String.fromCharCode(cu));
          breaksInsideWord = isWord(prevCU) && isWord(nextCU);
        }

        if ((breaksInsideWord || endsWithHyphen) && visible.length > 1) {
          final charsBeforeLastLine = _countParaCharsInLinesRange(
            lines: visible,
            pidx: pidx,
            paraIndex: lastPara,
            startLine: 0,
            endLineInclusive: lastLine - 1,
          );
          final meta = metas[lastPara];
          endCursor = _Cursor(
            blockIndex: meta.blockIndex,
            charOffset: meta.startOffsetInBlock + charsBeforeLastLine,
          );
        } else {
          final meta = metas[lastPara];
          endCursor = _Cursor(
            blockIndex: meta.blockIndex,
            charOffset: meta.startOffsetInBlock + charsVisible,
          );
        }
      } else if (hasInvisibleParas) {
        final nextMeta = metas[lastPara + 1];
        endCursor = _Cursor(
          blockIndex: nextMeta.blockIndex,
          charOffset: nextMeta.startOffsetInBlock,
        );
      } else {
        final meta = metas[lastPara];
        endCursor = _Cursor(blockIndex: meta.blockIndex + 1, charOffset: 0);
      }
    }

    final pageLayout = CustomTextLayout(
      lines: visible,
      totalHeight: usedH,
      paragraphIndexOfLine: layout.paragraphIndexOfLine.take(visible.length).toList(),
    );

    return _BuiltPage(pageLayout, endCursor);
  }

  /* ===================== Построение предыдущей страницы ===================== */
  /// Строит страницу, которая заканчивается ровно в `currentStart` (или как можно ближе перед ним).
  /// Возвращает layout и пару курсоров: start..end (end ~= currentStart).
  Future<_BuiltPrevPage?> _buildPrevPage(BuildContext context, _Cursor currentStart) async {
    if (currentStart.blockIndex <= 0 && currentStart.charOffset <= 0) return null;

    // Поищем старт не дальше, чем на 40 блоков назад — дешево и сердито.
    const int kMaxLookbackBlocks = 40;
    final int minStart = (currentStart.blockIndex - kMaxLookbackBlocks).clamp(0, _blocks.length);

    _BuiltPage? lastBefore; // последний, чей end <= currentStart
    for (int si = minStart; si <= currentStart.blockIndex; si++) {
      final built = await _buildNextPage(context, _Cursor(blockIndex: si, charOffset: 0));
      if (built == null) break;

      if (_isAfter(built.end, currentStart)) {
        // Переступили границу — предыдущий был лучшим кандидатом
        if (lastBefore == null) {
          // крайний случай: даже с minStart страница вышла дальше currentStart.
          // Тогда вернём её — пользователь всё равно увидит максимально возможный объем.
          return _BuiltPrevPage(
            layout: built.layout,
            start: _Cursor(blockIndex: si, charOffset: 0),
            end: built.end,
          );
        } else {
          final startIdx = (si - 1).clamp(0, _blocks.length);
          return _BuiltPrevPage(
            layout: lastBefore.layout,
            start: _Cursor(blockIndex: startIdx, charOffset: 0),
            end: lastBefore.end,
          );
        }
      } else if (_isAfterOrEq(built.end, currentStart)) {
        // Закончились ровно на нужной позиции
        return _BuiltPrevPage(
          layout: built.layout,
          start: _Cursor(blockIndex: si, charOffset: 0),
          end: built.end,
        );
      }

      lastBefore = built; // пока страница заканчивается раньше — запомним
    }

    // Если цикл закончился и мы так и не переступили — берём последний вариант «до»
    if (lastBefore != null) {
      final bestStart = (currentStart.blockIndex).clamp(0, _blocks.length);
      // start у lastBefore соответствует тому si, на котором он строился — мы не сохранили его.
      // Для простоты пересчитаем ещё раз.
      for (int si = currentStart.blockIndex; si >= minStart; si--) {
        final probe = await _buildNextPage(context, _Cursor(blockIndex: si, charOffset: 0));
        if (probe == null) break;
        if (!_isAfter(probe.end, currentStart)) {
          return _BuiltPrevPage(
            layout: probe.layout,
            start: _Cursor(blockIndex: si, charOffset: 0),
            end: probe.end,
          );
        }
      }
    }

    return null;
  }
}

/* ======================= Вспомогательные типы ======================= */

class _Cursor {
  final int blockIndex;
  final int charOffset;
  const _Cursor({required this.blockIndex, required this.charOffset});
}

class _BuiltPage {
  final CustomTextLayout layout;
  final _Cursor end;
  _BuiltPage(this.layout, this.end);
}

class _BuiltPrevPage {
  final CustomTextLayout layout;
  final _Cursor start;
  final _Cursor end;
  _BuiltPrevPage({
    required this.layout,
    required this.start,
    required this.end,
  });
}

class _ParaMeta {
  final int blockIndex;
  final int startOffsetInBlock;
  final int textLen;
  const _ParaMeta(this.blockIndex, this.startOffsetInBlock, this.textLen);
}
