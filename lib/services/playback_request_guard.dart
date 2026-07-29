class PlaybackRequestGuard {
  int _generation = 0;

  int begin() => ++_generation;

  void cancel() {
    _generation++;
  }

  bool matches(int requestId) => requestId == _generation;
}
