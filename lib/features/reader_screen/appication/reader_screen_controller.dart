// lib/features/reader_screen/appication/reader_pager_controller.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xml/xml.dart';

import '../../../engine/elements/data_blocks/block_text.dart';
import '../../../engine/elements/data_blocks/inline_text.dart';
import '../../../engine/elements/layout_blocks/line_layout.dart';
import '../../../engine/elements/text_utils.dart'; // см. утилиты ниже
import 'package:beam_reader/engine/advanced_layout_engine.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/paragraph_block.dart';
import 'package:beam_reader/engine/elements/layout_blocks/text_inline_element.dart';
import 'package:beam_reader/engine/elements/layout_blocks/image_inline_element.dart';
import 'package:beam_reader/engine/elements/fb2_style_map.dart';
import 'package:beam_reader/engine/fb2_transform.dart';
import 'package:beam_reader/engine/xml_loader.dart';
class _ParaMeta {
  final int blockIndex;        // глобальный индекс блока в _blocks
  final int startOffsetInBlock;// сколько символов в блоке пропущено (для первой страницы блока)
  final int textLen;           // сколько текстовых символов в этом параграфе (после среза)
  _ParaMeta(this.blockIndex, this.startOffsetInBlock, this.textLen);
}
@LazySingleton()
class ReaderPagerController {
  final XmlLoader xmlLoader;

  final totalPages = signal<int>(0);

  late List<BlockText> _blocks;
  late Map<String, Uint8List> _binaries;
  final Map<String, ui.Image> _imgCache = {};
  final Map<int, CustomTextLayout> _pageCache = {};

  // Якорь страницы i -> (index блока, смещение в символах внутри блока)
  final List<_PageAnchor> _anchors = []; // anchors[i] = старт страницы i
  bool _inited = false;

  // типографика (должна совпадать с рендером)
  static const _baseFontSize = 16.0;
  static const _lineHeight   = 1.6;
  static const _pagePadding  = EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  ReaderPagerController(this.xmlLoader);

