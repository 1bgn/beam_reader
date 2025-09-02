abstract class ElementText {
  /// Путь тегов от корня до этого узла (например: [section, epigraph, text-author])
  final List<String> path;

  /// Атрибуты исходного узла (href у <a>, name у <style> и т. п.)
  final Map<String, String> attrs;

  const ElementText({
    required this.path,
    this.attrs = const {},
  });

  /// Имя тега этого узла (для текстовых узлов — "#text")
  String get tag;
}