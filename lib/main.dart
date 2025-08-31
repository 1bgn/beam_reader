import 'package:beam_reader/di/injectable.dart';
import 'package:beam_reader/features/reader_screen/presentation/reader_screen.dart';
import 'package:flutter/material.dart';

void main() {
  configureDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(

      theme: ThemeData(


      ),
      home: ReaderScreen(),
    );
  }
}

