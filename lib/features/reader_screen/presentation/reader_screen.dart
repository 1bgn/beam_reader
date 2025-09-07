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

  // — Слайдер прогресса —
  double _progress = 0.0;
  bool _isSeeking = false;

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
      // если подошли к началу — лениво подгружаем прошлые
      _maybeExpandBefore().then((_) {
        _goTo(_currentIndex - 1);
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _maybeExpandBefore() async {
    // если уже есть запас слева — ничего не делаем
    if (_currentIndex > 0) return;

    // запросим у контроллера подгрузить, например, 3 страницы
    final added = await controller.lazyEnsurePrev(context, want: 3);
    if (added > 0 && mounted && _pageCtrl.hasClients) {
      // визуально остаёмся на той же странице — нужно сдвинуть контроллер
      final newIndex = _currentIndex + added;
      _pageCtrl.jumpToPage(newIndex);
      _currentIndex = newIndex;
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
      body: SafeArea(
        child: OrientationBuilder(
          builder: (ctx, orientation) {
            if (_lastOrientation != orientation) {
              _lastOrientation = orientation;

              // устойчивый якорь — начало абзаца
              final idAnchor = controller.idAnchorForPage(_currentIndex);

              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final newIndex = await controller.reflowFromId(
                  context,
                  keep: idAnchor,
                );
                if (!mounted) return;

                _pageCtrl.jumpToPage(newIndex);
                _currentIndex = newIndex;

                // сразу гарантируем запас вперёд
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  controller.ensurePage(context, newIndex + 1);
                  controller.prefetchAround(context, newIndex, radius: 2);
                  _syncSliderWithPage(newIndex);
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

                  return Stack(
                    children: [
                      // основной контент
                      Focus(
                        autofocus: true,
                        onKeyEvent: (node, event) => _handleKey(event),
                        child: PageView.builder(
                          controller: _pageCtrl,
                          physics: const PageScrollPhysics(),
                          allowImplicitScrolling: true,
                          onPageChanged: (i) async {
                            // если подошли к началу — подгрузим прошлые лениво
                            if (i <= 1) {
                              final added = await controller.lazyEnsurePrev(context, want: 3);
                              if (added > 0 && mounted && _pageCtrl.hasClients) {
                                // сдвигаем, чтобы остаться на той же визуальной странице
                                _pageCtrl.jumpToPage(i + added);
                                _currentIndex = i + added;
                                _syncSliderWithPage(_currentIndex);
                                return;
                              }
                            }

                            _currentIndex = i;
                            controller.ensurePage(context, i + 1);
                            controller.prefetchAround(context, i, radius: 2);
                            _syncSliderWithPage(i);
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

                      // прогресс-слайдер (не перекрывает текст: поверх, но с паддингом)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 8,
                        child: IgnorePointer(
                          ignoring: false,
                          child: Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: _isSeeking ? _progress : controller.pageStartProgress(_currentIndex),
                                  onChangeStart: (_) => setState(() => _isSeeking = true),
                                  onChanged: (v) => setState(() => _progress = v),
                                  onChangeEnd: (v) async {
                                    setState(() => _isSeeking = false);
                                    final newIndex = await controller.jumpToPercent(context, v);
                                    if (!mounted) return;
                                    _pageCtrl.jumpToPage(newIndex);
                                    _currentIndex = newIndex;

                                    // после прыжка — подгружаем вперёд и синхронизируем прогресс
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      controller.ensurePage(context, newIndex + 1);
                                      controller.prefetchAround(context, newIndex, radius: 2);
                                      _syncSliderWithPage(newIndex);
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(controller.pageStartProgress(_currentIndex) * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
