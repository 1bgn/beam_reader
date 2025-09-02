import 'line_layout.dart';

class MultiColumnPagedLayout {
final List<MultiColumnPage> pages;

MultiColumnPagedLayout(this.pages);
}

/// MultiColumnPage — одна страница с несколькими колонками.
class MultiColumnPage {
  final List<List<LineLayout>> columns;
  final double pageWidth;
  final double pageHeight;
  final double columnWidth;
  final double columnSpacing;

  MultiColumnPage({
    required this.columns,
    required this.pageWidth,
    required this.pageHeight,
    required this.columnWidth,
    required this.columnSpacing,
  });
  factory MultiColumnPage.empty(double pageWidth, double pageHeight, double columnSpacing) {
    return MultiColumnPage(
      columns: [],
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      columnWidth: 0,
      columnSpacing: columnSpacing,
    );
  }
}