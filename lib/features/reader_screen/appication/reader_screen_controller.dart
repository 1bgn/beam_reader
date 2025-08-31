import 'package:beam_reader/engine/fb2_parser.dart';
import 'package:beam_reader/engine/xml_loader.dart';
import 'package:injectable/injectable.dart';
import 'package:xml/xml.dart';

@LazySingleton()
class ReaderScreenController {
  final XmlLoader xmlLoader;
  final Fb2Parser fb2parser;

  ReaderScreenController(this.xmlLoader, this.fb2parser);



  Future start() async {
   final bookStringXml = await loadBook();
   final bookXml = XmlDocument.parse(bookStringXml);
   final bodyXml = bookXml.findAllElements("body");
   final sections = bodyXml?.first.findElements("section");
  final res =  fb2parser.parseElements([sections!.toList()[1]]);

   res.forEach((e){
     print("!!! $e");
   });
   // print("bdoy ${bodyXml}");
  }

  Future<String> loadBook(){
    return xmlLoader.loadBook();
  }
}