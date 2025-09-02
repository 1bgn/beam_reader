import 'dart:ui';
import 'dart:math' as math;

import 'package:beam_reader/engine/elements/layout_blocks/indent_inline_element.dart';
import 'package:beam_reader/engine/elements/layout_blocks/line_layout.dart';
import 'package:beam_reader/engine/elements/layout_blocks/multi_column_page.dart';
import 'package:beam_reader/engine/elements/layout_blocks/paragraph_block.dart';
import 'package:beam_reader/engine/elements/layout_blocks/text_inline_element.dart';
import 'package:injectable/injectable.dart';

import 'elements/data_blocks/inline_text.dart';
import 'elements/layout_blocks/custom_text_layout.dart';
import 'elements/layout_blocks/inline_element.dart';
import 'hyphenator.dart';


class AdvancedLayoutEngine{
  final  List<ParagraphBlock> paragraphs;
  final double globalMaxWidth;
  final TextAlign globalTextAlign;
  final Hyphenator hyphenator = Hyphenator();

  AdvancedLayoutEngine({required this.paragraphs,required this.globalMaxWidth,required this.globalTextAlign,this.allowSoftHyphens=true});

  final bool  allowSoftHyphens;

  CustomTextLayout layoutAllParagraphs() {
    final allLines = <LineLayout>[];
    final paragraphIndexOfLine = <int>[];
    double totalHeight = 0.0;
    int currentGlobalOffset = 0;

    for (int index = 0; index<paragraphs.length;index++) {
      final paragraph = paragraphs[index];
      if (paragraph.textAlign == TextAlign.right && allLines.isNotEmpty) {
        final breakLine = LineLayout();
        breakLine.startTextOffset = currentGlobalOffset;
        allLines.add(breakLine);
        paragraphIndexOfLine.add(index);
      }
      final lines = _layoutSingleParagraph(
          paragraph, startOffset: currentGlobalOffset);

      if (lines.length < paragraph.minimumLines) {
        final deficit = paragraph.minimumLines - lines.length;
        for (int i = 0; i < deficit; i++) {
          final emptyLine = LineLayout();
          emptyLine.width = 0;
          emptyLine.height = lines.isNotEmpty ? lines.last.height : 20;
          emptyLine.textDirection = paragraph.textDirection;
          emptyLine.startTextOffset = currentGlobalOffset;
          lines.add(emptyLine);
        }
      }
      for (int i = 0; i < lines.length; i++) {
        paragraphIndexOfLine.add(index);
      }
      allLines.addAll(lines);
      if (index < paragraphs.length - 1 && paragraph.paragraphSpacing > 0) {
        final spacingLine = LineLayout();
        spacingLine.width = 0;
        spacingLine.height = paragraph.paragraphSpacing;
        spacingLine.textAlign = paragraph.textAlign ?? globalTextAlign;
        spacingLine.textDirection = paragraph.textDirection;
        spacingLine.startTextOffset = currentGlobalOffset;
        allLines.add(spacingLine);
        paragraphIndexOfLine.add(index);
      }
      currentGlobalOffset += _countTextLength(paragraph.inlineElements);
      double paragraphHeight = 0.0;
      for (int i = 0;i<lines.length;i++){
        paragraphHeight += lines[i].height;
        if(i<lines.length-1){
          paragraphHeight += paragraph.paragraphSpacing;
        }
      }
      totalHeight += paragraphHeight;
      if(index<paragraphs.length-1){
        totalHeight += paragraph.paragraphSpacing;
      }
    }

      return CustomTextLayout(
        lines: allLines,
        totalHeight: totalHeight,
        paragraphIndexOfLine: paragraphIndexOfLine,
      );

  }
  List<LineLayout> _layoutSingleParagraph(
      ParagraphBlock paragraph, {
        required int startOffset,
      }) {
    final effectiveWidth = paragraph.maxWidth!=null?paragraph.maxWidth!*globalMaxWidth:globalMaxWidth;
    final splitted = _splitTokens(paragraph.inlineElements);
    final result= <LineLayout>[];

    var currentLine = LineLayout();
    double currentX = 0.0;
    double maxAscent = 0.0;
    double maxDescent = 0.0;
    bool isFirstLine = true;
    int runningOffset = startOffset;

    int _getElementTextLength(InlineElement elem) {
      if (elem is TextInlineElement) {
        return elem.text.length;
      }
      return 0;
    }
    void applyIndentIfNeeded(){
      if(isFirstLine && paragraph.textDirection !=TextDirection.rtl && paragraph.enableRedLine && paragraph.firstLineIndent>0){
        final indentElem = IndentInlineElement(indentWidth: paragraph.firstLineIndent);
        indentElem.performLayout(paragraph.firstLineIndent);
        if(currentLine.elements.isEmpty){
          currentLine.startTextOffset = runningOffset;
        }
        currentLine.elements.add(indentElem);
        currentX += paragraph.firstLineIndent;
      }
    }
    void commitLine(){
      currentLine.width = currentX;
      currentLine.maxAscent = maxAscent;
      currentLine.maxDescent = maxDescent;
      currentLine.height = maxAscent+maxDescent;
      currentLine.textAlign = paragraph.textAlign??globalTextAlign;
      currentLine.textDirection = paragraph.textDirection;

      if(paragraph.maxWidth !=null && paragraph.containerAlignment !=null){
        final effectiveContainerWidth = globalMaxWidth * paragraph.maxWidth!;
        final extra = globalMaxWidth - effectiveContainerWidth;
        switch(paragraph.containerAlignment!){


          case TextAlign.right:
            currentLine.containerOffset = extra;
          case TextAlign.center:
            currentLine.containerOffset = extra/2;
          default:
            currentLine.containerOffset = 0;
        }
        currentLine.containerOffsetFactor = paragraph.maxWidth!;
      }else{
        currentLine.containerOffset = 0;
        currentLine.containerOffsetFactor = 0;
      }
      result.add(currentLine);
      currentLine = LineLayout();
      currentX = 0.0;
      maxAscent = 0.0;
      maxDescent = 0.0;
      isFirstLine = false;
    }
    applyIndentIfNeeded();

    for(final elem in splitted) {
      double availableWidth = effectiveWidth - currentX;
      elem.performLayout(availableWidth);

      if (currentX + elem.width > effectiveWidth &&
          currentLine.elements.isNotEmpty) {
        if (elem is TextInlineElement && allowSoftHyphens) {
          final splittedPair = _trySplitBySoftHyphen(
              elem, effectiveWidth - currentX);
          if (splittedPair != null) {
            final leftPart = splittedPair[0];
            final rightPart = splittedPair[1];
            leftPart.performLayout(effectiveWidth - currentX);
            if (currentLine.elements.isEmpty) {
              currentLine.startTextOffset = runningOffset;
            }
            currentLine.elements.add(leftPart);
            currentX += leftPart.width;
            maxAscent = math.max(maxAscent, leftPart.baseline);
            maxDescent =
                math.max(maxAscent, leftPart.height - leftPart.baseline);
            runningOffset += _getElementTextLength(leftPart);
            commitLine();
            rightPart.performLayout(effectiveWidth);
            if (currentLine.elements.isEmpty) {
              currentLine.startTextOffset = runningOffset;
            }
            currentLine.elements.add(rightPart);
            currentX = rightPart.width;
            maxAscent = math.max(maxAscent, rightPart.baseline);
            maxDescent =
                math.max(maxAscent, rightPart.height - rightPart.baseline);
            runningOffset += _getElementTextLength(rightPart);
          }
        }
        else {
          commitLine();
          elem.performLayout(effectiveWidth);
          if (currentLine.elements.isEmpty) {
            currentLine.startTextOffset = runningOffset;
          }
          currentLine.elements.add(elem);
          currentX = elem.width;
          maxAscent = math.max(maxAscent, elem.baseline);
          maxDescent = math.max(maxAscent, elem.height - elem.baseline);
          runningOffset += _getElementTextLength(elem);
        }
      } else {
        if (currentLine.elements.isEmpty) {
          currentLine.startTextOffset = runningOffset;
        }
        currentLine.elements.add(elem);
        currentX += elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxAscent, elem.height - elem.baseline);
        runningOffset += _getElementTextLength(elem);
      }
    }
      if(currentLine.elements.isNotEmpty){
        commitLine();
      }
      if (paragraph.textDirection == TextDirection.rtl) {
        for (final line in result) {
          line.elements = line.elements.reversed.toList();
        }

    }
    return result;

  }



  List<InlineElement> _splitTokens(List<InlineElement> elements) {
    final result = <InlineElement>[];
    for (final e in elements){
      if(e is TextInlineElement){
        final tokens = e.text.split(RegExp(r'(\s+)'));
        for (final token in tokens){
          final isSpace = token.trim().isEmpty;
          if(isSpace){
            result.add(TextInlineElement(text: token, style: e.style));
          }else{
            result.add(TextInlineElement(text: "$token ", style: e.style));
          }
        }
      }
    }
    return result;
  }
  List<TextInlineElement>? _trySplitBySoftHyphen(TextInlineElement elem, double remainingWidth) {
    // final raw = elem.text;
    final raw = hyphenator.hyphenate(elem.text);
    final positions = <int>[];
    for (int i = 0;i<raw.length;i++){
      if(raw.codeUnitAt(i)==0x00AD){
        positions.add(i);
      }
    }
    if(positions.isEmpty){
      return null;
    }
    for (int i = positions.length-1;i>=0;i--){
      final idx = positions[i];
      if(idx < raw.length -1){
        final leftPart = raw.substring(0,idx)+'-';
        final rightPart = raw.substring(idx+1);
        final testElem = TextInlineElement(text: leftPart, style: elem.style);
        testElem.performLayout(remainingWidth);
        if(testElem.width <= remainingWidth){
          final leftOver = TextInlineElement(text: rightPart, style: elem.style);
          return [testElem,leftOver];
        }
      }
    }
    return null;
  }
  int _countTextLength(List<InlineElement> elements) {
    int total = 0;
    for (final elem in elements) {
      if (elem is TextInlineElement) {
        total += elem.text.length;
      }
      // else if (elem is InlineLinkElement) {
      //   total += elem.text.length;
      // }
    }
    return total;
  }

}