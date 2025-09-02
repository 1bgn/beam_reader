// lib/features/reader_screen/appication/reader_pager_controller.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:beam_reader/engine/advanced_layout_engine.dart';
import 'package:beam_reader/engine/elements/fb2_style_map.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/image_inline_element.dart';
import 'package:beam_reader/engine/elements/layout_blocks/paragraph_block.dart';
import 'package:beam_reader/engine/elements/layout_blocks/text_inline_element.dart';
import 'package:beam_reader/engine/elements/layout_blocks/line_layout.dart';
import 'package:beam_reader/engine/elements/text_utils.dart';
import 'package:beam_reader/engine/fb2_transform.dart';
import 'package:beam_reader/engine/xml_loader.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xml/xml.dart';

import '../../../engine/elements/data_blocks/block_text.dart';

@LazySingleton()
class ReaderPagerController {
  final XmlLoader xmlLoader;

  /// Количество доступных страниц (растёт по мере вычисления якорей)
  final totalPages = signal<int>(0);

  // Книга (сырые блоки)
  late List<BlockText> _blocks;

  // Бинарники и кэш картинок
  late Map<String, Uint8List> _binaries;
  final Map<String, ui.Image> _imgCache = {};

  // Кэш уже собранных страниц (layout видимых строк)
  final Map<int, CustomTextLayout> _pageCache = {};

  // Якорь начала каждой страницы: anchors[i] = (blockIndex, charOffset)
  final List<_PageAnchor> _anchors = [];

  // Защита от конкурентных сборок страниц
  final Map<int, Future<void>> _inflight = {};

  bool _inited = false;

  // Типографика (должна совпадать с рендером SinglePageView/RenderObj)
  static const _baseFontSize = 16.0;
  static const _lineHeight   = 1.6;
  static const _pagePadding  = EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  ReaderPagerController(this.xmlLoader);

  /* ============================ ИНИЦИАЛИЗАЦИЯ ============================ */

  Future<void> init(BuildContext context) async {
    if (_inited) return;
    _inited = true;

    final xml = XmlDocument.parse(await xmlLoader.loadBook());

    final transformer = Fb2Transformer();
    _blocks   = transformer.parseToBlocks(xml.rootElement);
    _binaries = extractBinaryMap(xml);

    // Первая страница всегда начинается с начала книги
    _anchors.add(const _PageAnchor(blockIndex: 0, charOffset: 0));
    totalPages.value = 1;

    // Префетч первых двух страниц
    await Future.wait([ensurePage(context, 0), ensurePage(context, 1)]);
  }

  /* ============================ ПУБЛИЧНЫЕ API ============================ */

  CustomTextLayout? getPage(int index) => _pageCache[index];

  Future<void> ensurePage(BuildContext context, int pageIndex) async {
    if (pageIndex < 0) return;

    // Если уже идёт сборка этой страницы — ждём её
    final infl = _inflight[pageIndex];
    if (infl != null) {
      await infl;
      return;
    }

    // Гарантируем наличие якоря для запрошенного индекса
    while (pageIndex >= _anchors.length) {
      final lastIdx = _anchors.length - 1;
      final before  = _anchors.length;

      final fut = _buildAndCachePage(context, lastIdx, computeNextAnchorOnly: true);
      _inflight[lastIdx] = fut;
      await fut.whenComplete(() => _inflight.remove(lastIdx));

      // если якорь не сдвинулся — прекращаем, чтобы не зациклиться
      if (_anchors.length == before) break;
    }

    // Если страница уже собрана — ок
    if (_pageCache.containsKey(pageIndex)) return;

    // Собираем страницу (с защитой от параллельной сборки)
    final fut2 = _buildAndCachePage(context, pageIndex);
    _inflight[pageIndex] = fut2;
    await fut2.whenComplete(() => _inflight.remove(pageIndex));
  }

  Future<void> prefetchAround(BuildContext ctx, int index, {int radius = 2}) async {
    for (int i = index - radius; i <= index + radius; i++) {
      if (i >= 0) {
        await ensurePage(ctx, i);
      }
    }
  }

