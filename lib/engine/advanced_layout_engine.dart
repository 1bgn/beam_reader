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
import 'elements/layout_blocks/line_break_inline_element.dart';
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
    final effectiveWidth = paragraph.maxWidth != null
        ? paragraph.maxWidth! * globalMaxWidth
        : globalMaxWidth;

    final splitted = _splitTokens(paragraph.inlineElements);
    final result = <LineLayout>[];

    var currentLine = LineLayout();
    double currentX = 0.0;
    double maxAscent = 0.0;
    double maxDescent = 0.0;
    bool isFirstLine = true;
    int runningOffset = startOffset;

    int _getElementTextLength(InlineElement elem) {
      if (elem is TextInlineElement) return elem.text.length;
      return 0;
    }

    void applyIndentIfNeeded() {
      if (isFirstLine &&
          paragraph.textDirection != TextDirection.rtl &&
          paragraph.enableRedLine &&
          paragraph.firstLineIndent > 0) {
        final indentElem =
        IndentInlineElement(indentWidth: paragraph.firstLineIndent)
          ..performLayout(paragraph.firstLineIndent);
        if (currentLine.elements.isEmpty) {
          currentLine.startTextOffset = runningOffset;
        }
        currentLine.elements.add(indentElem);
        currentX += paragraph.firstLineIndent;
      }
    }

    void commitLine({bool hardBreak = false}) {
      // Срезаем хвостовые чисто-пробельные токены, чтобы не учитывать их в width
      while (currentLine.elements.isNotEmpty) {
        final last = currentLine.elements.last;
        if (last is TextInlineElement && last.text.trim().isEmpty) {
          currentX -= last.width;
          currentLine.elements.removeLast();
        } else {
          break;
        }
      }

      // Финальные метрики
      currentLine.width = currentX;
      currentLine.maxAscent = maxAscent;
      currentLine.maxDescent = maxDescent;
      currentLine.height = maxAscent + maxDescent;

      currentLine.textAlign = paragraph.textAlign ?? globalTextAlign;
      currentLine.textDirection = paragraph.textDirection;

      // Контейнерное выравнивание (внутри колонки)
      if (paragraph.maxWidth != null && paragraph.containerAlignment != null) {
        final effectiveContainerWidth = globalMaxWidth * paragraph.maxWidth!;
        final extra = globalMaxWidth - effectiveContainerWidth;

        switch (paragraph.containerAlignment!) {
          case TextAlign.right:
            currentLine.containerOffset = extra;
            break;
          case TextAlign.center:
            currentLine.containerOffset = extra / 2;
            break;
          case TextAlign.left:
          case TextAlign.start:
          case TextAlign.end:
          case TextAlign.justify:
            currentLine.containerOffset = 0;
            break;
        }
        currentLine.containerOffsetFactor = paragraph.maxWidth!;
      } else {
        currentLine.containerOffset = 0;
        currentLine.containerOffsetFactor = 1.0;
      }

      // Флаги для justify
      currentLine.endsWithHardBreak = hardBreak;

      // Подсчёт обычных пробелов (U+0020) — для распределения в paint
      int gaps = 0;
      for (final e in currentLine.elements) {
        if (e is TextInlineElement) {
          final t = e.text;
          for (int i = 0; i < t.length; i++) {
            if (t.codeUnitAt(i) == 0x20) gaps++;
          }
        }
      }
      currentLine.spacesCount = gaps;

      // Сохраняем и сбрасываем
      result.add(currentLine);
      currentLine = LineLayout();
      currentX = 0.0;
      maxAscent = 0.0;
      maxDescent = 0.0;
      isFirstLine = false;
    }

    applyIndentIfNeeded();

    for (final elem in splitted) {
      // Жёсткий перенос строки (элемент-метка от токенайзера)
      if (elem is LineBreakInlineElement) {
        // Коммитим текущую строку как законченную жёстким переносом
        commitLine(hardBreak: true);
        applyIndentIfNeeded();
        continue;
      }

      final availableWidth = effectiveWidth - currentX;
      elem.performLayout(availableWidth);

      final overflow = currentX + elem.width > effectiveWidth;

      if (overflow) {
        if (elem is TextInlineElement) {
          // 1) Пытаемся мягкий перенос (дефис)
          final hyph =
          allowSoftHyphens ? _trySplitBySoftHyphen(elem, availableWidth) : null;

          if (hyph != null) {
            final left = hyph[0]..performLayout(availableWidth);
            if (currentLine.elements.isEmpty) {
              currentLine.startTextOffset = runningOffset;
            }
            currentLine.elements.add(left);
            currentX += left.width;
            maxAscent = math.max(maxAscent, left.baseline);
            maxDescent = math.max(maxDescent, left.height - left.baseline);
            runningOffset += _getElementTextLength(left);
            commitLine();

            final right = hyph[1]..performLayout(effectiveWidth);
            if (currentLine.elements.isEmpty) {
              currentLine.startTextOffset = runningOffset;
            }
            currentLine.elements.add(right);
            currentX = right.width;
            maxAscent = math.max(maxAscent, right.baseline);
            maxDescent = math.max(maxDescent, right.height - right.baseline);
            runningOffset += _getElementTextLength(right);
            continue;
          }

          // 2) Если слово не влезает и строка пустая — жёстко режем по ширине
          if (currentLine.elements.isEmpty) {
            final split = _forceSplitByWidth(elem, effectiveWidth);
            if (split != null) {
              final left = split.$1..performLayout(effectiveWidth);
              currentLine.startTextOffset = runningOffset;
              currentLine.elements.add(left);
              currentX += left.width;
              maxAscent = math.max(maxAscent, left.baseline);
              maxDescent = math.max(maxDescent, left.height - left.baseline);
              runningOffset += _getElementTextLength(left);
              commitLine();

              final right = split.$2..performLayout(effectiveWidth);
              currentLine.startTextOffset = runningOffset;
              currentLine.elements.add(right);
              currentX = right.width;
              maxAscent = math.max(maxAscent, right.baseline);
              maxDescent = math.max(maxDescent, right.height - right.baseline);
              runningOffset += _getElementTextLength(right);
              continue;
            }
          }
        }

        // 3) Обычный перенос на новую строку
        commitLine();
        elem.performLayout(effectiveWidth);
        if (currentLine.elements.isEmpty) {
          currentLine.startTextOffset = runningOffset;
        }
        currentLine.elements.add(elem);
        currentX = elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxDescent, elem.height - elem.baseline);
        runningOffset += _getElementTextLength(elem);
      } else {
        // Влезает целиком
        if (currentLine.elements.isEmpty) {
          currentLine.startTextOffset = runningOffset;
        }
        currentLine.elements.add(elem);
        currentX += elem.width;
        maxAscent = math.max(maxAscent, elem.baseline);
        maxDescent = math.max(maxDescent, elem.height - elem.baseline);
        runningOffset += _getElementTextLength(elem);
      }
    }

    // Докатываем последнюю строку
    if (currentLine.elements.isNotEmpty) {
      commitLine();
    }

    // RTL: переворачиваем порядок элементов в каждой строке
    if (paragraph.textDirection == TextDirection.rtl) {
      for (final line in result) {
        line.elements = line.elements.reversed.toList();
      }
    }

    // Последняя строка абзаца не должна растягиваться (для justify)
    if (result.isNotEmpty) {
      result.last.isSectionEnd = true;
    }

    return result;
  }



  (TextInlineElement, TextInlineElement)? _forceSplitByWidth(
      TextInlineElement e, double maxWidth) {
    final s = e.text;
    if (s.isEmpty) return null;
    int lo = 1, hi = s.length, best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final test = TextInlineElement(text: s.substring(0, mid), style: e.style);
      test.performLayout(maxWidth);
      if (test.width <= maxWidth) { best = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    if (best == 0) return null;
    return (
    TextInlineElement(text: s.substring(0, best), style: e.style),
    TextInlineElement(text: s.substring(best), style: e.style),
    );
  }
  List<InlineElement> _splitTokens(List<InlineElement> elements) {
    final out = <InlineElement>[];

    for (final e in elements) {
      if (e is! TextInlineElement) {
        out.add(e);
        continue;
      }

      // Сохраняем явные переводы строк
      final lines = e.text.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final chunk = lines[i];
        if (chunk.isNotEmpty) {
          // Берём либо непробельные, либо последовательности пробелов
          final matches = RegExp(r'\S+|\s+').allMatches(chunk);

          String? bufferedWord; // слово без следующих за ним пробелов
          for (final m in matches) {
            final token = m.group(0)!;
            final isSpace = token.trim().isEmpty;

            if (isSpace) {
              if (bufferedWord != null) {
                // привязываем пробел(ы) к предыдущему слову
                out.add(TextInlineElement(text: bufferedWord + token, style: e.style));
                bufferedWord = null;
              } else {
                // ведущие/множественные пробелы — отдельным элементом
                out.add(TextInlineElement(text: token, style: e.style));
              }
            } else {
              // встретили слово; если в буфере было предыдущее — выгружаем его
              if (bufferedWord != null) {
                out.add(TextInlineElement(text: bufferedWord, style: e.style));
              }
              bufferedWord = token;
            }
          }

          // «хвост» без завершающих пробелов
          if (bufferedWord != null) {
            out.add(TextInlineElement(text: bufferedWord, style: e.style));
            bufferedWord = null;
          }
        }

        if (i != lines.length - 1) {
          out.add(LineBreakInlineElement());
        }
      }
    }

    return out;
  }

  List<TextInlineElement>? _trySplitBySoftHyphen(
      TextInlineElement elem, double remainingWidth) {

    final full = elem.text;

    // Сохраняем хвостовые пробелы, чтобы они не пропали при дефисовании
    final trailingMatch = RegExp(r'\s+$').firstMatch(full);
    final trailingWs = trailingMatch?.group(0) ?? '';
    final core = trailingWs.isEmpty ? full : full.substring(0, full.length - trailingWs.length);

    final hyphCore = hyphenator.hyphenate(core);
    final positions = <int>[];

    for (int i = 0; i < hyphCore.length; i++) {
      if (hyphCore.codeUnitAt(i) == 0x00AD) positions.add(i);
    }
    if (positions.isEmpty) return null;

    for (int i = positions.length - 1; i >= 0; i--) {
      final idx = positions[i];
      if (idx < hyphCore.length - 1) {
        final leftStr  = hyphCore.substring(0, idx) + '-';
        final rightStr = hyphCore.substring(idx + 1) + trailingWs;

        final test = TextInlineElement(text: leftStr, style: elem.style)..performLayout(remainingWidth);
        if (test.width <= remainingWidth) {
          return [
            TextInlineElement(text: leftStr,  style: elem.style),
            TextInlineElement(text: rightStr, style: elem.style),
          ];
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