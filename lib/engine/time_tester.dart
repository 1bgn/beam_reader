abstract class Time{
  static Future<void> test(Function function) async {
    final start = DateTime.now();
    await function.call();
    final end = DateTime.now();
    final diff = end.difference(start);

    print('Время выполнения: ${diff.inMilliseconds} мс');
  }
}