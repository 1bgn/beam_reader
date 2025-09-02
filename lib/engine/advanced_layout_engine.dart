import 'package:injectable/injectable.dart';

import 'elements/data_blocks/inline_text.dart';


@LazySingleton()
class AdvancedLayoutEngine{
  final  List<List<InlineText>> lines;

  AdvancedLayoutEngine({required this.lines});
}