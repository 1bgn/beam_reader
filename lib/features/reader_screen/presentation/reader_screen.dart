import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/features/reader_screen/appication/reader_screen_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ReaderScreen extends StatefulWidget{
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {

  final ReaderScreenController controller = getIt();

  @override
  void initState() {
    super.initState();
    controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text("Reader screen"),),);
  }
}