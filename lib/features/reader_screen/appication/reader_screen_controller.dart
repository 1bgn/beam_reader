import 'package:beam_reader/engine/advanced_layout_engine.dart';
import 'package:beam_reader/engine/elements/data_blocks/text_run.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/paragraph_block.dart';
import 'package:beam_reader/engine/elements/layout_blocks/text_inline_element.dart';
import 'package:beam_reader/engine/hyphenator.dart';
import 'package:beam_reader/engine/xml_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:xml/xml.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../engine/elements/chunker.dart';
import '../../../engine/elements/fb2_style_map.dart';
import '../../../engine/fb2_transform.dart';




@LazySingleton()
class ReaderScreenController {
  final XmlLoader xmlLoader;
  final Signal<CustomTextLayout?> textLayout = signal(null);

  ReaderScreenController(this.xmlLoader);

  Future buildBook(BuildContext context) async {
    final start = DateTime.now();

    final bookStringXml = await loadBook();
    final bookXml = XmlDocument.parse(bookStringXml);
    final transformer = Fb2Transformer();
    final blocks = transformer.parseToBlocks(bookXml.rootElement);

    // параметры типографики (должны совпадать с движком/рендером)
    const baseFontSize   = 16.0;
    const lineHeight     = 1.6;
    const paragraphSpace = 10.0;

    final chunks = chunkBlocksByPages(
      context: context,
      blocks: blocks,
      viewportWidth: MediaQuery.of(context).size.width,
      viewportHeight: MediaQuery.of(context).size.height,
      targetPagesPerChunk: 25,
      baseFontSize: baseFontSize,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpace,
      pagePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    );

    // возьмём первый чанк (дальше можно подключить постраничную навигацию)
    final slice = blocks.sublist(chunks.first.blockStart, chunks.first.blockEnd);

    final pageWidth = MediaQuery.of(context).size.width;

    // строим ParagraphBlock'и с учётом стилей по тегам
    final paragraphs = <ParagraphBlock>[];
    for (final b in slice) {
      final s = fb2BlockRenderStyle(
        tag: b.tag,
        depth: b.depth,
        baseFontSize: baseFontSize,
        lineHeight: lineHeight,
        color: Colors.black,
      );

      if (b.tag == 'empty-line') {
        paragraphs.add(
          ParagraphBlock(
            inlineElements: const [],
            textAlign: TextAlign.start,
            paragraphSpacing: s.paragraphSpacing,
            enableRedLine: false,
            firstLineIndent: 0,
          ),
        );
        continue;
      }

      final inlines = buildInlineElements(b.inlines, s.textStyle);

      paragraphs.add(
        ParagraphBlock(
          inlineElements: inlines,
          textAlign: s.textAlign,
          paragraphSpacing: s.paragraphSpacing,
          enableRedLine: s.enableRedLine,
          firstLineIndent: s.firstLineIndent,          // может быть отрицательным (epigraph)
          maxWidth: s.containerWidthFactor,            // сужаем контейнер для epigraph/cite
          containerAlignment: s.containerAlign,        // выравнивание контейнера
          // при необходимости: minimumLines, textDirection и т.п.
        ),
      );
    }

    final engine = AdvancedLayoutEngine(
      allowSoftHyphens: true,
      paragraphs: paragraphs,
      globalMaxWidth: pageWidth,
      globalTextAlign: TextAlign.justify, // дефолт для тех абзацев, где не задан
    );

    final customTextLayout = engine.layoutAllParagraphs();
    textLayout.value = customTextLayout;

    debugPrint('layout: ${DateTime.now().difference(start).inMilliseconds} ms');
    return blocks;
  }

  Future<String> loadBook() => xmlLoader.loadBook();
}
