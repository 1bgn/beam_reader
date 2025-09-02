import 'package:flutter/widgets.dart';
import '../../../../engine/elements/layout_blocks/custom_text_layout.dart';
import '../../../../engine/elements/layout_blocks/line_layout.dart';
import '../../../../engine/elements/layout_blocks/multi_column_page.dart';

/// Разбивает CustomTextLayout на страницы с N колонками, заполняя по высоте.
MultiColumnPagedLayout buildPagedLayoutFromLines({
  required CustomTextLayout layout,
  required Size pageSize,
  int columnsPerPage = 1,
  double columnSpacing = 24,
  double lineSpacing = 0,
}) {
  assert(columnsPerPage >= 1);

  final pages = <MultiColumnPage>[];

  final pageWidth  = pageSize.width;
  final pageHeight = pageSize.height;

  final columnWidth =
      (pageWidth - (columnsPerPage - 1) * columnSpacing) / columnsPerPage;

  // Текущая страница: списки колонок; каждая колонка — список LineLayout
  List<List<LineLayout>> currentColumns =
  List.generate(columnsPerPage, (_) => <LineLayout>[]);

  final heights = List<double>.filled(columnsPerPage, 0);
  int colIndex = 0;

  for (final line in layout.lines) {
    final h = line.height + lineSpacing;

    // не влезает в колонку (и колонка не пустая) — переходим к следующей
    if (heights[colIndex] + h > pageHeight && currentColumns[colIndex].isNotEmpty) {
      colIndex++;
      // если колонок нет — сохраняем страницу и начинаем новую
      if (colIndex >= columnsPerPage) {
        pages.add(MultiColumnPage(
          columns: currentColumns.map((e) => List<LineLayout>.from(e)).toList(),
          pageWidth: pageWidth,
          pageHeight: pageHeight,
          columnWidth: columnWidth,
          columnSpacing: columnSpacing,
        ));
        currentColumns =
            List.generate(columnsPerPage, (_) => <LineLayout>[]);
        for (int i = 0; i < heights.length; i++) heights[i] = 0;
        colIndex = 0;
      }
    }

    currentColumns[colIndex].add(line);
    heights[colIndex] += h;
  }

  // докатываем хвост
  final hasAny = currentColumns.any((c) => c.isNotEmpty);
  if (hasAny) {
    pages.add(MultiColumnPage(
      columns: currentColumns.map((e) => List<LineLayout>.from(e)).toList(),
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      columnWidth: columnWidth,
      columnSpacing: columnSpacing,
    ));
  }

  return MultiColumnPagedLayout(pages);
}
