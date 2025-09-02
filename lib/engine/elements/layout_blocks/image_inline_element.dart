// lib/engine/elements/layout_blocks/image_inline_element.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'inline_element.dart';

class ImageInlineElement extends InlineElement {
  final ui.Image image;
  final double? maxHeight;
  final BorderRadius? radius;

  ImageInlineElement({
    required this.image,
    this.maxHeight,
    this.radius,
  });

  late Rect _dstRect;

  @override
  void performLayout(double maxWidth) {
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();

    // 1) Защита от "нулевой" ширины: если доступной ширины почти нет,
    //    возвращаем интринсик-размеры, чтобы переполнение точно сработало
    //    и движок перенёс картинку на новую строку (и перезалэйаутил её).
    const tiny = 1.0; // можно 0.5–2.0
    if (maxWidth <= tiny) {
      width = iw;
      height = ih;
      baseline = height;
      _dstRect = Rect.fromLTWH(0, 0, width, height);
      return;
    }

    double scale = iw > 0 ? (maxWidth / iw) : 1.0;
    double w = iw * scale;
    double h = ih * scale;

    if (maxHeight != null && h > maxHeight!) {
      final s = maxHeight! / h;
      w *= s;
      h *= s;
    }

    if (w < 0.5) w = 0.5;
    if (h < 0.5) h = 0.5;

    width = w;
    height = h;
    baseline = h; // картинка "сидит" на базовой линии
    _dstRect = Rect.fromLTWH(0, 0, w, h);
  }
  @override
  void paint(Canvas canvas, Offset offset) {
    final paint = Paint()..isAntiAlias = true;
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = _dstRect.shift(offset);

    // <-- ИСПРАВЛЕНО: проверяем BorderRadius, а не radius.x/y
    if (radius != null && radius != BorderRadius.zero) {
      final rrect = radius!.toRRect(dst);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawImageRect(image, src, dst, paint);
      canvas.restore();
    } else {
      canvas.drawImageRect(image, src, dst, paint);
    }
  }
}
