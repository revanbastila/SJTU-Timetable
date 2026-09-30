/// Invalidates asynchronous login work when a user starts browser navigation.
class WebNavigationGuard {
  int _generation = 0;

  int get generation => _generation;

  void invalidate() => _generation++;

  bool permits(int generation, {required bool returning}) =>
      generation == _generation && !returning;
}