  /* ============================ НИЗКОУРОВНЕВОЕ ============================ */

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

    // 1) Пустой абзац
    if (block.tag == 'empty-line') {
      paragraphs.add(ParagraphBlock(
        inlineElements: const [],
        textAlign: TextAlign.start,
        paragraphSpacing: s.paragraphSpacing,
      ));
      metas.add(_ParaMeta(_blocks.indexOf(block), 0, 0));
      return;
    }

    // 2) Картинка
    if (block.tag == 'image') {
      final img = await _resolveImageForAttrs(block.attrs);
      if (img != null) {
        final viewport = MediaQuery.of(context).size;
        final usableHeight = viewport.height - _pagePadding.vertical;
        final maxH = usableHeight * 0.9; // ограничим, чтобы влезала на страницу

        paragraphs.add(ParagraphBlock(
          inlineElements: [
            ImageInlineElement(
              image: img,
              maxHeight: maxH,                    // << ключ, чтобы длинные изображения не «пропадали»
              radius: BorderRadius.circular(8),
            ),
          ],
          textAlign: s.textAlign,
          paragraphSpacing: s.paragraphSpacing,
          enableRedLine: false,
          firstLineIndent: 0,
          maxWidth: s.containerWidthFactor ?? 0.92, // чуть уже визуальный контейнер
          containerAlignment: s.containerAlign ?? TextAlign.center,
        ));
      }
      metas.add(_ParaMeta(_blocks.indexOf(block), 0, 0)); // текстовой длины нет
      return;
    }

    // 3) Обычный текст: строим инлайны и срезаем первые skipCharsFromStart
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
  bool _lineEndsWithDrawnHyphen(LineLayout line) {
    for (int i = line.elements.length - 1; i >= 0; i--) {
      final e = line.elements[i];
      if (e is TextInlineElement && e.text.isNotEmpty) {
        return e.text.codeUnitAt(e.text.length - 1) == 0x2D; // '-'
      }
    }
    return false;
  }

// Считает количество «оригинальных» символов абзаца в диапазоне видимых строк.
// Вычитает хвостовой '-' у каждой строки диапазона и все soft hyphen (U+00AD).
  int _countParaCharsInLinesRange({
    required List<LineLayout> lines,
    required List<int> pidx,       // layout.paragraphIndexOfLine
    required int paraIndex,        // индекс абзаца в layout.paragraphs
    required int startLine,        // включительно
    required int endLineInclusive, // включительно
  }) {
    int total = 0;
    for (int li = startLine; li <= endLineInclusive; li++) {
      if (pidx[li] != paraIndex) continue;

      // суммируем символы этой строки
      int lineChars = 0;
      for (final el in lines[li].elements) {
        if (el is TextInlineElement) {
          // убираем мягкие переносы, если есть
          lineChars += el.text.replaceAll('\u00AD', '').length;
        }
      }

      // если строка заканчивается рисованным дефисом, он не «оригинальный»
      if (_lineEndsWithDrawnHyphen(lines[li]) && lineChars > 0) {
        lineChars -= 1;
      }
      if (lineChars > 0) total += lineChars;
    }
    return total;
  }
  /// Построить страницу с указанного `pageIndex`.
  /// Если `computeNextAnchorOnly == true` — считаем только якорь следующей страницы.
// ---- полностью переписанный метод: замени свою версию ----

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

    CustomTextLayout? layout;
    List<LineLayout>  visibleLines = [];
    double usedHeight = 0;
    int prevVisibleCount = 0;

    while (bi < _blocks.length) {
      await _pushBlockSliceAsParagraphWithMeta(
        context: context,
        block: _blocks[bi],
        skipCharsFromStart: skipHere,
        paragraphs: paragraphs,
        metas: metas,
      );
      bi++;
      skipHere = 0;

      // пересчёт верстки
      final engine = AdvancedLayoutEngine(
        allowSoftHyphens: true,
        paragraphs: paragraphs,
        globalMaxWidth: usableWidth,
        globalTextAlign: TextAlign.justify,
      );
      layout = engine.layoutAllParagraphs();

      // считаем сколько строк помещается по высоте
      visibleLines = [];
      usedHeight   = 0;
      for (final line in layout.lines) {
        final h = line.height; // lineSpacing=0
        if (usedHeight + h > usableHeight && visibleLines.isNotEmpty) break;
        visibleLines.add(line);
        usedHeight += h;
      }

      // страховка от «застревания»: если строк не прибавилось — стоп
      if (visibleLines.length == prevVisibleCount) break;
      prevVisibleCount = visibleLines.length;

      if (usedHeight >= usableHeight || bi >= _blocks.length) break;
    }

