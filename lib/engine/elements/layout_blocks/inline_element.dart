import 'dart:ui';
import 'dart:ui' as ui;

abstract class InlineElement {
  double width = 0.0;
  double height = 0.0;
  double baseline = 0.0;

  /// Прямоугольники (для выделения, интерактивности).
  List<Rect> selectionRects = [];

  /// Вычисляет размеры элемента при заданной максимальной ширине.
  void performLayout(double maxWidth);

  /// Рисует элемент на [canvas] по указанным координатам.
  void paint(ui.Canvas canvas, Offset offset);

  // /// Возвращает зоны интерактивности (например, для ссылок).
  // List<Rect> getInteractiveRects(Offset offset) => [];
}