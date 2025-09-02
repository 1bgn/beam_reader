import 'line_layout.dart';

class CustomTextLayout {
  final List<LineLayout> lines;
  final double totalHeight;
  final List<int> paragraphIndexOfLine;

  CustomTextLayout({
    required this.lines,
    required this.totalHeight,
    required this.paragraphIndexOfLine,
  });
}