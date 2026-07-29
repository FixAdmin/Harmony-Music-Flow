class PlaybackSignalGate {
  static const _requiredPlayback = Duration(seconds: 5);
  static const _maxPlausibleStep = Duration(seconds: 5);

  String? _songId;
  Object? _playbackSessionId;
  bool _playStartRecorded = false;
  bool _completedRecorded = false;
  bool _skipRecorded = false;
  Duration? _lastPosition;
  Duration _plausiblePlayback = Duration.zero;

  String? get songId => _songId;
  bool get playStartRecorded => _playStartRecorded;

  void begin(String songId, {Object? playbackSessionId}) {
    final songChanged = _songId != songId;
    final sessionChanged = !songChanged &&
        playbackSessionId != null &&
        playbackSessionId != _playbackSessionId;
    if (!songChanged && !sessionChanged) return;

    _songId = songId;
    _playbackSessionId = playbackSessionId;
    _playStartRecorded = false;
    _completedRecorded = false;
    _skipRecorded = false;
    _lastPosition = null;
    _plausiblePlayback = Duration.zero;
  }

  bool shouldRecordPlayStart(Duration position, {required bool isPlaying}) {
    if (_songId == null || _playStartRecorded) return false;

    final previous = _lastPosition;
    _lastPosition = position;
    if (!isPlaying || previous == null) return false;

    final step = position - previous;
    if (step <= Duration.zero || step > _maxPlausibleStep) {
      return false;
    }

    _plausiblePlayback += step;
    if (_plausiblePlayback < _requiredPlayback) return false;
    _playStartRecorded = true;
    return true;
  }

  bool shouldRecordCompletion(Duration position, Duration total) {
    if (_songId == null ||
        !_playStartRecorded ||
        _completedRecorded ||
        total.inMilliseconds <= 0) {
      return false;
    }
    if (position.inMilliseconds / total.inMilliseconds < .7) return false;
    _completedRecorded = true;
    return true;
  }

  bool shouldRecordEarlySkip(Duration position, Duration total) {
    if (_songId == null ||
        !_playStartRecorded ||
        _skipRecorded ||
        _completedRecorded ||
        total.inMilliseconds <= 0 ||
        position < const Duration(seconds: 5)) {
      return false;
    }
    final progress = position.inMilliseconds / total.inMilliseconds;
    if (position > const Duration(seconds: 30) && progress > .2) {
      return false;
    }
    _skipRecorded = true;
    return true;
  }
}