    if (layout == null) return;

    // --------- рассчитываем якорь следующей страницы ---------
    _PageAnchor? nextAnchor;

    if (visibleLines.isEmpty) {
      // очень большой абзац (например, огромная картинка) — сдвигаем на следующий блок
      final lastBlock = metas.isNotEmpty ? metas.last.blockIndex : start.blockIndex;
      final nb = lastBlock + 1;
      nextAnchor = (nb < _blocks.length)
          ? _PageAnchor(blockIndex: nb, charOffset: 0)
          : null;
    } else {
      final pidx = layout.paragraphIndexOfLine;
      final lastVisibleLineIndex = visibleLines.length - 1;
      final lastParaIndex        = pidx[lastVisibleLineIndex];

      // считаем строки «всего» и «видимо» для каждого параграфа
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

      // Есть ли абзацы, добавленные в paragraphs, но не попавшие в visibleLines?
      final bool hasInvisibleParas = lastParaIndex < (paragraphs.length - 1);

      if (visibleInLast < totalInLast) {
        // разрез внутри последнего видимого абзаца
        int charsInLastParaVisible = _countParaCharsInLinesRange(
          lines: visibleLines,
          pidx: pidx,
          paraIndex: lastParaIndex,
          startLine: 0,
          endLineInclusive: lastVisibleLineIndex,
        );

        // проверяем «рисованный» дефис у самой последней строки (на всякий случай)
        final endsWithHyphen = _lineEndsWithDrawnHyphen(visibleLines[lastVisibleLineIndex]);
        if (endsWithHyphen && charsInLastParaVisible > 0) {
          charsInLastParaVisible -= 1;
        }

        // Проверим, что разрыв попал ВНУТРЬ слова (без дефиса)
        final paraText = _concatParagraphText(paragraphs[lastParaIndex]);
        bool breaksInsideWord = false;
        if (charsInLastParaVisible > 0 && charsInLastParaVisible < paraText.length) {
          final prevCU = paraText.codeUnitAt(charsInLastParaVisible - 1);
          final nextCU = paraText.codeUnitAt(charsInLastParaVisible);
          final prevIsWord = _isWordCU(prevCU);
          final nextIsWord = _isWordCU(nextCU);
          breaksInsideWord = prevIsWord && nextIsWord;
        }

        // Если слово разорвано (или был дефис) — переносим ЦЕЛИКОМ ПОСЛЕДНЮЮ СТРОКУ
        if ((breaksInsideWord || endsWithHyphen) && visibleLines.length > 1) {
          // Сколько символов последнего абзаца было видно ДО последней строки
          final charsBeforeLastLine = _countParaCharsInLinesRange(
            lines: visibleLines,
            pidx: pidx,
            paraIndex: lastParaIndex,
            startLine: 0,
            endLineInclusive: lastVisibleLineIndex - 1,
          );

          // Якорь следующей страницы — с начала «перенесённой» строки
          final meta = metas[lastParaIndex];
          nextAnchor = _PageAnchor(
            blockIndex: meta.blockIndex,
            charOffset: meta.startOffsetInBlock + charsBeforeLastLine,
          );

          // Текущую страницу подрезаем: убираем последнюю строку (чтобы не было дубликата)
          usedHeight -= visibleLines[lastVisibleLineIndex].height;
          visibleLines = visibleLines.sublist(0, lastVisibleLineIndex);
        } else {
          // обычный случай: разрыв после слова/на границе
          final meta = metas[lastParaIndex];
          nextAnchor = _PageAnchor(
            blockIndex: meta.blockIndex,
            charOffset: meta.startOffsetInBlock + charsInLastParaVisible,
          );
        }
      } else if (hasInvisibleParas) {
        // последний видимый абзац закончился; есть абзацы, которые не влезли вообще
        // → следующая страница с ПЕРВОГО невидимого абзаца
        final nextParaMeta = metas[lastParaIndex + 1];
        nextAnchor = _PageAnchor(
          blockIndex: nextParaMeta.blockIndex,
          charOffset: nextParaMeta.startOffsetInBlock, // обычно 0
        );
      } else {
        // абзац виден полностью и невидимых абзацев нет → следующий блок
        final meta = metas[lastParaIndex];
        final nextBlock = meta.blockIndex + 1;
        nextAnchor = (nextBlock < _blocks.length)
            ? _PageAnchor(blockIndex: nextBlock, charOffset: 0)
            : null;
      }
    }

