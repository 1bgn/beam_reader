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
  final PageController _pageCtrl = PageController();

  int _currentIndex = 0;
  Orientation? _lastOrientation;

  // симметричные поля
  static const EdgeInsets _contentPad =
  EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  @override
  void initState() {
    super.initState();
    controller.init(context);

    // первичная подгрузка вокруг первой страницы — после первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.prefetchAround(context, _currentIndex);
    });
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
      body: SafeArea(
        child: OrientationBuilder(
          builder: (ctx, orientation) {
            // при повороте — сохраняем якорь и полностью пересчитываем
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
                final safeSize = constraints.biggest;

                return Watch((ctx) {
                  final total = controller.totalPages.value;
                  if (total == 0) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return PageView.builder(
                    controller: _pageCtrl,
                    allowImplicitScrolling: true, // iOS lookahead для соседних
                    physics: const PageScrollPhysics(),
                    // ВАЖНО: подгружаем только когда страница уже в центре
                    onPageChanged: (i) {
                      _currentIndex = i;

                      // даём этому кадру дорисоваться, затем считаем
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        // подгружаем текущую (на случай плейсхолдера) и соседние
                        controller.ensurePage(context, i);
                        controller.prefetchAround(context, i, radius: 2);
                      });
                    },
                    itemCount: total,
                    itemBuilder: (ctx, index) {
                      final layout = controller.getPage(index);

                      if (layout == null) {
                        // Плейсхолдер без тяжёлых расчётов — НИЧЕГО не считаем здесь
                        return Padding(
                          padding: _contentPad,
                          child: const RepaintBoundary(
                            child: ColoredBox(color: Colors.white),
                          ),
                        );
                      }

                      final page = _buildPageFromLayout(
                        safeSize,
                        layout,
                        _contentPad,
                      );

                      return Padding(
                        padding: _contentPad,
                        child: RepaintBoundary(
                          child: SizedBox.expand(
                            child: SinglePageView(
                              page: page,
                              lineSpacing: 0,
                              allowSoftHyphens: true,
                            ),
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
      pageWidth: contentWidth,
      pageHeight: contentHeight,
      columnWidth: contentWidth,
      columnSpacing: 0,
    );
  }
}
