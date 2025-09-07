// lib/features/reader_screen/presentation/paged_reader_screen.dart
import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Orientation? _lastOrientation = Orientation.portrait;

  static const EdgeInsets _contentPad =
  EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  static const _kAnimDuration = Duration(milliseconds: 180);
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    controller.init(context);

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

  Future<void> _goTo(int target) async {
    if (!_pageCtrl.hasClients) return;
    final total = controller.totalPages.value;
    if (target < 0 || target >= total) return;
    if (_isAnimating) return;

    _isAnimating = true;

    // лениво подготавливаем цель
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.ensurePage(context, target);
      controller.prefetchAround(context, target, radius: 2);
    });

    try {
      await _pageCtrl.animateToPage(
        target,
        duration: _kAnimDuration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isAnimating = false;
    }
  }

  KeyEventResult _handleKey(KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isShift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);

    if (e.logicalKey == LogicalKeyboardKey.arrowRight ||
        e.logicalKey == LogicalKeyboardKey.pageDown ||
        (e.logicalKey == LogicalKeyboardKey.space && !isShift)) {
      _goTo(_currentIndex + 1);
      return KeyEventResult.handled;
    }

    if (e.logicalKey == LogicalKeyboardKey.arrowLeft ||
        e.logicalKey == LogicalKeyboardKey.pageUp ||
        (e.logicalKey == LogicalKeyboardKey.space && isShift)) {
      _goTo(_currentIndex - 1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: OrientationBuilder(
          builder: (ctx, orientation) {
            // обработка смены ориентации: пересчет и восстановление "назад"
            if (_lastOrientation != orientation) {
              _lastOrientation = orientation;
              final anchor = controller.anchorForPage(_currentIndex);

              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final startIndex =
                await controller.reflow(context, preserve: anchor, backfill: 3);
                if (!mounted) return;

                // ставим PageView на корректную страницу (учтен backfill)
                _pageCtrl.jumpToPage(startIndex);
                _currentIndex = startIndex;

                // подгрузим окрестности
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  controller.ensurePage(context, startIndex);
                  controller.prefetchAround(context, startIndex, radius: 2);
                });
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

                  // только свайпы (PageView) и клавиатура — никаких mouse/trackpad listeners
                  return Focus(
                    autofocus: true,
                    onKeyEvent: (node, event) => _handleKey(event),
                    child: PageView.builder(
                      controller: _pageCtrl,
                      physics: const PageScrollPhysics(), // свайпы
                      allowImplicitScrolling: true,
                      onPageChanged: (i) {
                        _currentIndex = i;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          controller.ensurePage(context, i);
                          controller.prefetchAround(context, i, radius: 2);
                        });
                      },
                      itemCount: total,
                      itemBuilder: (ctx, index) {
                        final layout = controller.getPage(index);
                        if (layout == null) {
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
                    ),
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
    final contentWidth = safeSize.width - pad.left - pad.right;
    final contentHeight = safeSize.height - pad.top - pad.bottom;

    return MultiColumnPage(
      columns: [layout.lines],
      pageWidth: contentWidth,
      pageHeight: contentHeight,
      columnWidth: contentWidth,
      columnSpacing: 0,
    );
  }
}
