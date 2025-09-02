// lib/features/reader_screen/presentation/paged_reader_screen.dart
import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_view.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../appication/reader_screen_controller.dart';

class PagedReaderScreen extends StatefulWidget {
  const PagedReaderScreen({super.key});

  @override
  State<PagedReaderScreen> createState() => _PagedReaderScreenState();
}

class _PagedReaderScreenState extends State<PagedReaderScreen> {
  final ReaderPagerController controller = getIt();
  final _pageCtrl = PageController();

  @override
  void initState() {
    super.initState();
    controller.init(context);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const pagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 28);
    final usableWidth  = size.width  - pagePadding.horizontal;
    final usableHeight = size.height - pagePadding.vertical;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Watch((ctx) {
        final total = controller.totalPages.value;
        if (total == 0) {
          return const Center(child: CircularProgressIndicator());
        }

        return PageView.builder(
          controller: _pageCtrl,
          onPageChanged: (i) => controller.prefetchAround(context, i),
          itemCount: total,
          itemBuilder: (ctx, index) {
            final layout = controller.getPage(index);
            if (layout == null) {
              controller.ensurePage(context, index);
              return const Center(child: CircularProgressIndicator());
            }

            final page = _buildPageFromLayout(
              Size(usableWidth, usableHeight),  // ← пробрасываем usable размер
              layout,
            );

            return Padding(
              padding: pagePadding,             // ← рисуем в том же окне, что и при измерении
              child: SizedBox(
                width: usableWidth,
                height: usableHeight,
                child: SinglePageView(
                  page: page,
                  lineSpacing: 0,
                  allowSoftHyphens: true,
                ),
              ),
            );
          },
        );
      }),
    );
  }


  MultiColumnPage _buildPageFromLayout(Size usable, CustomTextLayout layout) {
    return MultiColumnPage(
      columns: [layout.lines],
      pageWidth: usable.width,
      pageHeight: usable.height, // не критично, но консистентно
      columnWidth: usable.width, // ← ключевое: колонка = usableWidth
      columnSpacing: 0,
    );
  }
}
