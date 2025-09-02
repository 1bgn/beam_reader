// import 'package:flutter/material.dart';
// import '../../../engine/elements/data_blocks/block_text.dart';
// import '../../../engine/elements/data_blocks/text_run.dart' as i;
// import '../../../engine/fb2_transform.dart';
//
// /// Ридер с пагинацией по страницам. Принимает готовые BlockText из трансформера.
// class ReaderPager extends StatefulWidget {
//   final List<BlockText> blocks;
//
//   // Настройки внешнего вида
//   final EdgeInsets pagePadding;
//   final Color? linkColor;
//   final double baseFontSize;
//   final double lineHeight;
//   final double paragraphSpacing; // базовый отступ между абзацами
//   final PageController? controller;
//   final ValueChanged<int>? onPageChanged;
//
//   const ReaderPager({
//     super.key,
//     required this.blocks,
//     this.pagePadding = const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
//     this.linkColor,
//     this.baseFontSize = 18,
//     this.lineHeight = 1.6,
//     this.paragraphSpacing = 10,
//     this.controller,
//     this.onPageChanged,
//   });
//
//   @override
//   State<ReaderPager> createState() => _ReaderPagerState();
// }
//
// class _ReaderPagerState extends State<ReaderPager> {
//   List<_MeasuredBlock> _measured = [];
//   List<_PageSlice> _pages = [];
//
//   @override
//   void didChangeDependencies() {
//     super.didChangeDependencies();
//     _rebuildIfNeeded();
//   }
//
//   @override
//   void didUpdateWidget(covariant ReaderPager oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (oldWidget.blocks != widget.blocks ||
//         oldWidget.baseFontSize != widget.baseFontSize ||
//         oldWidget.lineHeight != widget.lineHeight ||
//         oldWidget.paragraphSpacing != widget.paragraphSpacing ||
//         oldWidget.pagePadding != widget.pagePadding) {
//       _rebuildIfNeeded();
//     }
//   }
//
//   void _rebuildIfNeeded() {
//     // Пересчёт произойдёт в LayoutBuilder, когда узнаем точный размер
//     setState(() {
//       _measured = [];
//       _pages = [];
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final linkColor = widget.linkColor ?? theme.colorScheme.primary;
//
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final usableWidth =
//             constraints.maxWidth - widget.pagePadding.horizontal;
//         final usableHeight =
//             constraints.maxHeight - widget.pagePadding.vertical;
//
//         if (usableWidth <= 0 || usableHeight <= 0) {
//           return const SizedBox.shrink();
//         }
//
//         // 1) Построить и измерить все блоки
//         _measured = _buildAndMeasureBlocks(
//           context: context,
//           blocks: widget.blocks,
//           maxWidth: usableWidth,
//           baseFontSize: widget.baseFontSize,
//           lineHeight: widget.lineHeight,
//           paraBaseSpacing: widget.paragraphSpacing,
//           linkColor: linkColor,
//         );
//
//         // 2) Пагинация
//         _pages = _paginate(_measured, usableHeight);
//
//         if (_pages.isEmpty) {
//           return const Center(child: Text('Пусто'));
//         }
//
//         // 3) Рендер страниц
//         return PageView.builder(
//           controller: widget.controller,
//           onPageChanged: widget.onPageChanged,
//           itemCount: _pages.length,
//           itemBuilder: (context, index) {
//             final page = _pages[index];
//             return Padding(
//               padding: widget.pagePadding,
//               child: _PageContent(
//                 blocks: _measured.sublist(page.start, page.end),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
// }
//
// /* ----------------------------- измерение/пагинация ----------------------------- */
//
// class _MeasuredBlock {
//   final BlockText block;
//   final TextSpan span;
//   final TextAlign align;
//   final double indentLeft; // отступ слева (например, для стихов)
//   final double spaceBefore;
//   final double spaceAfter;
//   final double height; // высота текста (без spaceBefore/After)
//
//   _MeasuredBlock({
//     required this.block,
//     required this.span,
//     required this.align,
//     required this.indentLeft,
//     required this.spaceBefore,
//     required this.spaceAfter,
//     required this.height,
//   });
// }
//
// class _PageSlice {
//   final int start; // включительно
//   final int end; // исключительно
//   _PageSlice(this.start, this.end);
// }
//
// List<_MeasuredBlock> _buildAndMeasureBlocks({
//   required BuildContext context,
//   required List<BlockText> blocks,
//   required double maxWidth,
//   required double baseFontSize,
//   required double lineHeight,
//   required double paraBaseSpacing,
//   required Color linkColor,
// }) {
//   final List<_MeasuredBlock> out = [];
//   final direction = Directionality.of(context);
//
//   for (final b in blocks) {
//     final s = _styleForBlockTag(
//       context: context,
//       tag: b.tag, // используем строковый тег
//       baseFontSize: baseFontSize,
//       lineHeight: lineHeight,
//       paraBaseSpacing: paraBaseSpacing,
//     );
//
//     // Особый кейс: empty-line как пустой блок с фиксированной высотой
//     if (b.tag == 'empty-line') {
//       final h = baseFontSize * lineHeight * 0.7;
//       out.add(_MeasuredBlock(
//         block: b,
//         span: const TextSpan(text: ''),
//         align: TextAlign.start,
//         indentLeft: 0,
//         spaceBefore: s.spaceBefore,
//         spaceAfter: s.spaceAfter,
//         height: h,
//       ));
//       continue;
//     }
//
//     // Построить TextSpan из inline-узлов
//     final textSpan = TextSpan(
//       style: s.textStyle,
//       children: b.inlines
//           .map((n) => _inlineToTextSpan(
//         n,
//         s.textStyle,
//         linkColor,
//         baseFontSize,
//         lineHeight,
//       ))
//           .toList(),
//     );
//
//     // Измеряем высоту с тем же maxWidth (минус отступ слева)
//     final painter = TextPainter(
//       text: textSpan,
//       textDirection: direction,
//       textAlign: s.textAlign,
//       maxLines: null,
//     )..layout(maxWidth: maxWidth - s.indentLeft);
//
//     out.add(_MeasuredBlock(
//       block: b,
//       span: textSpan,
//       align: s.textAlign,
//       indentLeft: s.indentLeft,
//       spaceBefore: s.spaceBefore,
//       spaceAfter: s.spaceAfter,
//       height: painter.height,
//     ));
//   }
//   return out;
// }
//
// List<_PageSlice> _paginate(List<_MeasuredBlock> items, double maxHeight) {
//   final pages = <_PageSlice>[];
//   double cursor = 0;
//   int start = 0;
//
//   for (int i = 0; i < items.length; i++) {
//     final it = items[i];
//
//     final double blockTotalHeight =
//         (pages.isEmpty && i == 0 ? 0 : it.spaceBefore) + it.height + it.spaceAfter;
//
//     if (cursor + blockTotalHeight > maxHeight && i > start) {
//       // закрываем страницу до предыдущего
//       pages.add(_PageSlice(start, i));
//       start = i;
//       cursor = 0;
//     }
//
//     // добавляем текущий
//     cursor += blockTotalHeight;
//   }
//
//   // последняя страница
//   if (start < items.length) {
//     pages.add(_PageSlice(start, items.length));
//   }
//
//   return pages;
// }
//
// /* ----------------------------- рендер одной страницы ----------------------------- */
//
// class _PageContent extends StatelessWidget {
//   final List<_MeasuredBlock> blocks;
//
//   const _PageContent({required this.blocks});
//
//   @override
//   Widget build(BuildContext context) {
//     final children = <Widget>[];
//
//     for (int i = 0; i < blocks.length; i++) {
//       final b = blocks[i];
//
//       if (b.spaceBefore > 0 && i != 0) {
//         children.add(SizedBox(height: b.spaceBefore));
//       }
//
//       // empty-line -> просто отступ
//       if (b.block.tag == 'empty-line') {
//         children.add(SizedBox(height: b.height));
//       } else if (b.block.tag == 'image') {
//         // плейсхолдер; подставь Image.memory(...) на основе бинарника
//         children.add(Container(
//           alignment: Alignment.center,
//           margin: EdgeInsets.only(left: b.indentLeft),
//           height: 160,
//           color: Colors.black12,
//           child: const Text('Изображение'),
//         ));
//       } else {
//         children.add(Container(
//           margin: EdgeInsets.only(left: b.indentLeft),
//           alignment: _alignToAlignment(b.align),
//           child: Text.rich(
//             b.span,
//             textAlign: b.align,
//           ),
//         ));
//       }
//
//       if (b.spaceAfter > 0) {
//         children.add(SizedBox(height: b.spaceAfter));
//       }
//     }
//
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.stretch,
//       children: children,
//     );
//   }
//
//   Alignment _alignToAlignment(TextAlign a) {
//     switch (a) {
//       case TextAlign.right:
//         return Alignment.centerRight;
//       case TextAlign.center:
//         return Alignment.center;
//       case TextAlign.left:
//       case TextAlign.start:
//       default:
//         return Alignment.centerLeft;
//     }
//   }
// }
//
// /* ----------------------------- стили и маппинги ----------------------------- */
//
// class _BlockStyle {
//   final TextStyle textStyle;
//   final TextAlign textAlign;
//   final double indentLeft;
//   final double spaceBefore;
//   final double spaceAfter;
//
//   _BlockStyle({
//     required this.textStyle,
//     required this.textAlign,
//     required this.indentLeft,
//     required this.spaceBefore,
//     required this.spaceAfter,
//   });
// }
//
// _BlockStyle _styleForBlockTag({
//   required BuildContext context,
//   required String tag,
//   required double baseFontSize,
//   required double lineHeight,
//   required double paraBaseSpacing,
// }) {
//   final base = DefaultTextStyle.of(context).style.copyWith(
//     fontSize: baseFontSize,
//     height: lineHeight,
//   );
//
//   switch (tag) {
//     case 'title':
//       return _BlockStyle(
//         textStyle: base.copyWith(fontSize: baseFontSize * 1.35, fontWeight: FontWeight.w700, height: lineHeight * 0.95),
//         textAlign: TextAlign.start,
//         indentLeft: 0,
//         spaceBefore: paraBaseSpacing * 1.2,
//         spaceAfter: paraBaseSpacing * 0.9,
//       );
//     case 'subtitle':
//       return _BlockStyle(
//         textStyle: base.copyWith(fontSize: baseFontSize * 1.15, fontStyle: FontStyle.italic),
//         textAlign: TextAlign.start,
//         indentLeft: 0,
//         spaceBefore: paraBaseSpacing * 0.8,
//         spaceAfter: paraBaseSpacing * 0.8,
//       );
//     case 'text-author':
//       return _BlockStyle(
//         textStyle: base.copyWith(fontStyle: FontStyle.italic),
//         textAlign: TextAlign.right,
//         indentLeft: 0,
//         spaceBefore: paraBaseSpacing * 0.5,
//         spaceAfter: paraBaseSpacing * 0.7,
//       );
//     case 'v': // стих — лёгкий отступ
//       return _BlockStyle(
//         textStyle: base,
//         textAlign: TextAlign.start,
//         indentLeft: 16,
//         spaceBefore: paraBaseSpacing * 0.3,
//         spaceAfter: 0,
//       );
//     case 'epigraph':
//     case 'cite':
//       return _BlockStyle(
//         textStyle: base.copyWith(fontStyle: FontStyle.italic),
//         textAlign: TextAlign.start,
//         indentLeft: 12,
//         spaceBefore: paraBaseSpacing,
//         spaceAfter: paraBaseSpacing * 0.6,
//       );
//     case 'empty-line':
//       return _BlockStyle(
//         textStyle: base,
//         textAlign: TextAlign.start,
//         indentLeft: 0,
//         spaceBefore: 0,
//         spaceAfter: 0,
//       );
//     case 'image':
//       return _BlockStyle(
//         textStyle: base,
//         textAlign: TextAlign.center,
//         indentLeft: 0,
//         spaceBefore: paraBaseSpacing,
//         spaceAfter: paraBaseSpacing,
//       );
//     case 'p':
//     default:
//       return _BlockStyle(
//         textStyle: base,
//         textAlign: TextAlign.start,
//         indentLeft: 0,
//         spaceBefore: paraBaseSpacing * 0.6,
//         spaceAfter: 0,
//       );
//   }
// }
//
// /// Конвертируем твои i.InlineText → Flutter TextSpan (без конфликтов имён).
// TextSpan _inlineToTextSpan(
//     i.InlineText node,
//     TextStyle base,
//     Color linkColor,
//     double baseFontSize,
//     double lineHeight,
//     ) {
//   if (node is i.TextRun) {
//     return TextSpan(text: node.text, style: base);
//   }
//
//   if (node is i.InlineSpan) {
//     // ЯВНОЕ ПРИВЕДЕНИЕ – после этого доступны tag/children
//     final i.InlineSpan spanNode = node;
//
//     TextStyle s = base;
//     switch (spanNode.tag) {
//       case 'strong':
//         s = s.copyWith(fontWeight: FontWeight.w700);
//         break;
//       case 'emphasis':
//         s = s.copyWith(fontStyle: FontStyle.italic);
//         break;
//       case 'a':
//         s = s.copyWith(
//           decoration: TextDecoration.underline,
//           color: linkColor,
//         );
//         break;
//       case 'code':
//         s = s.copyWith(fontFamily: 'monospace', backgroundColor: Colors.black12);
//         break;
//       case 'strikethrough':
//         s = s.copyWith(decoration: TextDecoration.lineThrough);
//         break;
//       case 'sub':
//       case 'sup':
//         s = s.copyWith(
//           fontSize: (base.fontSize ?? baseFontSize) * 0.8,
//           height: lineHeight * 0.9,
//         );
//         break;
//     // 'style', 'date' и прочие — без доп. модификаций
//     }
//
//     return TextSpan(
//       style: s,
//       children: spanNode.children
//           .map((c) => _inlineToTextSpan(c, s, linkColor, baseFontSize, lineHeight))
//           .toList(),
//     );
//   }
//
//   // на всякий случай
//   return const TextSpan(text: '');
// }
