// lib/engine/fb2_style_map.dart
import 'package:flutter/material.dart' hide InlineSpan;

import 'data_blocks/inline_text.dart';
import 'data_blocks/text_run.dart';
import 'layout_blocks/inline_element.dart';
import 'layout_blocks/text_inline_element.dart';

class BlockRenderStyle {
  final TextStyle textStyle;
  final TextAlign textAlign;
  final double firstLineIndent;
  final double paragraphSpacing;
  final bool enableRedLine;
  final TextAlign? containerAlign;
  final double? containerWidthFactor;

  const BlockRenderStyle({
    required this.textStyle,
    this.textAlign = TextAlign.start,
    this.firstLineIndent = 0,
    this.paragraphSpacing = 8,
    this.enableRedLine = false,
    this.containerAlign,
    this.containerWidthFactor,
  });
}

/// Маппинг FB2-тега → визуальные параметры.
/// depth влияет на масштаб заголовков в подразделах.
BlockRenderStyle fb2BlockRenderStyle({
  required String tag,
  required int depth,
  required double baseFontSize,
  required double lineHeight,
  Color color = Colors.black,
}) {
  final base = TextStyle(
    color: color,
    fontSize: baseFontSize,
    height: lineHeight,
  );

  switch (tag) {
    case 'title': {
      final d = depth.clamp(0, 3);
      final scale = 1.35 - d * 0.10; // 1.35, 1.25, 1.15, 1.05
      return BlockRenderStyle(
        textStyle: base.copyWith(
          fontSize: baseFontSize * scale,
          fontWeight: FontWeight.w700,
          height: lineHeight * 0.95,
        ),
        textAlign: TextAlign.center,
        paragraphSpacing: 14,
      );
    }
    case 'subtitle':
      return BlockRenderStyle(
        textStyle: base.copyWith(
          fontSize: baseFontSize * 1.15,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
        paragraphSpacing: 10,
      );

    case 'text-author':
      return BlockRenderStyle(
        textStyle: base.copyWith(fontStyle: FontStyle.italic),
        textAlign: TextAlign.right,
        paragraphSpacing: 12,
      );

  // Висячая первая строка: отрицательный indent уводит 1-ю строку влево,
  // контейнер делаем чуть уже (визуально отделяет от основного текста).
    case 'epigraph':
      return BlockRenderStyle(
        textStyle: base.copyWith(fontStyle: FontStyle.italic),
        textAlign: TextAlign.start,
        enableRedLine: true,
        firstLineIndent: -18,          // ← висячая строка
        paragraphSpacing: 12,
        containerAlign: TextAlign.center,
        containerWidthFactor: 0.9,
      );

    case 'cite':
      return BlockRenderStyle(
        textStyle: base.copyWith(fontStyle: FontStyle.italic),
        textAlign: TextAlign.start,
        paragraphSpacing: 10,
        containerAlign: TextAlign.center,
        containerWidthFactor: 0.92,
      );

  // Поэзия/строфы — компактнее, малая «красная строка»
    case 'poem':
    case 'stanza':
    case 'v':
      return BlockRenderStyle(
        textStyle: base,
        textAlign: TextAlign.start,
        firstLineIndent: 16,
        paragraphSpacing: 6,           // меньше отступ между строками-абзацами
        enableRedLine: true,
      );

  // Служебные
    case 'annotation':
      return BlockRenderStyle(
        textStyle: base.copyWith(
          fontSize: baseFontSize * 0.92,
          fontStyle: FontStyle.italic,
          color: Colors.black87,
        ),
        textAlign: TextAlign.start,
        paragraphSpacing: 10,
      );

  // Изображение центрируем контейнером
    case 'image':
      return BlockRenderStyle(
        textStyle: base,
        textAlign: TextAlign.center,
        paragraphSpacing: 12,
        containerAlign: TextAlign.center,
      );

    case 'empty-line':
      return BlockRenderStyle(
        textStyle: base,
        paragraphSpacing: baseFontSize * lineHeight * 0.7,
      );

  // Обычный текст — по ширине с красной строкой
    case 'p':
    default:
      return BlockRenderStyle(
        textStyle: base,
        textAlign: TextAlign.justify,
        paragraphSpacing: 10,
        firstLineIndent: 24,
        enableRedLine: true,
      );
  }
}

/// Конвертация инлайнов FB2 → плоские InlineElement с учётом вложенных стилей.
List<InlineElement> buildInlineElements(
    List<InlineText> nodes,
    TextStyle base,
    ) {
  final out = <InlineElement>[];

  void visit(InlineText n, TextStyle cur) {
    if (n is TextRun) {
      if (n.text.isNotEmpty) out.add(TextInlineElement(text: n.text, style: cur));
      return;
    }
    if (n is InlineSpan) {
      var s = cur;
      switch (n.tag) {
        case 'strong':
          s = s.copyWith(fontWeight: FontWeight.w700);
          break;
        case 'emphasis':
          s = s.copyWith(fontStyle: FontStyle.italic);
          break;
        case 'a':
          s = s.copyWith(color: Colors.blueAccent, decoration: TextDecoration.underline);
          break;
        case 'code':
          s = s.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0x11000000));
          break;
        case 'strikethrough':
          s = s.copyWith(decoration: TextDecoration.lineThrough);
          break;
        case 'sub':
        case 'sup':
          s = s.copyWith(
            fontSize: (s.fontSize ?? base.fontSize ?? 14) * 0.85,
            height: (s.height ?? 1.2) * 0.95,
          );
          break;
        case 'date':
          s = s.copyWith(color: Colors.black54, fontStyle: FontStyle.italic);
          break;
      // 'style' и др. — без изменений
      }
      for (final c in n.children) visit(c, s);
      return;
    }
    // нераспознанное — как есть
    out.add(TextInlineElement(text: n.toString(), style: cur));
  }

  for (final n in nodes) visit(n, base);
  return out;
}
