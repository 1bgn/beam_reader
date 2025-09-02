import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
@LazySingleton()
class XmlLoader {
  Future<String> loadBook()async{
    return rootBundle.loadString("assets/books/book2.fb2");
  }
}