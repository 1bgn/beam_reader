import 'package:beam_reader/engine/xml_loader.dart';
import 'package:injectable/injectable.dart';
import 'package:xml/xml.dart';

import '../../../engine/fb2_transform.dart';

@LazySingleton()
class ReaderScreenController {
  final XmlLoader xmlLoader;
  // final Fb2Parser fb2parser;

  ReaderScreenController(this.xmlLoader, );



  Future buildBook() async {
    final start = DateTime.now();

   final bookStringXml = await loadBook();
   final bookXml = XmlDocument.parse(bookStringXml);
   final bodyXml = bookXml.findAllElements("body");
   final sections = bodyXml?.first.findElements("section");
   final transformer = Fb2Transformer();


    final blocks = transformer.parseToBlocks(sections!.toList()[1]);

    final lines = transformer.groupIntoLines(blocks);
    print("lines $lines");
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

  Future<String> loadBook(){
    return xmlLoader.loadBook();
  }
}