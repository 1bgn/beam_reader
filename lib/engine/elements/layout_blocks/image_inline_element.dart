import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'inline_element.dart';

/// Инлайн-картинка. Масштабируется под доступную ширину (maxWidth).
class ImageInlineElement extends InlineElement {
  final ui.Image image;
  final double? maxHeight;       // опционально: ограничение по высоте (px)
  final BorderRadius? radius;    // опционально: скругления

  ImageInlineElement({
    required this.image,
    this.maxHeight,
    this.radius,
  });

  @override
  void performLayout(double maxWidth) {
    final natW = image.width.toDouble();
    final natH = image.height.toDouble();

    double scale = 1.0;
    if (natW > 0) {
      scale = maxWidth / natW;
    }
    if (maxHeight != null && natH * scale > maxHeight!) {
      scale = maxHeight! / natH;
    }

    width = natW * scale;
    height = natH * scale;
    baseline = height; // базлайн под картинкой
  }

  @override
  void paint(ui.Canvas canvas, ui.Offset offset) {
    final dst = offset & Size(width, height);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

    if (radius != null && radius != BorderRadius.zero) {
      final rrect = RRect.fromRectAndCorners(
        dst,
        topLeft: radius!.topLeft,
        topRight: radius!.topRight,
        bottomLeft: radius!.bottomLeft,
        bottomRight: radius!.bottomRight,
      );
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawImageRect(image, src, dst, Paint());
      canvas.restore();
    } else {
      canvas.drawImageRect(image, src, dst, Paint());
    }
  }
}
