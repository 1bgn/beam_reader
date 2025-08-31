import 'package:beam_reader/engine/elements/block_text.dart';
import 'package:beam_reader/engine/elements/inline_text.dart';
import 'package:injectable/injectable.dart';
import 'package:xml/xml.dart';

@LazySingleton()
class Fb2Parser {
  List<BlockText> parseElements(List<XmlNode> elems) {
    final List<BlockText> blockElements = [];
    for (var e in elems) {
      blockElements.addAll(parseElement(e));
    }
    return blockElements;
  }
  List<BlockText> parseElement(XmlNode  node,{List<String> parent = const []}) {
    final List<BlockText> blockElements = [];
    for (var node in node.children) {
      if(node.children.isNotEmpty){
        blockElements.addAll(parseElement(node,parent: parent+[node.parentElement?.name.local??""]));
      }else{
        if(node.value!=null && node.value!.trim().isNotEmpty ){
            blockElements.add(BlockText(inlines: [InlineText(text: node.value??"", parentTypes: parent+[node.parentElement?.name.local??""])], ));
        }
        else{
            if(node.toString().trim().isNotEmpty){
              if(node.nodeType==XmlNodeType.ELEMENT){
                blockElements.add(BlockText(inlines: [InlineText(text: node.value??"", parentTypes: [node.parentElement?.name.local??"",(node as XmlElement).name.local])], ));

              }
            }
        }
      }
    }
    return blockElements;
  }


  List<String> blocks = [
    "body",
    "section",
    "title",
    "subtitle",
    "p",
    "empty-line",
    "poem",
    "stanza",
    "v",
    "epigraph",
    "annotation",
    "image",
    "table",
    "tr",
    "td",
  ];
  List<String> inlines = [
    "style",
    "emphasis",
    "strong",
    "sub",
    "sup",
    "strikethrough",
    "a",
    "code",
    "date",
  ];
}
