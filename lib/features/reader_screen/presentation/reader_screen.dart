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

  int _currentIndex = 0;
  Orientation? _lastOrientation;

  // симметричные поля: слева=20, справа=20, сверху/снизу=28
  static const EdgeInsets _contentPad =
  EdgeInsets.symmetric(horizontal: 20, vertical: 28);

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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea( // не уходим под динамик/вырез
        child: OrientationBuilder(
          builder: (ctx, orientation) {
            if (_lastOrientation != orientation) {
              _lastOrientation = orientation;

              final anchor = controller.anchorForPage(_currentIndex);
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await controller.reflow(context, preserve: anchor);
                if (mounted) {
                  _pageCtrl.jumpToPage(0);
                  _currentIndex = 0;
                }
              });
            }

            return LayoutBuilder(
              builder: (ctx, constraints) {
                // размер уже с учётом SafeArea
                final safeSize = constraints.biggest;

                return Watch((ctx) {
                  final total = controller.totalPages.value;
                  if (total == 0) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return PageView.builder(
                    controller: _pageCtrl,
                    physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
                    onPageChanged: (i) {
                      _currentIndex = i;
                      controller.prefetchAround(context, i);
                    },
                    itemCount: total,
                    itemBuilder: (ctx, index) {
                      final layout = controller.getPage(index);
                      if (layout == null) {
                        controller.ensurePage(context, index);
                        return const Center(child: CircularProgressIndicator());
                      }

                      final page = _buildPageFromLayout(
                        safeSize,
                        layout,
                        _contentPad,
                      );

                      // важное: паддинг вокруг канвы, а внутрь передаём pageHeight без этих паддингов
                      return Padding(
                        padding: _contentPad,
                        child: SizedBox.expand(
                          child: SinglePageView(
                            page: page,
                            lineSpacing: 0,
                            allowSoftHyphens: true,
                          ),
                        ),
                      );
                    },
                  );
                });
              },
            );
          },
        ),
      ),
    );
  }

  MultiColumnPage _buildPageFromLayout(
      Size safeSize,
      CustomTextLayout layout,
      EdgeInsets pad,
      ) {
    final contentWidth  = safeSize.width  - pad.left - pad.right;
    final contentHeight = safeSize.height - pad.top  - pad.bottom;

    return MultiColumnPage(
      columns: [layout.lines],
      pageWidth: contentWidth,     // ширина области рисования
      pageHeight: contentHeight,   // ВАЖНО: высота области рисования = без паддингов
      columnWidth: contentWidth,
      columnSpacing: 0,
    );
  }
}
