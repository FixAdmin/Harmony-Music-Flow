import 'package:audio_service/audio_service.dart';

class RecommendationCandidate {
  RecommendationCandidate({
    required this.item,
    required this.source,
    this.seedId,
    this.sourceScore = 1,
    this.sourceRank = 0,
  });

  final MediaItem item;
  final String source;
  final String? seedId;
  final double sourceScore;
  final int sourceRank;
}

class RecommendationMediaJson {
  static Map<String, dynamic> fromMediaItem(MediaItem item) {
    final artists = item.extras?['artists'];
    final thumbnails = item.artUri == null
        ? <Map<String, dynamic>>[]
        : [
            {'url': item.artUri.toString()}
          ];

    return {
      'videoId': item.id,
      'title': item.title,
      'album': item.extras?['album'] ??
          (item.album == null ? null : {'name': item.album}),
      'artists': artists is List
          ? artists
          : [
              {'name': item.artist ?? ''}
            ],
      'length': item.extras?['length'],
      'duration': item.duration?.inSeconds,
      'date': item.extras?['date'],
      'thumbnails': thumbnails,
      'url': item.extras?['url'],
      'trackDetails': item.extras?['trackDetails'],
      'year': item.extras?['year'],
      'recommendationSource': item.extras?['recommendationSource'],
      'recommendationScore': item.extras?['recommendationScore'],
      'recommendationReasonCodes': item.extras?['recommendationReasonCodes'],
    };
  }

  static String normalizedText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizedMarkerText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizedPrimaryArtist(MediaItem item) {
    return normalizedArtist(item.artist ?? '');
  }

  static String normalizedArtist(String artist) {
    return normalizedText(artist
        .split(RegExp(r'[,;&]|\s+feat\.?\s+', caseSensitive: false))
        .first);
  }

  static String normalizedSongKey(MediaItem item) {
    final artist = normalizedPrimaryArtist(item);
    final title = normalizedText(item.title);
    if (artist.isEmpty && title.isEmpty) return item.id.trim();
    return '$artist::$title';
  }

  static bool sameSong(MediaItem a, MediaItem b) {
    if (a.id.isNotEmpty && a.id == b.id) return true;
    final aKey = normalizedSongKey(a);
    return aKey.isNotEmpty && aKey == normalizedSongKey(b);
  }

  static bool containsNormalizedTerm(String normalizedTextValue, String term) {
    final normalizedTerm = normalizedText(term);
    if (normalizedTextValue.isEmpty || normalizedTerm.isEmpty) return false;
    return ' $normalizedTextValue '.contains(' $normalizedTerm ');
  }

  static double textSimilarity(String a, String b) {
    final normalizedA = normalizedText(a);
    final normalizedB = normalizedText(b);
    if (normalizedA.isEmpty || normalizedB.isEmpty) return 0;
    if (normalizedA == normalizedB) return 1;
    final tokensA = normalizedA.split(' ').toSet();
    final tokensB = normalizedB.split(' ').toSet();
    final shared = tokensA.intersection(tokensB).length;
    return shared / _max(tokensA.length, tokensB.length);
  }

  static int _max(int a, int b) => a > b ? a : b;

  static bool hasNoisyVersionMarker(MediaItem item) {
    final title = item.title;
    final bracketed = RegExp(r'[\(\[]([^\)\]]*)[\)\]]', unicode: true);
    for (final match in bracketed.allMatches(title)) {
      if (_containsVersionMarker(match.group(1) ?? '')) return true;
    }

    final delimitedSuffix = RegExp(
      r'(?:\s+-\s+|\s*[\u2013\u2014:]\s*)(.+)$',
      unicode: true,
    ).firstMatch(title);
    if (delimitedSuffix != null &&
        _containsVersionMarker(delimitedSuffix.group(1) ?? '')) {
      return true;
    }

    final normalizedTitle = normalizedMarkerText(title);
    return RegExp(
      r'(?:^| )(?:live|remix|cover|karaoke|nightcore|sped up|slowed(?: down)?)(?: version| edit| mix)?$',
      unicode: true,
    ).hasMatch(normalizedTitle);
  }

  static bool _containsVersionMarker(String value) {
    final normalized = normalizedMarkerText(value);
    return const [
      'live',
      'remix',
      'cover',
      'karaoke',
      'sped up',
      'slowed',
      'nightcore',
    ].any((marker) => containsNormalizedTerm(normalized, marker));
  }
}
