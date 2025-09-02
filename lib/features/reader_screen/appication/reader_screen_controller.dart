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
import '../../../engine/fb2_transform.dart';

@LazySingleton()
class ReaderScreenController {
  final XmlLoader xmlLoader;
  final Signal<CustomTextLayout?> textLayout = signal(null);
  // final Fb2Parser fb2parser;

  ReaderScreenController(this.xmlLoader);

  Future buildBook(BuildContext context) async {
    final start = DateTime.now();

    final bookStringXml = await loadBook();
    final bookXml = XmlDocument.parse(bookStringXml);
    final bodyXml = bookXml.findAllElements("body");
    final sections = bodyXml?.first.findElements("section");
    final transformer = Fb2Transformer();

    final blocks = transformer.parseToBlocks(bookXml.rootElement);

    // final lines = transformer.groupIntoLines(blocks);
    final chunks = chunkBlocksByPages(
      context: context,
      blocks: blocks,
      viewportWidth: MediaQuery.of(context).size.width,
      viewportHeight: MediaQuery.of(context).size.height,
      targetPagesPerChunk: 25, // ≈ по 25 страниц
      // настройки должны совпадать с вашим рендером:
      baseFontSize: 18,
      lineHeight: 1.6,
      paragraphSpacing: 10,
      pagePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    );
    final AdvancedLayoutEngine advancedLayoutEngine = AdvancedLayoutEngine(
      paragraphs: blocks.sublist(chunks.first.blockStart, chunks.first.blockEnd).map((e)=>e.inlines)
          .map(
            (e) => ParagraphBlock(
              inlineElements: e
                  .map(
                    (e) => TextInlineElement(
                      text: (e is TextRun) ? e.text : "",
                      style: TextStyle(color: Colors.black),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      globalMaxWidth: MediaQuery.of(context).size.width,
      globalTextAlign: TextAlign.left,
    );
    print("lines ${advancedLayoutEngine.paragraphs}");
   CustomTextLayout customTextLayout =  advancedLayoutEngine.layoutAllParagraphs();
   textLayout.value = customTextLayout;
    final end = DateTime.now();
    final diff = end.difference(start);

    print('Время выполнения: ${diff.inMilliseconds} мс');
    // for (final line in lines) {
    //   final buf = StringBuffer();
    //   for (final inline in line) {
    //     if (inline is TextRun) {
    //       buf.write(inline.text);
    //     } else if (inline is InlineSpan) {
    //
    //       buf.write(inline.toString());
    //     }
    //   }
    //   print(buf.toString());
    // }
    //
    // print("GOTOVO");
    return blocks;
  }

  Future<String> loadBook() {
    return xmlLoader.loadBook();
  }
}
