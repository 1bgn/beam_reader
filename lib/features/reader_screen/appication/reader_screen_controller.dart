import 'dart:ui' as ui;

import 'package:beam_reader/engine/advanced_layout_engine.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/paragraph_block.dart';
import 'package:beam_reader/engine/elements/layout_blocks/image_inline_element.dart';
import 'package:beam_reader/engine/fb2_transform.dart';
import 'package:beam_reader/engine/xml_loader.dart';

import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:xml/xml.dart';

import '../../../engine/elements/chunker.dart';
import '../../../engine/elements/fb2_style_map.dart';               // твой пагинатор по блокам

@LazySingleton()
class ReaderScreenController {
  final XmlLoader xmlLoader;
  final Signal<CustomTextLayout?> textLayout = signal(null);

  ReaderScreenController(this.xmlLoader);

  Future buildBook(BuildContext context) async {
    final start = DateTime.now();

    // 1) загрузили и распарсили FB2
    final bookStringXml = await loadBook();
    final bookXml = XmlDocument.parse(bookStringXml);

    final transformer = Fb2Transformer();
    final blocks = transformer.parseToBlocks(bookXml.rootElement);

    // 2) параметры типографики (должны совпадать с движком/рендером)
    const baseFontSize   = 16.0;
    const lineHeight     = 1.6;
    const paragraphSpace = 10.0;

    final viewportWidth  = MediaQuery.of(context).size.width;
    final viewportHeight = MediaQuery.of(context).size.height;

    // 3) разбиваем на чанки страниц (как раньше)
    final chunks = chunkBlocksByPages(
      context: context,
      blocks: blocks,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      targetPagesPerChunk: 25,
      baseFontSize: baseFontSize,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpace,
      pagePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    );

    // берём первый чанк (подключишь постраничный просмотр позже)
    final slice = blocks.sublist(chunks.first.blockStart, chunks.first.blockEnd);

    // 4) собрали бинарники картинок и подготовили кэш ui.Image
    final binaries = extractBinaryMap(bookXml);
    final images = <String, ui.Image>{};

    Future<ui.Image?> _resolveImageForBlockAttrs(Map<String, String>? attrs) async {
      if (attrs == null) return null;
      final href = attrs['href'] ?? attrs['xlink:href'];
      if (href == null || href.isEmpty) return null;
      final id = href.startsWith('#') ? href.substring(1) : href;
      if (images.containsKey(id)) return images[id];
      final bytes = binaries[id];
      if (bytes == null) return null;
      final img = await decodeUiImage(bytes);
      images[id] = img;
      return img;
    }

    // 5) конвертируем slice → ParagraphBlock’и со стилями и картинками
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
          ),
        );
        continue;
      }

      if (b.tag == 'image') {
        final img = await _resolveImageForBlockAttrs(b.attrs);
        if (img != null) {
          paragraphs.add(
            ParagraphBlock(
              inlineElements: [
                ImageInlineElement(
                  image: img,
                  // maxHeight: viewportHeight * 0.6, // опционально
                  radius: BorderRadius.circular(8),
                ),
              ],
              textAlign: s.textAlign,               // обычно center
              paragraphSpacing: s.paragraphSpacing,
              enableRedLine: false,
              firstLineIndent: 0,
              maxWidth: s.containerWidthFactor,     // сузить контейнер
              containerAlignment: s.containerAlign, // центр контейнера
            ),
          );
        }
        continue;
      }

      // обычный текстовый блок
      final inlines = buildInlineElements(b.inlines, s.textStyle);
      paragraphs.add(
        ParagraphBlock(
          inlineElements: inlines,
          textAlign: s.textAlign,
          paragraphSpacing: s.paragraphSpacing,
          enableRedLine: s.enableRedLine,
          firstLineIndent: s.firstLineIndent,      // может быть отрицательным (epigraph)
          maxWidth: s.containerWidthFactor,
          containerAlignment: s.containerAlign,
        ),
      );
    }

    // 6) раскладка
    final engine = AdvancedLayoutEngine(
      allowSoftHyphens: true,
      paragraphs: paragraphs,
      globalMaxWidth: viewportWidth,
      globalTextAlign: TextAlign.justify,
    );

    final customTextLayout = engine.layoutAllParagraphs();
    textLayout.value = customTextLayout;

    debugPrint('layout: ${DateTime.now().difference(start).inMilliseconds} ms');
    return blocks;
  }

  Future<String> loadBook() => xmlLoader.loadBook();
}
