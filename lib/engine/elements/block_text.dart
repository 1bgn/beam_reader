import 'package:beam_reader/engine/elements/element_text.dart';
import 'package:beam_reader/engine/elements/inline_text.dart';

class BlockText{
  final List<InlineText> inlines;
  // final List<BlockText> blocks;

  // BlockText({required this.inlines,required this.blocks});
  BlockText({required this.inlines,});

  @override
  String toString() {
    return inlines.map((e)=>"${e.parentTypes} ${e.text}").toString();
  }
}