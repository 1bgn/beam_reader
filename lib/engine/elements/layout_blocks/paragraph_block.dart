import 'package:beam_reader/engine/elements/layout_blocks/inline_element.dart';
import 'package:flutter/material.dart';

class ParagraphBlock {
  final List<InlineElement> inlineElements;
  final TextAlign? textAlign;
  final TextDirection textDirection;
  final double firstLineIndent;
  final double paragraphSpacing;
  final int minimumLines;
  final double? maxWidth;
  final bool isSectionEnd;
  final bool breakable;
  final bool enableRedLine;
  final TextAlign? containerAlignment;

  ParagraphBlock({
    required this.inlineElements,
     this.textAlign,
     this.textDirection = TextDirection.ltr,
     this.firstLineIndent = 0,
     this.paragraphSpacing = 0,
     this.minimumLines = 1,
     this.maxWidth,
     this.isSectionEnd = false,
     this.breakable = false,
     this.enableRedLine = true,
     this.containerAlignment,
  });
  ParagraphBlock copyWith({
    List<InlineElement>? inlineElements,
    TextAlign? textAlign,
    TextDirection? textDirection,
    double? firstLineIndent,
    double? paragraphSpacing,
    int? minimumLines,
    double? maxWidth,
    bool? isSectionEnd,
    bool? breakable,
    bool? enableRedLine,
    TextAlign? containerAlignment,
  }) {
    return ParagraphBlock(
      inlineElements: inlineElements ?? this.inlineElements,
      textAlign: textAlign ?? this.textAlign,
      textDirection: textDirection ?? this.textDirection,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      minimumLines: minimumLines ?? this.minimumLines,
      maxWidth: maxWidth ?? this.maxWidth,
      isSectionEnd: isSectionEnd ?? this.isSectionEnd,
      breakable: breakable ?? this.breakable,
      enableRedLine: enableRedLine ?? this.enableRedLine,
      containerAlignment: containerAlignment ?? this.containerAlignment,
    );
  }
}
