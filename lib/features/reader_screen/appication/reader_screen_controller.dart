// lib/features/reader_screen/appication/reader_pager_controller.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beam_reader/engine/advanced_layout_engine.dart';
import 'package:beam_reader/engine/elements/fb2_style_map.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/image_inline_element.dart';
import 'package:beam_reader/engine/elements/layout_blocks/line_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/paragraph_block.dart';
import 'package:beam_reader/engine/elements/layout_blocks/text_inline_element.dart';
import 'package:beam_reader/engine/elements/text_utils.dart';
import 'package:beam_reader/engine/fb2_transform.dart';
import 'package:beam_reader/engine/xml_loader.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xml/xml.dart';

import '../../../engine/elements/data_blocks/block_text.dart';

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

  late List<BlockText> _blocks;
  late Map<String, Uint8List> _binaries;
  final Map<String, ui.Image> _imgCache = {};

  final Map<int, CustomTextLayout> _pageCache = {};
  final List<_PageAnchor> _anchors = [];
  final Map<int, Future<void>> _inflight = {};

  bool _inited = false;

  static const _baseFontSize = 16.0;
  static const _lineHeight   = 1.6;
  static const _pagePadding  = EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  /* API */

  ReaderAnchor anchorForPage(int index) {
    if (_anchors.isEmpty) return const ReaderAnchor(0, 0);
    final i = index.clamp(0, _anchors.length - 1);
    final a = _anchors[i];
    return ReaderAnchor(a.blockIndex, a.charOffset);
  }

  Future<void> reflow(BuildContext context, {ReaderAnchor? preserve}) async {
    final keep = preserve ?? anchorForPage(0);
    _pageCache.clear();
    _inflight.clear();
    _anchors
      ..clear()
      ..add(_PageAnchor(blockIndex: keep.blockIndex, charOffset: keep.charOffset));
    totalPages.value = 1;
    await Future.wait([ensurePage(context, 0), ensurePage(context, 1)]);
  }

  Future<void> init(BuildContext context) async {
    if (_inited) return;
    _inited = true;

    final xml = XmlDocument.parse(await xmlLoader.loadBook());
    final transformer = Fb2Transformer();
    _blocks   = transformer.parseToBlocks(xml.rootElement);
    _binaries = extractBinaryMap(xml);

    _anchors.add(const _PageAnchor(blockIndex: 0, charOffset: 0));
    totalPages.value = 1;

    await Future.wait([ensurePage(context, 0), ensurePage(context, 1)]);
  }

  CustomTextLayout? getPage(int index) => _pageCache[index];

  Future<void> ensurePage(BuildContext context, int pageIndex) async {
    if (pageIndex < 0) return;

    final infl = _inflight[pageIndex];
    if (infl != null) { await infl; return; }

    while (pageIndex >= _anchors.length) {
      final lastIdx = _anchors.length - 1;
      final before  = _anchors.length;
      final fut = _buildAndCachePage(context, lastIdx, computeNextAnchorOnly: true);
      _inflight[lastIdx] = fut;
      await fut.whenComplete(() => _inflight.remove(lastIdx));
      if (_anchors.length == before) break;
    }

    if (_pageCache.containsKey(pageIndex)) return;

    final fut2 = _buildAndCachePage(context, pageIndex);
    _inflight[pageIndex] = fut2;
    await fut2.whenComplete(() => _inflight.remove(pageIndex));
  }

  Future<void> prefetchAround(BuildContext ctx, int index, {int radius = 2}) async {
    for (int i = index - radius; i <= index + radius; i++) {
      if (i >= 0) { await ensurePage(ctx, i); }
    }
  }

  /* Low level */

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
      paragraphs.add(ParagraphBlock(
        inlineElements: const [],
        textAlign: TextAlign.start,
        paragraphSpacing: s.paragraphSpacing,
      ));
      metas.add(_ParaMeta(blockIndex, 0, 0));
      return;
    }

    if (block.tag == 'image') {
      final img = await _resolveImageForAttrs(block.attrs);
      if (img != null) {
        final mq = MediaQuery.of(context);
        final safeH   = mq.size.height - mq.padding.top - mq.padding.bottom;
        final usableH = safeH - _pagePadding.vertical;
        final maxH    = (usableH * 0.9).clamp(1.0, double.infinity);

        paragraphs.add(ParagraphBlock(
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
        ));
      }
      metas.add(_ParaMeta(blockIndex, 0, 0));
      return;
    }

    final totalLen = inlineTextTotalLength(block.inlines);
    final full     = buildInlineElements(block.inlines, s.textStyle);
    final sliced   = sliceInlineElementsFromStart(full, skipCharsFromStart);

    paragraphs.add(ParagraphBlock(
      inlineElements: sliced,
      textAlign: s.textAlign,
      paragraphSpacing: s.paragraphSpacing,
      enableRedLine: s.enableRedLine,
      firstLineIndent: s.firstLineIndent,
      maxWidth: s.containerWidthFactor,
      containerAlignment: s.containerAlign,
    ));

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

  bool _isAfter(_PageAnchor a, _PageAnchor b) {
    return (a.blockIndex > b.blockIndex) ||
        (a.blockIndex == b.blockIndex && a.charOffset > b.charOffset);
  }

  _PageAnchor? _forceAdvanceAfter(_PageAnchor? candidate, _PageAnchor current) {
    if (candidate == null) return null;
    if (_isAfter(candidate, current)) return candidate;

    final blLen = inlineTextTotalLength(_blocks[current.blockIndex].inlines);
    if (current.charOffset < blLen) {
      return _PageAnchor(blockIndex: current.blockIndex, charOffset: current.charOffset + 1);
    }
    if (current.blockIndex + 1 < _blocks.length) {
      return _PageAnchor(blockIndex: current.blockIndex + 1, charOffset: 0);
    }
    return null;
  }

  Future<void> _buildAndCachePage(
      BuildContext context,
      int pageIndex, {
        bool computeNextAnchorOnly = false,
      }) async {
    if (pageIndex < 0 || pageIndex >= _anchors.length) return;

    final mq = MediaQuery.of(context);
    final safeWidth  = mq.size.width  - mq.padding.left - mq.padding.right;
    final safeHeight = mq.size.height - mq.padding.top  - mq.padding.bottom;

    final usableWidth  = safeWidth  - _pagePadding.horizontal;
    final usableHeight = safeHeight - _pagePadding.vertical;

    final start = _anchors[pageIndex];

    final paragraphs = <ParagraphBlock>[];
    final metas      = <_ParaMeta>[];

    int bi       = start.blockIndex;
    int skipHere = start.charOffset;

    CustomTextLayout? layout;
    List<LineLayout>  visibleLines = [];
    double usedHeight = 0;

    int prevVisibleCount = -1;       // ← контроль прогресса
    int stagnantIters    = 0;        // ← защита от зависаний
    const int kMaxStagnantIters = 2; // допустим 2 итерации без роста

    while (bi < _blocks.length) {
      await _pushBlockSliceAsParagraphWithMeta(
        context: context,
        blockIndex: bi,
        block: _blocks[bi],
        skipCharsFromStart: skipHere,
        paragraphs: paragraphs,
        metas: metas,
      );
      bi++;
      skipHere = 0;

      final engine = AdvancedLayoutEngine(
        allowSoftHyphens: true,
        paragraphs: paragraphs,
        globalMaxWidth: usableWidth,
        globalTextAlign: TextAlign.justify,
      );
      layout = engine.layoutAllParagraphs();

      visibleLines = [];
      usedHeight   = 0;
      for (final line in layout.lines) {
        final h = line.height;
        if (usedHeight + h > usableHeight && visibleLines.isNotEmpty) break;
        visibleLines.add(line);
        usedHeight += h;
      }

      // — Стоп-кран зависаний —
      if (visibleLines.length == prevVisibleCount) {
        stagnantIters++;
        if (stagnantIters >= kMaxStagnantIters) {
          break; // выходим из набора, иначе можем крутиться бесконечно
        }
      } else {
        stagnantIters = 0;
        prevVisibleCount = visibleLines.length;
      }

      if (usedHeight >= usableHeight || bi >= _blocks.length) break;
    }

    if (layout == null) return;

    // --- следующий якорь ---
    _PageAnchor? nextAnchor;

    if (visibleLines.isEmpty) {
      final lastBlock = metas.isNotEmpty ? metas.last.blockIndex : start.blockIndex;
      final nb = lastBlock + 1;
      nextAnchor = (nb < _blocks.length) ? _PageAnchor(blockIndex: nb, charOffset: 0) : null;
    } else {
      final pidx = layout.paragraphIndexOfLine;
      final lastVisibleLineIndex = visibleLines.length - 1;
      final lastParaIndex        = pidx[lastVisibleLineIndex];

      final totalLinesPerPara = <int,int>{};
      for (final idx in pidx) {
        totalLinesPerPara[idx] = (totalLinesPerPara[idx] ?? 0) + 1;
      }
      final visibleLinesPerPara = <int,int>{};
      for (int i = 0; i <= lastVisibleLineIndex; i++) {
        final pid = pidx[i];
        visibleLinesPerPara[pid] = (visibleLinesPerPara[pid] ?? 0) + 1;
      }

      final totalInLast   = totalLinesPerPara[lastParaIndex] ?? 0;
      final visibleInLast = visibleLinesPerPara[lastParaIndex] ?? 0;
      final bool hasInvisibleParas = lastParaIndex < (paragraphs.length - 1);

      final bool lastParaIsImage = paragraphs[lastParaIndex]
          .inlineElements
          .any((e) => e is ImageInlineElement);

      if (lastParaIsImage) {
        final meta = metas[lastParaIndex];
        final nb = meta.blockIndex + 1;
        nextAnchor = (nb < _blocks.length)
            ? _PageAnchor(blockIndex: nb, charOffset: 0)
            : null;
      } else if (visibleInLast < totalInLast) {
        int charsInLastParaVisible = _countParaCharsInLinesRange(
          lines: visibleLines,
          pidx: pidx,
          paraIndex: lastParaIndex,
          startLine: 0,
          endLineInclusive: lastVisibleLineIndex,
        );

        final endsWithHyphen = _lineEndsWithDrawnHyphen(visibleLines[lastVisibleLineIndex]);
        if (endsWithHyphen && charsInLastParaVisible > 0) {
          charsInLastParaVisible -= 1;
        }

        final paraText = _concatParagraphText(paragraphs[lastParaIndex]);
        bool breaksInsideWord = false;
        if (charsInLastParaVisible > 0 && charsInLastParaVisible < paraText.length) {
          final prevCU = paraText.codeUnitAt(charsInLastParaVisible - 1);
          final nextCU = paraText.codeUnitAt(charsInLastParaVisible);
          breaksInsideWord = _isWordCU(prevCU) && _isWordCU(nextCU);
        }

        if ((breaksInsideWord || endsWithHyphen) && visibleLines.length > 1) {
          final charsBeforeLastLine = _countParaCharsInLinesRange(
            lines: visibleLines,
            pidx: pidx,
            paraIndex: lastParaIndex,
            startLine: 0,
            endLineInclusive: lastVisibleLineIndex - 1,
          );
          final meta = metas[lastParaIndex];
          nextAnchor = _PageAnchor(
            blockIndex: meta.blockIndex,
            charOffset: meta.startOffsetInBlock + charsBeforeLastLine,
          );

          usedHeight -= visibleLines[lastVisibleLineIndex].height;
          visibleLines = visibleLines.sublist(0, lastVisibleLineIndex);
        } else {
          final meta = metas[lastParaIndex];
          nextAnchor = _PageAnchor(
            blockIndex: meta.blockIndex,
            charOffset: meta.startOffsetInBlock + charsInLastParaVisible,
          );
        }
      } else if (hasInvisibleParas) {
        final nextParaMeta = metas[lastParaIndex + 1];
        nextAnchor = _PageAnchor(
          blockIndex: nextParaMeta.blockIndex,
          charOffset: nextParaMeta.startOffsetInBlock,
        );
      } else {
        final meta = metas[lastParaIndex];
        final nextBlock = meta.blockIndex + 1;
        nextAnchor = (nextBlock < _blocks.length)
            ? _PageAnchor(blockIndex: nextBlock, charOffset: 0)
            : null;
      }
    }

    // строгое продвижение якоря (убирает дубли)
    nextAnchor = _forceAdvanceAfter(nextAnchor, start);

    // computeNextAnchorOnly → только расширяем anchors, не кэшируем страницу
    if (computeNextAnchorOnly) {
      if (nextAnchor != null) {
        final last = _anchors.last;
        final toAdd = _forceAdvanceAfter(nextAnchor, last);
        if (toAdd != null && _isAfter(toAdd, last)) {
          _anchors.add(toAdd);
          totalPages.value = _anchors.length;
        }
      }
      return;
    }

    // пустые страницы не кэшируем
    if (visibleLines.isEmpty) {
      if (nextAnchor != null && _anchors.length == pageIndex + 1) {
        final last = _anchors.last;
        final toAdd = _forceAdvanceAfter(nextAnchor, last);
        if (toAdd != null && _isAfter(toAdd, last)) {
          _anchors.add(toAdd);
          totalPages.value = _anchors.length;
        }
      }
      return;
    }

    final pageLayout = CustomTextLayout(
      lines: visibleLines,
      totalHeight: usedHeight,
      paragraphIndexOfLine: layout.paragraphIndexOfLine.take(visibleLines.length).toList(),
    );
    _pageCache[pageIndex] = pageLayout;

    if (nextAnchor != null && _anchors.length == pageIndex + 1) {
      final last = _anchors.last;
      final toAdd = _forceAdvanceAfter(nextAnchor, last);
      if (toAdd != null && _isAfter(toAdd, last)) {
        _anchors.add(toAdd);
        totalPages.value = _anchors.length;
      }
    }
  }

  /* helpers */

  final RegExp _wordCharRe = RegExp(r'[A-Za-zА-Яа-яЁё0-9]');
  bool _isWordCU(int cu) => _wordCharRe.hasMatch(String.fromCharCode(cu));

  String _concatParagraphText(ParagraphBlock p) {
    final sb = StringBuffer();
    for (final e in p.inlineElements) {
      if (e is TextInlineElement) sb.write(e.text);
    }
    return sb.toString();
  }
}

class _ParaMeta {
  final int blockIndex;
  final int startOffsetInBlock;
  final int textLen;
  const _ParaMeta(this.blockIndex, this.startOffsetInBlock, this.textLen);
}

class _PageAnchor {
  final int blockIndex;
  final int charOffset;
  const _PageAnchor({required this.blockIndex, required this.charOffset});
}
