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

/// Устойчивый якорь: начало абзаца (id) + offset (используем 0)
class ReaderIdAnchor {
  final String blockId;
  final int charOffset;
  const ReaderIdAnchor(this.blockId, this.charOffset);
}

@LazySingleton()
class ReaderPagerController {
  final XmlLoader xmlLoader;
  ReaderPagerController(this.xmlLoader);

  /* ===== Public state ===== */
  final totalPages = signal<int>(0);

  /* ===== Book ===== */
  List<BlockText> _blocks = [];
  late Map<String, Uint8List> _binaries;
  final Map<String, ui.Image> _imgCache = {};

  /* ===== Pages cache (deque) ===== */
  final List<CustomTextLayout> _pages = [];
  final List<_Cursor> _pageStarts = []; // включительно
  final List<_Cursor> _pageEnds   = []; // эксклюзивно
  _Cursor _cursor = const _Cursor(blockIndex: 0, charOffset: 0); // build next forward from here

  bool inited = false;

  /* ===== Layout params ===== */
  static const _baseFontSize = 16.0;
  static const _lineHeight = 1.6;
  static const _pagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  /* ===== Indices ===== */
  late List<int> _charPrefix; // len = _blocks.length + 1
  int _totalChars = 0;
  int get totalChars => _totalChars;
  late Map<String, int> _idToBlockIndex;

  /* ====== Prefetch throttling ====== */
  int _lastPrefetchCenter = -1;
  int _lastPrefetchAhead = 0;

  /* ========================= API ========================= */

  double pageStartProgress(int pageIndex) {
    if (_totalChars <= 0) return 0.0;
    if (pageIndex < 0 || pageIndex >= _pageStarts.length) return 0.0;
    final _Cursor start = _pageStarts[pageIndex];
    final int g = _globalCharOfCursor(start);
    if (g <= 0) return 0.0;
    if (g >= _totalChars) return 1.0;
    return g / _totalChars;
  }

  Future<void> init(BuildContext context) async {
    if (inited) return;
    inited = true;

    final xml = XmlDocument.parse(await xmlLoader.loadBook());
    final transformer = Fb2Transformer();
    _blocks   = transformer.parseToBlocks(xml.rootElement);
    _binaries = extractBinaryMap(xml);

    _buildIndices();

    _resetPagination(const ReaderAnchor(0, 0));
    await ensurePage(context, 0);
    await ensurePage(context, 1);
  }

  ReaderAnchor anchorForPage(int index) {
    if (index < 0 || index >= _pageStarts.length) return const ReaderAnchor(0, 0);
    final c = _pageStarts[index];
    return ReaderAnchor(c.blockIndex, c.charOffset);
  }

  ReaderIdAnchor idAnchorForPage(int index) {
    if (index < 0 || index >= _pageStarts.length) {
      final firstId = _blocks.isNotEmpty ? _blocks.first.id : '';
      return ReaderIdAnchor(firstId, 0);
    }
    final c = _pageStarts[index];
    final bi = c.blockIndex.clamp(0, _blocks.length - 1);
    return ReaderIdAnchor(_blocks[bi].id, 0);
  }

  Future<int> reflow(BuildContext context, {ReaderAnchor? preserve}) async {
    final keep = preserve ?? const ReaderAnchor(0, 0);
    final bi = keep.blockIndex.clamp(0, _blocks.length);
    _resetPagination(ReaderAnchor(bi, 0));
    await ensurePage(context, 0);
    await ensurePage(context, 1);
    return 0;
  }

