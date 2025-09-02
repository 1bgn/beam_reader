// lib/features/reader_screen/presentation/widgets/single_page_view.dart
import 'package:flutter/material.dart';
import '../../../../engine/elements/layout_blocks/multi_column_page.dart';
import 'single_page_render_obj.dart';

class SinglePageView extends LeafRenderObjectWidget {
  final MultiColumnPage page;
  final double lineSpacing;
  final bool allowSoftHyphens;

  // ↓↓↓ новые параметры
  final bool enableSelection;
  final bool doubleTapSelectsWord;
  final bool tripleTapSelectsLine;
  final bool holdToSelect;
  final bool clearSelectionOnSingleTap;

  final void Function(String explanation)? onFootnoteTap;
  final void Function(int start, int end)? onSelectionChanged;

  const SinglePageView({
    super.key,
    required this.page,
    required this.lineSpacing,
    required this.allowSoftHyphens,
    this.enableSelection = true,
    this.doubleTapSelectsWord = true,
    this.tripleTapSelectsLine = true,
    this.holdToSelect = true,
    this.clearSelectionOnSingleTap = false,
    this.onFootnoteTap,
    this.onSelectionChanged,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return SinglePageRenderObj(
      page: page,
      lineSpacing: lineSpacing,
      allowSoftHyphens: allowSoftHyphens,
      enableSelection: enableSelection,
      doubleTapSelectsWord: doubleTapSelectsWord,
      tripleTapSelectsLine: tripleTapSelectsLine,
      holdToSelect: holdToSelect,
      clearSelectionOnSingleTap: clearSelectionOnSingleTap,
      onFootnoteTap: onFootnoteTap,
      onSelectionChanged: onSelectionChanged,
    );
  }

  @override
  void updateRenderObject(BuildContext context, SinglePageRenderObj ro) {
    ro
      ..page = page
      ..lineSpacing = lineSpacing
      ..allowSoftHyphens = allowSoftHyphens
      ..enableSelection = enableSelection
      ..doubleTapSelectsWord = doubleTapSelectsWord
      ..tripleTapSelectsLine = tripleTapSelectsLine
      ..holdToSelect = holdToSelect
      ..clearSelectionOnSingleTap = clearSelectionOnSingleTap
      ..onFootnoteTap = onFootnoteTap
      ..onSelectionChanged = onSelectionChanged;
  }
}
