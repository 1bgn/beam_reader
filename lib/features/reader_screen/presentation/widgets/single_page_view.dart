import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_render_obj.dart';
import 'package:flutter/material.dart';

import '../../../../engine/elements/layout_blocks/multi_column_page.dart';

class SinglePageView extends LeafRenderObjectWidget {
  final MultiColumnPage page;
  final double lineSpacing;
  final bool allowSoftHyphens;
  final void Function(String explanation)? onFootnoteTap;

  const SinglePageView({
    Key? key,
    required this.page,
    required this.lineSpacing,
    required this.allowSoftHyphens,
    this.onFootnoteTap,
  }) : super(key: key);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return SinglePageRenderObj(
      page: page,
      lineSpacing: lineSpacing,
      allowSoftHyphens: allowSoftHyphens,
      onFootnoteTap: onFootnoteTap,
    );
  }

  @override
  void updateRenderObject(BuildContext context, SinglePageRenderObj renderObject) {
    renderObject
      ..page = page
      ..lineSpacing = lineSpacing
      ..allowSoftHyphens = allowSoftHyphens
      ..onFootnoteTap = onFootnoteTap;
  }
}