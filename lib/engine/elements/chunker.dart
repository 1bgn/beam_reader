import 'package:flutter/material.dart';

import '../elements/data_blocks/block_text.dart';
import '../elements/data_blocks/inline_text.dart' as m;
import '../elements/data_blocks/text_run.dart' as tr;

/// Результат пагинации: страница охватывает блоки [startBlock, endBlock) включительно-исключительно
class PageSlice {
  final int startBlock;
  final int endBlock;
  const PageSlice(this.startBlock, this.endBlock);
}

/// Чанк ≈ N страниц: страницы [pageStart, pageEnd), а по блокам это [blockStart, blockEnd)
class PageChunk {
  final int pageStart;
  final int pageEnd;
  final int blockStart;
  final int blockEnd;

  const PageChunk({
    required this.pageStart,
    required this.pageEnd,
    required this.blockStart,
    required this.blockEnd,
  });

  int get pagesCount => pageEnd - pageStart;
}

/// Главная функция: разбить на чанки ~ по [targetPagesPerChunk] страниц.
List<PageChunk> chunkBlocksByPages({
  required BuildContext context,
  required List<BlockText> blocks,
  required double viewportWidth,
  required double viewportHeight,
  int targetPagesPerChunk = 20,

  // Настройки типографики/отступов — должны совпадать с рендером
  EdgeInsets pagePadding = const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
  double baseFontSize = 18,
  double lineHeight = 1.6,
  double paragraphSpacing = 10,
  Color? linkColor,
}) {
  assert(targetPagesPerChunk > 0);

  // 1) измеряем блоки
  final usableWidth = viewportWidth - pagePadding.horizontal;
  final usableHeight = viewportHeight - pagePadding.vertical;
  if (usableWidth <= 0 || usableHeight <= 0 || blocks.isEmpty) return const [];

  final measured = _measureBlocks(
    context: context,
    blocks: blocks,
    maxWidth: usableWidth,
    baseFontSize: baseFontSize,
    lineHeight: lineHeight,
    paraBaseSpacing: paragraphSpacing,
    linkColor: linkColor ?? Theme.of(context).colorScheme.primary,
  );

  // 2) собираем страницы
  final pages = _paginateMeasured(measured, usableHeight);

  if (pages.isEmpty) return const [];

  // 3) группируем страницы в чанки ≈ по N
  final chunks = <PageChunk>[];
  int pageStart = 0;
  int blockStart = pages.first.startBlock;

  for (int i = 0; i < pages.length; i++) {
    final isChunkFull = (i - pageStart + 1) >= targetPagesPerChunk;
    final isLastPage = i == pages.length - 1;

    if (isChunkFull || isLastPage) {
      final pageEnd = isLastPage ? (i + 1) : (i + 1);
      final blockEnd = pages[i].endBlock;

      chunks.add(PageChunk(
        pageStart: pageStart,
        pageEnd: pageEnd,
        blockStart: blockStart,
        blockEnd: blockEnd,
      ));

      // следующий чанк
      pageStart = i + 1;
      if (!isLastPage) {
        blockStart = pages[i].endBlock;
      }
    }
  }

  return chunks;
}

/* ============================ измерение/пагинация ============================ */

class _MeasuredBlock {
  final BlockText block;
  final TextSpan span;
  final TextAlign align;
  final double indentLeft;
  final double spaceBefore;
  final double spaceAfter;
  final double height;

  _MeasuredBlock({
    required this.block,
    required this.span,
    required this.align,
    required this.indentLeft,
    required this.spaceBefore,
    required this.spaceAfter,
    required this.height,
  });
}

List<_MeasuredBlock> _measureBlocks({
  required BuildContext context,
  required List<BlockText> blocks,
  required double maxWidth,
  required double baseFontSize,
  required double lineHeight,
  required double paraBaseSpacing,
  required Color linkColor,
}) {
  final out = <_MeasuredBlock>[];
  final direction = Directionality.of(context);

  for (final b in blocks) {
    final s = _styleForBlockTag(
      context: context,
      tag: b.tag,
      baseFontSize: baseFontSize,
      lineHeight: lineHeight,
      paraBaseSpacing: paraBaseSpacing,
      sectionDepth: b.depth,
    );

    if (b.tag == 'empty-line') {
      final h = baseFontSize * lineHeight * 0.7;
      out.add(_MeasuredBlock(
        block: b,
        span: const TextSpan(text: ''),
        align: TextAlign.start,
        indentLeft: 0,
        spaceBefore: s.spaceBefore,
        spaceAfter: s.spaceAfter,
        height: h,
      ));
      continue;
    }

    final textSpan = TextSpan(
      style: s.textStyle,
      children: b.inlines
          .map((node) => _inlineToTextSpan(
        node,
        s.textStyle,
        linkColor,
        baseFontSize,
        lineHeight,
      ))
          .toList(),
    );

    final painter = TextPainter(
      text: textSpan,
      textDirection: direction,
      textAlign: s.textAlign,
      maxLines: null,
    )..layout(maxWidth: maxWidth - s.indentLeft);

    out.add(_MeasuredBlock(
      block: b,
      span: textSpan,
      align: s.textAlign,
      indentLeft: s.indentLeft,
      spaceBefore: s.spaceBefore,
      spaceAfter: s.spaceAfter,
      height: painter.height,
    ));
  }

  return out;
}

