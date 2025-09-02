import 'package:beam_reader/features/reader_screen/presentation/widgets/paged_layout_builder.dart';
import 'package:flutter/widgets.dart';
import '../../../../engine/elements/layout_blocks/custom_text_layout.dart';
import '../../../../engine/elements/layout_blocks/multi_column_page.dart';
import 'single_page_view.dart';

class PagedReaderView extends StatelessWidget {
  final CustomTextLayout layout;

  // геометрия
  final int columnsPerPage;
  final double columnSpacing;
  final double lineSpacing;

  // рендер
  final bool allowSoftHyphens;

  // выделение (опционально, если у тебя обновлённый SinglePageView/RenderObj)
  final bool enableSelection;
  final bool doubleTapSelectsWord;
  final bool tripleTapSelectsLine;
  final bool holdToSelect;
  final bool clearSelectionOnSingleTap;

  final void Function(String explanation)? onFootnoteTap;
  final void Function(int start, int end)? onSelectionChanged;

  const PagedReaderView({
    super.key,
    required this.layout,
    this.columnsPerPage = 1,
    this.columnSpacing = 24,
    this.lineSpacing = 0,
    this.allowSoftHyphens = true,
    this.enableSelection = true,
    this.doubleTapSelectsWord = true,
    this.tripleTapSelectsLine = true,
    this.holdToSelect = true,
    this.clearSelectionOnSingleTap = false,
    this.onFootnoteTap,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final paged = buildPagedLayoutFromLines(
          layout: layout,
          pageSize: Size(c.maxWidth, c.maxHeight),
          columnsPerPage: columnsPerPage,
          columnSpacing: columnSpacing,
          lineSpacing: lineSpacing,
        );

        return PageView.builder(
          itemCount: paged.pages.length,
          physics: const PageScrollPhysics(),
          itemBuilder: (ctx, i) {
            final page = paged.pages[i];
            return SinglePageView(
              page: page,
              lineSpacing: lineSpacing,
              allowSoftHyphens: allowSoftHyphens,
              // если твой SinglePageView уже принимает флаги выделения — раскомментируй:
              enableSelection: enableSelection,
              doubleTapSelectsWord: doubleTapSelectsWord,
              tripleTapSelectsLine: tripleTapSelectsLine,
              holdToSelect: holdToSelect,
              clearSelectionOnSingleTap: clearSelectionOnSingleTap,
              onFootnoteTap: onFootnoteTap,
              onSelectionChanged: onSelectionChanged,
            );
          },
        );
      },
    );
  }
}