    // Анти-дубликат якоря (на всякий случай)
    if (nextAnchor != null &&
        nextAnchor.blockIndex == start.blockIndex &&
        nextAnchor.charOffset == start.charOffset) {
      final blLen = inlineTextTotalLength(_blocks[start.blockIndex].inlines);
      if (start.charOffset < blLen) {
        nextAnchor = _PageAnchor(
          blockIndex: start.blockIndex,
          charOffset: start.charOffset + 1,
        );
      } else if (start.blockIndex + 1 < _blocks.length) {
        nextAnchor = _PageAnchor(blockIndex: start.blockIndex + 1, charOffset: 0);
      } else {
        nextAnchor = null;
      }
    }

    // если нужно было только «протащить якорь» — обновляем anchors и выходим
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


  /// Добавляет в `paragraphs` один параграф — это:
  ///  - пустой абзац,
  ///  - картинка,
  ///  - либо текстовые inline-элементы, срезанные от начала на `skipCharsFromStart`.
  Future<void> _pushBlockSliceAsParagraph({
    required BlockText block,
    required int skipCharsFromStart,
    required List<ParagraphBlock> paragraphs,
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
      return;
    }

    if (block.tag == 'image') {
      final img = await _resolveImageForAttrs(block.attrs);
      if (img != null) {
        paragraphs.add(ParagraphBlock(
          inlineElements: [
            ImageInlineElement(
              image: img,
              radius: BorderRadius.circular(8),
            ),
          ],
          textAlign: s.textAlign,
          paragraphSpacing: s.paragraphSpacing,
          enableRedLine: false,
          firstLineIndent: 0,
          maxWidth: s.containerWidthFactor,
          containerAlignment: s.containerAlign,
        ));
      }
      return;
    }

    // Обычный текстовый блок: строим инлайны и срезаем первые skipCharsFromStart
    final full   = buildInlineElements(block.inlines, s.textStyle);
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

  /// Считает число «оригинальных» символов, попавших в видимые строки.
  /// Если строка заканчивается «рисованным» переносным дефисом, он не входит в счётчик.
  int _countVisibleCharsWithHyphenFix(List<LineLayout> visible) {
    int total = 0;

    for (final line in visible) {
      final elems = line.elements;
      for (int i = 0; i < elems.length; i++) {
        final e = elems[i];
        if (e is! TextInlineElement) continue;

        var len = e.text.length;

        // Последний текстовый элемент строки и он заканчивается '-' → уберём этот «рисованный» дефис
        if (i == elems.length - 1 && e.text.endsWith('-')) {
          len = len - 1;
          if (len < 0) len = 0;
        }
        total += len;
      }
    }
    return total;
  }

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
  final int blockIndex;         // глобальный индекс блока в _blocks
  final int startOffsetInBlock; // сколько символов в блоке пропущено (для первой страницы блока)
  final int textLen;            // сколько текстовых символов в параграфе (после среза)
  const _ParaMeta(this.blockIndex, this.startOffsetInBlock, this.textLen);
}
class _PageAnchor {
  final int blockIndex;
  final int charOffset;
  const _PageAnchor({required this.blockIndex, required this.charOffset});
}
