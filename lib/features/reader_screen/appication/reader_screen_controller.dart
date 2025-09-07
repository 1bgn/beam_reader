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

class ReaderAnchor {
  final int blockIndex;
  final int charOffset;
  const ReaderAnchor(this.blockIndex, this.charOffset);
}

@LazySingleton()
class ReaderPagerController {
  final XmlLoader xmlLoader;
  ReaderPagerController(this.xmlLoader);

  final totalPages = signal<int>(0);

  List<BlockText> _blocks = [];
  late Map<String, Uint8List> _binaries;
  final Map<String, ui.Image> _imgCache = {};

  final List<CustomTextLayout> _pages = [];
  final List<_Cursor> _pageStarts = [];
  final List<_Cursor> _pageEnds   = [];
  _Cursor _cursor = const _Cursor(blockIndex: 0, charOffset: 0);

  bool inited = false;

  static const _baseFontSize = 16.0;
  static const _lineHeight = 1.6;
  static const _pagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 28);

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

  ReaderAnchor anchorForPage(int index) {
    if (index < 0 || index >= _pageStarts.length) return const ReaderAnchor(0, 0);
    final c = _pageStarts[index];
    return ReaderAnchor(c.blockIndex, c.charOffset);
  }

  Future<int> reflow(BuildContext context, {ReaderAnchor? preserve, int backfill = 0}) async {
    // 1) если якорь не передан — считаем, что это начало
    final keep = preserve ?? const ReaderAnchor(0, 0);

    // 2) ПОЛНЫЙ пересчёт ВПЕРЁД ОТ НАЧАЛА, чтобы восстановить все предыдущие страницы
    _resetPagination(const ReaderAnchor(0, 0));

    final wanted = _Cursor(blockIndex: keep.blockIndex, charOffset: keep.charOffset);
    int targetIndex = 0;

    while (true) {
      // если уже есть страницы и последняя "накрыла" якорь — останавливаемся
      if (_pages.isNotEmpty) {
        final st = _pageStarts.last;
        final ed = _pageEnds.last; // end — курсор продолжения НЕ РАНЬШЕ конца страницы
        final stLeWanted = !_isAfter(st, wanted);       // st <= wanted
        final wantedLeEd = !_isAfter(wanted, ed);       // wanted <= ed
        if (stLeWanted && wantedLeEd) {
          targetIndex = _pages.length - 1;
          break;
        }
        // если уже прошли якорь (редкий случай) — ставим на предыдущую
        if (_isAfter(st, wanted)) {
          targetIndex = (_pages.length - 2).clamp(0, _pages.length - 1);
          break;
        }
      }

      final before = _cursor;
      final built = await _buildNextPage(context, _cursor);
      if (built == null) break; // дошли до конца книги

      // инварианты против дублей
      if (!_isAfter(built.end, before)) break;
      if (_pageEnds.isNotEmpty && !_isAfter(built.end, _pageEnds.last)) break;

      _pageStarts.add(before);
      _pages.add(built.layout);
      _pageEnds.add(built.end);
      _cursor = built.end;
      totalPages.value = _pages.length;
    }

    // на всякий: подстроим ещё одну страницу вперёд для плавности
    await ensurePage(context, targetIndex + 1);

    return targetIndex;
  }

  CustomTextLayout? getPage(int index) =>
      (index >= 0 && index < _pages.length) ? _pages[index] : null;

  Future<void> ensurePage(BuildContext context, int pageIndex) async {
    if (pageIndex < 0) return;
    if (pageIndex < _pages.length) return;

    while (_pages.length <= pageIndex) {
      final before = _cursor;
      final built = await _buildNextPage(context, _cursor);
      if (built == null) break;

      // FIX: если страница не продвинула курсор — прекращаем (иначе дубликаты)
      if (!_isAfter(built.end, before)) break;

      // FIX: если есть предыдущая страница и её конец не меньше нового конца — тоже не добавляем
      if (_pageEnds.isNotEmpty && !_isAfter(built.end, _pageEnds.last)) break;

      _pageStarts.add(before);
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

  /* ====================== helpers & invariants ====================== */

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

  bool _cursorEq(_Cursor a, _Cursor b) =>
      a.blockIndex == b.blockIndex && a.charOffset == b.charOffset;

  bool _isAfter(_Cursor a, _Cursor b) =>
      (a.blockIndex > b.blockIndex) ||
          (a.blockIndex == b.blockIndex && a.charOffset > b.charOffset);

  // FIX: гарантированное продвижение минимум на 1 символ/блок
  _Cursor _forceAdvanceAfter(_Cursor candidate, _Cursor current) {
    if (_isAfter(candidate, current)) return candidate;

    // попробуем сдвинуться на 1 символ в текущем блоке
    if (current.blockIndex < _blocks.length) {
      final len = inlineTextTotalLength(_blocks[current.blockIndex].inlines);
      if (current.charOffset < len) {
        return _Cursor(blockIndex: current.blockIndex, charOffset: current.charOffset + 1);
      }
    }
    // иначе — в начало следующего блока
    if (current.blockIndex + 1 < _blocks.length) {
      return _Cursor(blockIndex: current.blockIndex + 1, charOffset: 0);
    }
    // уже конец книги — возвращаем current, upstream отфильтрует бездействие
    return current;
  }

  /* ---------- images ---------- */

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

  /* слово/перенос */
  final RegExp _wordCharRe = RegExp(r'[A-Za-zА-Яа-яЁё0-9]');
  bool _isWordCU(int cu) => _wordCharRe.hasMatch(String.fromCharCode(cu));

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

  /* ===================== build forward page ===================== */

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
          breaksInsideWord = _isWordCU(prevCU) && _isWordCU(nextCU);
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

          // визуально отрезаем последнюю линию
          usedH -= visible[lastLine].height;
          visible = visible.sublist(0, lastLine);
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

    // FIX: жёсткая гарантия продвижения (никаких end == start)
    endCursor = _forceAdvanceAfter(endCursor, start);

    // если после «среза» последней строки вдруг всё опустело — это пустая страница, пропускаем
    if (visible.isEmpty) {
      // позволим внешнему уровню отфильтровать отсутствие прогресса
      if (!_isAfter(endCursor, start)) return null;
    }

    final pageLayout = CustomTextLayout(
      lines: visible,
      totalHeight: usedH,
      paragraphIndexOfLine: layout.paragraphIndexOfLine.take(visible.length).toList(),
    );

    return _BuiltPage(pageLayout, endCursor);
  }

  /* ===================== build previous page (approx) ===================== */
  Future<_BuiltPrevPage?> _buildPrevPage(BuildContext context, _Cursor currentStart) async {
    if (currentStart.blockIndex <= 0 && currentStart.charOffset <= 0) return null;

    const int kMaxLookbackBlocks = 40;
    final int minStart = (currentStart.blockIndex - kMaxLookbackBlocks).clamp(0, _blocks.length);

    _BuiltPage? lastBefore;
    int lastBeforeStartIdx = -1;

    for (int si = minStart; si <= currentStart.blockIndex; si++) {
      final built = await _buildNextPage(context, _Cursor(blockIndex: si, charOffset: 0));
      if (built == null) break;

      if (_isAfter(built.end, currentStart)) {
        if (lastBefore == null) {
          return _BuiltPrevPage(
            layout: built.layout,
            start: _Cursor(blockIndex: si, charOffset: 0),
            end: built.end,
          );
        } else {
          return _BuiltPrevPage(
            layout: lastBefore.layout,
            start: _Cursor(blockIndex: lastBeforeStartIdx, charOffset: 0),
            end: lastBefore.end,
          );
        }
      } else if (_cursorEq(built.end, currentStart)) {
        return _BuiltPrevPage(
          layout: built.layout,
          start: _Cursor(blockIndex: si, charOffset: 0),
          end: built.end,
        );
      }

      lastBefore = built;
      lastBeforeStartIdx = si;
    }

    if (lastBefore != null) {
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

/* ======================= types ======================= */

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
  _BuiltPrevPage({required this.layout, required this.start, required this.end});
}

class _ParaMeta {
  final int blockIndex;
  final int startOffsetInBlock;
  final int textLen;
  const _ParaMeta(this.blockIndex, this.startOffsetInBlock, this.textLen);
}
