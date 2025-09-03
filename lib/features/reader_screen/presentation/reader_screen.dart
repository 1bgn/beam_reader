// lib/features/reader_screen/presentation/paged_reader_screen.dart
import 'dart:ui' as ui show PointerDeviceKind;

import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_view.dart';
import 'package:flutter/gestures.dart';
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
  Orientation? _lastOrientation;

  static const EdgeInsets _contentPad =
  EdgeInsets.symmetric(horizontal: 20, vertical: 28);

  static const _kAnimDuration = Duration(milliseconds: 180);
  bool _isAnimating = false;
  DateTime? _lastWheelTs;
  static const _kWheelThrottle = Duration(milliseconds: 220);

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

    // мягко подготовим цель и соседей — уже после кадра (не блокируем UI)
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



  void _handlePointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;

    // throttle, чтобы одно «прокручивание» не давало серию перелистываний
    final now = DateTime.now();
    if (_lastWheelTs != null &&
        now.difference(_lastWheelTs!) < _kWheelThrottle) return;
    _lastWheelTs = now;

    // Колесо обычно вертикальное — маппим вниз -> следующая страница
    final dy = signal.scrollDelta.dy;
    if (dy > 0) {
      _goTo(_currentIndex + 1);
    } else if (dy < 0) {
      _goTo(_currentIndex - 1);
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
    final scrollBehavior = _EverywhereDragScrollBehavior();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
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
                final safeSize = constraints.biggest;

                return Watch((ctx) {
                  final total = controller.totalPages.value;
                  if (total == 0) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return ScrollConfiguration(
                    behavior: scrollBehavior,
                    child: Focus(
                      autofocus: true,
                      onKeyEvent: (node, event) =>
                          _handleKey(event),
                      child: Listener(
                        onPointerSignal: _handlePointerSignal, // колесо мыши / трекпад
                        child: PageView.builder(
                          controller: _pageCtrl,
                          physics: const PageScrollPhysics(),
                          allowImplicitScrolling: true, // lookahead для iOS/desktop
                          onPageChanged: (i) {
                            _currentIndex = i;
                            // откладываем тяжелую работу на следующий кадр
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
                      ),
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

class _EverywhereDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<ui.PointerDeviceKind> get dragDevices => <ui.PointerDeviceKind>{
    ui.PointerDeviceKind.touch,
    ui.PointerDeviceKind.mouse,
    ui.PointerDeviceKind.trackpad,
    ui.PointerDeviceKind.stylus,
    ui.PointerDeviceKind.unknown,
  };
}
