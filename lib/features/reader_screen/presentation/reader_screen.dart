import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/engine/elements/layout_blocks/custom_text_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/features/reader_screen/appication/reader_screen_controller.dart';
import 'package:beam_reader/features/reader_screen/presentation/reader_pager.dart';
import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_render_obj.dart';
import 'package:beam_reader/features/reader_screen/presentation/widgets/single_page_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

class ReaderScreen extends StatefulWidget {
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
      body: Watch(
              (context) {
            if (controller.textLayout.value != null) {
              return SingleChildScrollView(
                child: Column(
                  children: [Row(
                    children: [
                      SinglePageView(page: buildPage(controller.textLayout.value!), lineSpacing: 0, allowSoftHyphens: true),
                    ],
                  )],),
              );
            }
            return Center();
          }
      ),
    );
  }

  MultiColumnPage buildPage(CustomTextLayout customTextLayout) {
    return MultiColumnPage(columns: [customTextLayout.lines],
        pageWidth: MediaQuery
            .of(context)
            .size
            .width,
        pageHeight: MediaQuery
            .of(context)
            .size
            .height,
        columnWidth: MediaQuery
            .of(context)
            .size
            .width,
        columnSpacing: 0);
  }
}