  Future<void> init(BuildContext context) async {
    if (_inited) return;
    _inited = true;

    final xml = XmlDocument.parse(await xmlLoader.loadBook());
    final transformer = Fb2Transformer();
    _blocks   = transformer.parseToBlocks(xml.rootElement);
    _binaries = extractBinaryMap(xml);

    // Первая страница — от начала книги
    _anchors.add(_PageAnchor(blockIndex: 0, charOffset: 0));
    totalPages.value = 1;

    // Префетч первых двух
    await Future.wait([ensurePage(context, 0), ensurePage(context, 1)]);
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
  final Map<int, Future<void>> _inflight = {};
  Future<void> ensurePage(BuildContext context, int pageIndex) async {
    if (pageIndex < 0) return;

    // уже строим эту страницу? — подождём тот же future
    final infl = _inflight[pageIndex];
    if (infl != null) {
      await infl;
      return;
    }

    // 1) гарантируем якоря до нужного индекса
    while (pageIndex >= _anchors.length) {
      final before = _anchors.length;
      // якорь считаем относительно последней имеющейся страницы
      final fut = _buildAndCachePage(context, _anchors.length - 1, computeNextAnchorOnly: true);
      _inflight[_anchors.length - 1] = fut;
      await fut.whenComplete(() => _inflight.remove(_anchors.length - 1));

      // если якорь не добавился — выходим, чтобы не крутиться бесконечно
      if (_anchors.length == before) break;
    }

    // 2) если страница уже есть — ок
    if (_pageCache.containsKey(pageIndex)) return;

    // 3) собираем страницу (один inflight на индекс)
    final fut2 = _buildAndCachePage(context, pageIndex);
    _inflight[pageIndex] = fut2;
    await fut2.whenComplete(() => _inflight.remove(pageIndex));
  }
  CustomTextLayout? getPage(int index) => _pageCache[index];

  Future<void> prefetchAround(BuildContext ctx, int index, {int radius = 2}) async {
    for (int i = index - radius; i <= index + radius; i++) {
      if (i >= 0) { await ensurePage(ctx, i); }
    }
  }
  Future<void> _pushBlockSliceAsParagraphWithMeta({
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
      metas.add(_ParaMeta(_blocks.indexOf(block), 0, 0));
      return;
    }

    if (block.tag == 'image') {
      final img = await _resolveImageForAttrs(block.attrs);
      if (img != null) {
        paragraphs.add(ParagraphBlock(
          inlineElements: [ImageInlineElement(image: img, radius: BorderRadius.circular(8))],
          textAlign: s.textAlign,
          paragraphSpacing: s.paragraphSpacing,
          enableRedLine: false,
          firstLineIndent: 0,
          maxWidth: s.containerWidthFactor,
          containerAlignment: s.containerAlign,
        ));
      }
      metas.add(_ParaMeta(_blocks.indexOf(block), 0, 0)); // «текстовая длина» = 0
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
    metas.add(_ParaMeta(_blocks.indexOf(block), skipCharsFromStart, textLenAfterSlice));
  }
  Future<void> _buildAndCachePage(
      BuildContext context,
      int pageIndex, {
        bool computeNextAnchorOnly = false,
      }) async {
    if (pageIndex < 0 || pageIndex >= _anchors.length) return;

    final size         = MediaQuery.of(context).size;
    final usableWidth  = size.width  - _pagePadding.horizontal;
    final usableHeight = size.height - _pagePadding.vertical;

    // стартовый якорь
    final start = _anchors[pageIndex];

    // собираем параграфы постепенно, пока страница не заполнится
    final paragraphs = <ParagraphBlock>[];
    final metas      = <_ParaMeta>[];

    int bi       = start.blockIndex;
    int skipHere = start.charOffset;

    // минимум один параграф всегда добавим, затем — увеличиваем до заполнения
    CustomTextLayout? layout;
    List<LineLayout>   visibleLines = [];
    double usedHeight = 0;
    int prevVisibleCount = 0;

    while (bi < _blocks.length) {
      await _pushBlockSliceAsParagraphWithMeta(
        block: _blocks[bi],
        skipCharsFromStart: skipHere,
        paragraphs: paragraphs,
        metas: metas,
      );
      bi++;
      skipHere = 0;

      // пересчёт
      final engine = AdvancedLayoutEngine(
        allowSoftHyphens: true,
        paragraphs: paragraphs,
        globalMaxWidth: usableWidth,
        globalTextAlign: TextAlign.justify,
      );
      layout = engine.layoutAllParagraphs();

      // сколько строк влезает по высоте
      visibleLines = [];
      usedHeight   = 0;
      for (final line in layout.lines) {
        final h = line.height;
        // если первая строка одна и она выше страницы — всё равно берём её
        if (usedHeight + h > usableHeight && visibleLines.isNotEmpty) break;
        visibleLines.add(line);
        usedHeight += h;
      }

      // *** СТРАХОВКА ОТ «БЕЗДВИЖЕНИЯ» ***
      if (visibleLines.length == prevVisibleCount) {
        // не стало больше видимых строк после добавления нового параграфа — заканчиваем набор
        break;
      }
      prevVisibleCount = visibleLines.length;

      if (usedHeight >= usableHeight || bi >= _blocks.length) break;
    }

    // если по какой-то причине layout ещё не собран (книга пуста) — выходим
    if (layout == null) return;

    // --- считаем якорь следующей страницы ---
    _PageAnchor? nextAnchor;

    if (visibleLines.isEmpty) {
      // редкий случай: первая же строка выше страницы (очень большая картинка/кегль)
      // тогда просто двигаем на следующий блок
      final lastBlock = metas.isNotEmpty ? metas.last.blockIndex : start.blockIndex;
      final nb = lastBlock + 1;
      nextAnchor = (nb < _blocks.length)
          ? _PageAnchor(blockIndex: nb, charOffset: 0)
          : null;
    } else {
      // индексы параграфов по строкам
      final pidx = layout.paragraphIndexOfLine;
      final lastVisibleLineIndex = visibleLines.length - 1;
      final lastParaIndex        = pidx[lastVisibleLineIndex];

      // посчитаем сколько строк всего у каждого параграфа
      final totalLinesPerPara = <int,int>{};
      for (final idx in pidx) {
        totalLinesPerPara[idx] = (totalLinesPerPara[idx] ?? 0) + 1;
      }

      // и сколько строк видимо у каждого параграфа
      final visibleLinesPerPara = <int,int>{};
      for (int i = 0; i <= lastVisibleLineIndex; i++) {
        final pid = pidx[i];
        visibleLinesPerPara[pid] = (visibleLinesPerPara[pid] ?? 0) + 1;
      }

      final totalInLast   = totalLinesPerPara[lastParaIndex] ?? 0;
      final visibleInLast = visibleLinesPerPara[lastParaIndex] ?? 0;

      if (visibleInLast < totalInLast) {
        // последняя видимая строка — внутри параграфа (разрываем абзац)
        // считаем, сколько символов текста в видимой ЧАСТИ ЭТОГО параграфа
        int charsInLastParaVisible = 0;
        for (int i = 0; i <= lastVisibleLineIndex; i++) {
          if (pidx[i] != lastParaIndex) continue;
          for (final e in visibleLines[i].elements) {
            if (e is TextInlineElement) {
              charsInLastParaVisible += e.text.length;
            }
          }
        }
        final meta = metas[lastParaIndex];
        nextAnchor = _PageAnchor(
          blockIndex: meta.blockIndex,
          charOffset: meta.startOffsetInBlock + charsInLastParaVisible,
        );
      } else {
        // последний параграф виден целиком — двигаем на следующий блок
        final meta = metas[lastParaIndex];
        final nextBlock = meta.blockIndex + 1;
        nextAnchor = (nextBlock < _blocks.length)
            ? _PageAnchor(blockIndex: nextBlock, charOffset: 0)
            : null;
      }
    }

    // если нужна была только прогонка якоря — обновим anchors и выходим
    if (computeNextAnchorOnly) {
      if (nextAnchor != null) {
        _anchors.add(nextAnchor);
        totalPages.value = _anchors.length;
      }
      return;
    }

    // кешируем готовую страницу (только видимые строки)
    final pageLayout = CustomTextLayout(
      lines: visibleLines,
      totalHeight: usedHeight,
      paragraphIndexOfLine: layout.paragraphIndexOfLine.take(visibleLines.length).toList(),
    );
    _pageCache[pageIndex] = pageLayout;

    // добавляем якорь следующей страницы, если его ещё нет
    if (nextAnchor != null && _anchors.length == pageIndex + 1) {
      _anchors.add(nextAnchor);
      totalPages.value = _anchors.length;
    }
  }

  // Добавляет в paragraphs срез блока с пропуском первых skipChars символов
  Future<void> _pushBlockSliceAsParagraph({
    required BlockText block,
    required int skipCharsFromStart,
    required List<ParagraphBlock> paragraphs,
    required List<int> perBlockTextLen,
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
      perBlockTextLen.add(0);
      return;
    }

    if (block.tag == 'image') {
      final img = await _resolveImageForAttrs(block.attrs);
      if (img != null) {
        paragraphs.add(ParagraphBlock(
          inlineElements: [ImageInlineElement(image: img, radius: BorderRadius.circular(8))],
          textAlign: s.textAlign,
          paragraphSpacing: s.paragraphSpacing,
          enableRedLine: false,
          firstLineIndent: 0,
          maxWidth: s.containerWidthFactor,
          containerAlignment: s.containerAlign,
        ));
      }
      perBlockTextLen.add(0);
      return;
    }

    // считаем длину текста блока (по InlineText-модели)
    final totalLen = inlineTextTotalLength(block.inlines);
    perBlockTextLen.add(totalLen);

    // строим InlineElements и срезаем первые skipCharsFromStart символов
    final full = buildInlineElements(block.inlines, s.textStyle);
    final sliced = sliceInlineElementsFromStart(full, skipCharsFromStart);

    paragraphs.add(ParagraphBlock(
      inlineElements: sliced,
      textAlign: s.textAlign,
      paragraphSpacing: s.paragraphSpacing,
      enableRedLine: s.enableRedLine,
      firstLineIndent: s.firstLineIndent,
      maxWidth: s.containerWidthFactor,
      containerAlignment: s.containerAlign,
    ));
  }

  // Считает количество текстовых символов в наборе строк
  int _countCharsInLines(List<LineLayout> lines) {
    int total = 0;
    for (final line in lines) {
      for (final e in line.elements) {
        if (e is TextInlineElement) total += e.text.length;
      }
    }
    return total;
  }

  // Продвигает якорь на consumedChars через блоки
  _PageAnchor? _advanceAnchor(_PageAnchor start, int consumedChars, List<BlockText> blocks) {
    int idx = start.blockIndex;
    int offset = start.charOffset;
    int left = consumedChars;

    while (idx < blocks.length) {
      final blLen = inlineTextTotalLength(blocks[idx].inlines);
      final avail = (idx == start.blockIndex) ? (blLen - offset) : blLen;

      if (left < avail) {
        final nextOffset = ((idx == start.blockIndex) ? offset : 0) + left;
        return _PageAnchor(blockIndex: idx, charOffset: nextOffset);
      } else {
        left -= avail;
        idx++;
        offset = 0;
      }
    }
    // дошли до конца книги → страниц больше нет
    return null;
  }
}

class _PageAnchor {
  final int blockIndex;
  final int charOffset;
  const _PageAnchor({required this.blockIndex, required this.charOffset});
}