  Future<int> reflowFromId(BuildContext context, {required ReaderIdAnchor keep}) async {
    final bi = _idToBlockIndex[keep.blockId] ?? 0;
    _resetPagination(ReaderAnchor(bi.clamp(0, _blocks.length), 0));
    await ensurePage(context, 0);
    await ensurePage(context, 1);
    return 0;
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
      if (!_isAfter(built.end, before)) break;
      if (_pageEnds.isNotEmpty && !_isAfter(built.end, _pageEnds.last)) break;

      _pageStarts.add(before);
      _pages.add(built.layout);
      _pageEnds.add(built.end);
      _cursor = built.end;
      totalPages.value = _pages.length;
    }
  }

  /// Неблокирующая предзагрузка страниц вперёд (используется при свайпе).
  void ensureAhead(BuildContext context, int centerIndex, {int ahead = 3}) {
    // чтобы не плодить одинаковые запросы
    if (_lastPrefetchCenter == centerIndex && _lastPrefetchAhead == ahead) return;
    _lastPrefetchCenter = centerIndex;
    _lastPrefetchAhead = ahead;

    // запускаем в microtask — не блокируем текущий кадр
    Future<void>(() async {
      final want = centerIndex + ahead;
      await ensurePage(context, want);
      // небольшое «веерное» добивание: center+1..center+ahead
      for (int i = centerIndex + 1; i <= want; i++) {
        await ensurePage(context, i);
      }
    });
  }

  /// Ленивая подгрузка прошлых страниц «влево».
  Future<int> lazyEnsurePrev(BuildContext context, {int want = 1}) async {
    if (_pageStarts.isEmpty) return 0;

    int added = 0;
    while (added < want) {
      final currStart = _pageStarts.first;
      if (currStart.blockIndex <= 0 && currStart.charOffset <= 0) break;

      final prev = await _buildPrevPageStrictByBlocks(context, currStart.blockIndex);
      if (prev == null) break;

      if (_isAfter(prev.end, currStart)) {
        final fallback = await _buildPrevPageStrictByBlocks(context, (currStart.blockIndex - 1).clamp(0, _blocks.length));
        if (fallback == null || _isAfter(fallback.end, currStart)) break;
        _pages.insert(0, fallback.layout);
        _pageStarts.insert(0, fallback.start);
        _pageEnds.insert(0, fallback.end);
      } else {
        _pages.insert(0, prev.layout);
        _pageStarts.insert(0, prev.start);
        _pageEnds.insert(0, prev.end);
      }

      totalPages.value = _pages.length;
      added++;
    }
    return added;
  }

  Future<int> jumpToPercent(BuildContext context, double percent) async {
    if (_blocks.isEmpty) return 0;
    if (_totalChars <= 0) {
      _resetPagination(const ReaderAnchor(0, 0));
      await ensurePage(context, 0);
      return 0;
    }

    final p = percent.clamp(0.0, 1.0);
    final targetGlobal = (p * _totalChars).round();

    final curSym = _cursorFromGlobalChar(targetGlobal);
    final bi = curSym.blockIndex.clamp(0, _blocks.length);
    _resetPagination(ReaderAnchor(bi, 0));

    await ensurePage(context, 0);
    await ensurePage(context, 1);
    // сбросим маркеры предзагрузки, чтобы не стопорить ensureAhead после прыжка
    _lastPrefetchCenter = -1;
    _lastPrefetchAhead = 0;
    return 0;
  }

  Future<void> prefetchAround(BuildContext ctx, int index, {int radius = 2}) async {
    for (int i = index - radius; i <= index + radius; i++) {
      if (i >= 0) {
        await ensurePage(ctx, i);
      }
    }
  }

  /* ====================== internals ====================== */

  void _buildIndices() {
    _charPrefix = List<int>.filled(_blocks.length + 1, 0, growable: false);
    _idToBlockIndex = <String, int>{};

    int acc = 0;
    for (int i = 0; i < _blocks.length; i++) {
      final b = _blocks[i];
      _idToBlockIndex[b.id] = i;

      final len = (b.tag == 'image' || b.tag == 'empty-line')
          ? 0
          : inlineTextTotalLength(b.inlines);
      acc += len;
      _charPrefix[i + 1] = acc;
    }
    _totalChars = acc;
  }

  void _resetPagination(ReaderAnchor anchor) {
    _pages.clear();
    _pageStarts.clear();
    _pageEnds.clear();
    _cursor = _Cursor(blockIndex: anchor.blockIndex, charOffset: 0);
    totalPages.value = 0;
    _lastPrefetchCenter = -1;
    _lastPrefetchAhead = 0;
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

  /* ---------- global char helpers ---------- */

  int _globalCharOfCursor(_Cursor c) {
    if (_totalChars == 0) return 0;
    if (c.blockIndex <= 0) return 0;
    if (c.blockIndex >= _blocks.length) return _totalChars;
    final base = _charPrefix[c.blockIndex];
    final len = inlineTextTotalLength(_blocks[c.blockIndex].inlines);
    final off = (c.charOffset.clamp(0, len)) as int;
    return (base + off).clamp(0, _totalChars) as int;
  }

  _Cursor _cursorFromGlobalChar(int g) {
    if (_totalChars == 0) return const _Cursor(blockIndex: 0, charOffset: 0);
    int target = g.clamp(0, _totalChars) as int;
    int lo = 0, hi = _blocks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_charPrefix[mid] <= target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final bi = (lo - 1).clamp(0, _blocks.length);
    final base = _charPrefix[bi];
    final inBlock = target - base;
    final len =
    (bi < _blocks.length) ? inlineTextTotalLength(_blocks[bi].inlines) : 0;
    final off = inBlock.clamp(0, len) as int;
    return _Cursor(blockIndex: bi, charOffset: off);
  }

  /* ---------- build previous page strictly by blocks ---------- */

  Future<_BuiltPrevPage?> _buildPrevPageStrictByBlocks(BuildContext context, int currentStartBlock) async {
    if (currentStartBlock <= 0) return null;

    final int hi = currentStartBlock;
    int lo = (hi - 1).clamp(0, _blocks.length);

    int step = 1;
    bool found = false;
    while (true) {
      final cand = (hi - step).clamp(0, _blocks.length);
      final start = _Cursor(blockIndex: cand, charOffset: 0);
      final built = await _buildNextPage(context, start);
      if (built == null) break;

      if (!_isAfter(built.end, _Cursor(blockIndex: hi, charOffset: 0))) {
        lo = cand;
        found = true;
        break;
      }
      if (cand == 0) break;
      step <<= 1;
    }

    if (!found) {
      final start = _Cursor(blockIndex: lo, charOffset: 0);
      final built = await _buildNextPage(context, start);
      if (built == null) return null;
      if (_isAfter(built.end, _Cursor(blockIndex: hi, charOffset: 0))) return null;
      return _BuiltPrevPage(layout: built.layout, start: start, end: built.end);
    }

    int L = lo, R = hi - 1, best = lo;
    while (L <= R) {
      final mid = (L + R) >> 1;
      final start = _Cursor(blockIndex: mid, charOffset: 0);
      final built = await _buildNextPage(context, start);
      if (built == null) break;

      if (!_isAfter(built.end, _Cursor(blockIndex: hi, charOffset: 0))) {
        best = mid;
        L = mid + 1;
      } else {
        R = mid - 1;
      }
    }

    final start = _Cursor(blockIndex: best, charOffset: 0);
    final built = await _buildNextPage(context, start);
    if (built == null) return null;
    if (_isAfter(built.end, _Cursor(blockIndex: hi, charOffset: 0))) return null;

    return _BuiltPrevPage(layout: built.layout, start: start, end: built.end);
  }

  /* ===================== build forward page ===================== */

  Future<_BuiltPage?> _buildNextPage(BuildContext context, _Cursor start) async {
    if (start.blockIndex >= _blocks.length) return null;

    final mq = MediaQuery.of(context);
    final safeWidth  = mq.size.width  - mq.padding.left - mq.padding.right;
    final safeHeight = mq.size.height - mq.padding.top  - mq.padding.bottom;

    final usableWidth  = safeWidth  - _pagePadding.horizontal;
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

    if (!_isAfter(endCursor, start)) {
      if (start.blockIndex + 1 <= _blocks.length - 1) {
        endCursor = _Cursor(blockIndex: start.blockIndex + 1, charOffset: 0);
      } else {
        return null;
      }
    }

    final pageLayout = CustomTextLayout(
      lines: visible,
      totalHeight: usedH,
      paragraphIndexOfLine: layout.paragraphIndexOfLine.take(visible.length).toList(),
    );

    return _BuiltPage(pageLayout, endCursor);
  }

  /* ===================== helpers ===================== */

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
