import 'dart:async';
import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
  static const double _sliderBarHeight = 60;

  static const _kAnimDuration = Duration(milliseconds: 180);
  bool _isAnimating = false;

  double _progress = 0.0;
  bool _isSeeking = false;

  // только для isScrollingNotifier
  bool _settleRunning = false;
  bool _ignorePageChanged = false;

  @override
  void initState() {
    super.initState();
    controller.init(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _waitForAttach();
      _attachScrollSettleListener();
      controller.prefetchAround(context, _currentIndex);
      _syncSliderWithPage(_currentIndex);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _waitForAttach();
      _attachScrollSettleListener();
    });
  }

  @override
  void dispose() {
    // попытка снять слушатель — безопасно обёрнута
    try {
      _pageCtrl.position.isScrollingNotifier.removeListener(_onScrollSettleChanged);
    } catch (_) {}
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Дожидаемся, пока PageController прикрепится к PageView (появится позиция)
  Future<void> _waitForAttach() async {
    while (mounted && !_pageCtrl.hasClients) {
      // ждём конец кадра; обычно хватает 1–2 итераций
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  void _attachScrollSettleListener() {
    // снимаем старый, чтобы не плодить слушателей
    try {
      _pageCtrl.position.isScrollingNotifier.removeListener(_onScrollSettleChanged);
    } catch (_) {}
    _pageCtrl.position.isScrollingNotifier.addListener(_onScrollSettleChanged);
  }

  void _onScrollSettleChanged() {
    // интересует момент полной остановки анимации/жеста
    if (!_pageCtrl.position.isScrollingNotifier.value) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _onSettle();
      });
    }
  }

  Future<void> _onSettle() async {
    if (_settleRunning || !mounted) return;
    _settleRunning = true;
    try {
      await _waitForAttach();

      // если у начала — пытаемся расшириться влево
      if (_currentIndex <= 1) {
        final added = await controller.lazyEnsurePrev(context, want: 3);
        if (added > 0 && mounted) {
          _ignorePageChanged = true;
          _pageCtrl.jumpToPage(_currentIndex + added);
          _currentIndex = _currentIndex + added;
          _syncSliderWithPage(_currentIndex);
          await SchedulerBinding.instance.endOfFrame;
          _ignorePageChanged = false;
        }
      }

      // и всегда готовим страницы вперёд
      controller.ensureAhead(context, _currentIndex, ahead: 4);
    } finally {
      _settleRunning = false;
    }
  }

  Future<void> _goTo(int target) async {
    final total = controller.totalPages.value;
    if (target < 0 || target >= total) return;
    if (_isAnimating) return;

    _isAnimating = true;
    controller.ensureAhead(context, target, ahead: 3); // лёгкая подготовка

    try {
      await _waitForAttach();
      await _pageCtrl.animateToPage(
        target,
        duration: _kAnimDuration,
        curve: Curves.easeOutCubic,
      );
      // дальнейшую подгрузку вызовет _onSettle() через isScrollingNotifier
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

  Future<void> _maybeExpandBefore() async {
    if (_currentIndex > 1) return;
    final added = await controller.lazyEnsurePrev(context, want: 3);
    if (added > 0 && mounted) {
      _ignorePageChanged = true;
      await _waitForAttach();
      _pageCtrl.jumpToPage(_currentIndex + added);
      _currentIndex = _currentIndex + added;
      _syncSliderWithPage(_currentIndex);
      await SchedulerBinding.instance.endOfFrame;
      _ignorePageChanged = false;
      setState(() {});
    }
  }

  void _syncSliderWithPage(int pageIndex) {
    final p = controller.pageStartProgress(pageIndex);
    setState(() => _progress = p);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const SafeArea(top: true, bottom: false, left: false, right: false, child: SizedBox.shrink()),
          Expanded(
            child: OrientationBuilder(
              builder: (ctx, orientation) {
                if (_lastOrientation != orientation) {
                  _lastOrientation = orientation;
                  final idAnchor = controller.idAnchorForPage(_currentIndex);

                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    final newIndex = await controller.reflowFromId(
                      context,
                      keep: idAnchor,
                    );
                    if (!mounted) return;

                    _ignorePageChanged = true;
                    await _waitForAttach();
                    _pageCtrl.jumpToPage(newIndex);
                    _currentIndex = newIndex;
                    _syncSliderWithPage(newIndex);
                    await SchedulerBinding.instance.endOfFrame;
                    _ignorePageChanged = false;

                    // подгрузка сработает на settle
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

                      return Focus(
                        autofocus: true,
                        onKeyEvent: (node, event) => _handleKey(event),
                        child: PageView.builder(
                          controller: _pageCtrl,
                          physics: const PageScrollPhysics(),
                          allowImplicitScrolling: true,
                          onPageChanged: (i) {
                            if (_ignorePageChanged) return;
                            _currentIndex = i;
                            _syncSliderWithPage(i);
                            // загрузку делаем только после полного settle через isScrollingNotifier
                          },
                          itemCount: total,
                          itemBuilder: (ctx, index) {
                            final layout = controller.getPage(index);
                            final pad = _contentPad;

                            if (layout == null) {
                              return Padding(
                                padding: pad,
                                child: const _KeptAlive(
                                  child: RepaintBoundary(
                                    child: ColoredBox(color: Colors.white),
                                  ),
                                ),
                              );
                            }

                            final page = _buildPageFromLayout(
                              safeSize,
                              layout,
                              pad,
                            );

                            return Padding(
                              padding: pad,
                              child: _KeptAlive(
                                child: RepaintBoundary(
                                  child: SizedBox.expand(
                                    child: SinglePageView(
                                      page: page,
                                      lineSpacing: 0,
                                      allowSoftHyphens: true,
                                    ),
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
          // SafeArea(
          //   top: false,
          //   bottom: true,
          //   left: false,
          //   right: false,
          //   child: SizedBox(
          //     height: _sliderBarHeight,
          //     child: Padding(
          //       padding: const EdgeInsets.symmetric(horizontal: 16),
          //       child: Row(
          //         children: [
          //           Expanded(
          //             child: Slider(
          //               value: _isSeeking
          //                   ? _progress
          //                   : controller.pageStartProgress(_currentIndex),
          //               onChangeStart: (_) => setState(() => _isSeeking = true),
          //               onChanged: (v) => setState(() => _progress = v),
          //               onChangeEnd: (v) async {
          //                 setState(() => _isSeeking = false);
          //                 final newIndex =
          //                 await controller.jumpToPercent(context, v);
          //                 if (!mounted) return;
          //
          //                 _ignorePageChanged = true;
          //                 await _waitForAttach();
          //                 _pageCtrl.jumpToPage(newIndex);
          //                 _currentIndex = newIndex;
          //                 _syncSliderWithPage(newIndex);
          //                 await SchedulerBinding.instance.endOfFrame;
          //                 _ignorePageChanged = false;
          //
          //                 // остальное — через _onSettle()
          //               },
          //             ),
          //           ),
          //           const SizedBox(width: 8),
          //           Text(
          //             '${(controller.pageStartProgress(_currentIndex) * 100).toStringAsFixed(0)}%',
          //             style: const TextStyle(fontSize: 12),
          //           ),
          //         ],
          //       ),
          //     ),
          //   ),
          // ),
        ],
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

/// Оставляем keep-alive, чтобы PageView не уничтожал виджет сразу после ухода
class _KeptAlive extends StatefulWidget {
  final Widget child;
  const _KeptAlive({required this.child});

  @override
  State<_KeptAlive> createState() => _KeptAliveState();
}

class _KeptAliveState extends State<_KeptAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
