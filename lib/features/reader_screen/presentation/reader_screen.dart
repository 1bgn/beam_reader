// lib/features/reader_screen/presentation/paged_reader_screen.dart
import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  int _current = 0;
  int _lastPrefetched = -1;

  @override
  void initState() {
    super.initState();
    controller.init(context);
  }

  void _schedulePrefetch(int i) {
    if (_lastPrefetched == i) return;
    _lastPrefetched = i;
    // дождаться завершения кадра, чтобы не дергать раскладку в тот же тик
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.prefetchAround(context, i); // ensurePage внутри уже дедуплит
    });
  }

  bool _onScrollNotif(ScrollNotification n) {
    // интересуют только «остановки»
    if (n is ScrollEndNotification || (n is UserScrollNotification && n.direction == ScrollDirection.idle)) {
      final raw = _pageCtrl.page ?? _current.toDouble();
      final idx = raw.round();
      // защелкнулся на целую страницу
      if ((raw - idx).abs() < 0.0001) {
        _current = idx;
        _schedulePrefetch(idx);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Watch((ctx) {
        final total = controller.totalPages.value;
        if (total == 0) {
          return const Center(child: CircularProgressIndicator());
        }

        return NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotif,
          child: PageView.builder(
            controller: _pageCtrl,
            // Важно: убираем префетч из onPageChanged — пусть только фикс на центре триггерит
            onPageChanged: (i) => _current = i,
            itemCount: total,
            itemBuilder: (ctx, index) {

              final size = MediaQuery.of(ctx).size;
              const pagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 28);
              final usableWidth  = size.width  - pagePadding.horizontal;
              final usableHeight = size.height - pagePadding.vertical;

              final layout = controller.getPage(index);
              if (layout == null) {
                controller.ensurePage(context, index);
                return const Center(child: CircularProgressIndicator());
              }

// ВАЖНО: колонка = usableWidth
              final page = MultiColumnPage(
                columns: [layout.lines],
                pageWidth: usableWidth,
                pageHeight: usableHeight,
                columnWidth: usableWidth,
                columnSpacing: 0,
              );

              return Padding(
                padding: pagePadding,
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
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }
}

