class NaturalCompletionGuard {
  static const Duration approachWindow = Duration(seconds: 3);

  int? _requestId;
  bool _approachObserved = false;
  bool _completionClaimed = false;

  void begin(int requestId) {
    _requestId = requestId;
    _approachObserved = false;
    _completionClaimed = false;
  }

  bool observe({
    required int requestId,
    required Duration position,
    required Duration duration,
    required Duration terminalOffset,
  }) {
    if (requestId != _requestId ||
        _completionClaimed ||
        duration <= Duration.zero) {
      return false;
    }

    final terminalAt = duration - terminalOffset;
    final approachAt = terminalAt - approachWindow;

    if (position < approachAt) {
      _approachObserved = false;
      return false;
    }

    if (position < terminalAt) {
      _approachObserved = true;
      return false;
    }

    if (!_approachObserved) return false;

    _completionClaimed = true;
    return true;
  }
}
