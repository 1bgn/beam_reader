// lib/features/reader_screen/presentation/reader_screen.dart
import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/features/reader_screen/appication/reader_screen_controller.dart';

import 'package:beam_reader/features/reader_screen/presentation/widgets/paged_view_reader.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ReaderScreenController controller = getIt();

  @override
  void initState() {
    super.initState();
    controller.buildBook(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Watch((context) {
        final layout = controller.textLayout.value;
        if (layout == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: PagedReaderView(
              layout: layout,
              columnsPerPage: 1,      // сделай 2/3 — будет много колонок на странице
              columnSpacing: 24,
              lineSpacing: 0,
              allowSoftHyphens: true,
              enableSelection: true,
              doubleTapSelectsWord: true,
              tripleTapSelectsLine: true,
              holdToSelect: true,
              clearSelectionOnSingleTap: true,
              onSelectionChanged: (s, e) {
                // например, показывать тулбар/копирование
              },
            ),
          ),
        );
      }),
    );
  }
}