List<PageSlice> _paginateMeasured(List<_MeasuredBlock> items, double maxHeight) {
  final pages = <PageSlice>[];
  double cursor = 0;
  int pageStartBlock = 0;

  for (int i = 0; i < items.length; i++) {
    final it = items[i];
    final blockTotal =
        (pages.isEmpty && i == 0 ? 0 : it.spaceBefore) + it.height + it.spaceAfter;

    if (cursor + blockTotal > maxHeight && i > pageStartBlock) {
      // закрываем страницу до предыдущего блока
      pages.add(PageSlice(pageStartBlock, i));
      pageStartBlock = i;
      cursor = 0;
    }

    cursor += blockTotal;
  }

  if (pageStartBlock < items.length) {
    pages.add(PageSlice(pageStartBlock, items.length));
  }

  return pages;
}

/* ============================ стили и инлайны ============================ */

class _BlockStyle {
  final TextStyle textStyle;
  final TextAlign textAlign;
  final double indentLeft;
  final double spaceBefore;
  final double spaceAfter;

  _BlockStyle({
    required this.textStyle,
    required this.textAlign,
    required this.indentLeft,
    required this.spaceBefore,
    required this.spaceAfter,
  });
}

_BlockStyle _styleForBlockTag({
  required BuildContext context,
  required String tag,
  required double baseFontSize,
  required double lineHeight,
  required double paraBaseSpacing,
  int sectionDepth = 0,
}) {
  final base = DefaultTextStyle.of(context).style.copyWith(
    fontSize: baseFontSize,
    height: lineHeight,
  );

  switch (tag) {
    case 'title':
      final d = sectionDepth.clamp(0, 3);
      final factor = 1.35 - d * 0.10; // 1.35, 1.25, 1.15, 1.05
      return _BlockStyle(
        textStyle: base.copyWith(
          fontSize: baseFontSize * factor,
          fontWeight: FontWeight.w700,
          height: lineHeight * 0.95,
        ),
        textAlign: TextAlign.start,
        indentLeft: 0,
        spaceBefore: paraBaseSpacing * 1.2,
        spaceAfter: paraBaseSpacing * 0.9,
      );
    case 'subtitle':
      return _BlockStyle(
        textStyle: base.copyWith(
          fontSize: baseFontSize * 1.15,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.start,
        indentLeft: 0,
        spaceBefore: paraBaseSpacing * 0.8,
        spaceAfter: paraBaseSpacing * 0.8,
      );
    case 'text-author':
      return _BlockStyle(
        textStyle: base.copyWith(fontStyle: FontStyle.italic),
        textAlign: TextAlign.right,
        indentLeft: 0,
        spaceBefore: paraBaseSpacing * 0.5,
        spaceAfter: paraBaseSpacing * 0.7,
      );
    case 'v':
      return _BlockStyle(
        textStyle: base,
        textAlign: TextAlign.start,
        indentLeft: 16,
        spaceBefore: paraBaseSpacing * 0.3,
        spaceAfter: 0,
      );
    case 'epigraph':
    case 'cite':
      return _BlockStyle(
        textStyle: base.copyWith(fontStyle: FontStyle.italic),
        textAlign: TextAlign.start,
        indentLeft: 12,
        spaceBefore: paraBaseSpacing,
        spaceAfter: paraBaseSpacing * 0.6,
      );
    case 'empty-line':
      return _BlockStyle(
        textStyle: base,
        textAlign: TextAlign.start,
        indentLeft: 0,
        spaceBefore: 0,
        spaceAfter: 0,
      );
    case 'image':
      return _BlockStyle(
        textStyle: base,
        textAlign: TextAlign.center,
        indentLeft: 0,
        spaceBefore: paraBaseSpacing,
        spaceAfter: paraBaseSpacing,
      );
    case 'p':
    default:
      return _BlockStyle(
        textStyle: base,
        textAlign: TextAlign.start,
        indentLeft: 0,
        spaceBefore: paraBaseSpacing * 0.6,
        spaceAfter: 0,
      );
  }
}

/// Конвертер твоих inline-узлов → Flutter TextSpan.
/// Обрати внимание на алиасы: модели импортированы как `m.*`, а TextRun — как `tr.*`.
TextSpan _inlineToTextSpan(
    m.InlineText node,
    TextStyle base,
    Color linkColor,
    double baseFontSize,
    double lineHeight,
    ) {
  if (node is tr.TextRun) {
    return TextSpan(text: node.text, style: base);
  }

  if (node is m.InlineSpan) {
    final m.InlineSpan spanNode = node;

    TextStyle s = base;
    switch (spanNode.tag) {
      case 'strong':
        s = s.copyWith(fontWeight: FontWeight.w700);
        break;
      case 'emphasis':
        s = s.copyWith(fontStyle: FontStyle.italic);
        break;
      case 'a':
        s = s.copyWith(
          decoration: TextDecoration.underline,
          color: linkColor,
        );
        break;
      case 'code':
        s = s.copyWith(fontFamily: 'monospace', backgroundColor: Colors.black12);
        break;
      case 'strikethrough':
        s = s.copyWith(decoration: TextDecoration.lineThrough);
        break;
      case 'sub':
      case 'sup':
        s = s.copyWith(
          fontSize: (base.fontSize ?? baseFontSize) * 0.8,
          height: lineHeight * 0.9,
        );
        break;
    // 'style', 'date' и др. — без доп. модификаций
    }

    return TextSpan(
      style: s,
      children: spanNode.children
          .map((c) => _inlineToTextSpan(c, s, linkColor, baseFontSize, lineHeight))
          .toList(),
    );
  }

  return const TextSpan(text: '');
}
