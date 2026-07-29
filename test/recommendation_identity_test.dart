import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/recommendation_item.dart';

void main() {
  MediaItem song(String id, String title, String artist) {
    return MediaItem(id: id, title: title, artist: artist);
  }

  test('canonical identity deduplicates alternate uploads', () {
    final official = song('video-a', 'Signal (Official Audio)', 'Nova feat. K');
    final plain = song('video-b', 'Signal', 'Nova');

    expect(RecommendationMediaJson.sameSong(official, plain), isTrue);
    expect(
      RecommendationMediaJson.normalizedPrimaryArtist(official),
      'nova',
    );
  });

  test('detects noisy versions even when marker is in brackets', () {
    expect(
      RecommendationMediaJson.hasNoisyVersionMarker(
        song('live', 'Signal (Live)', 'Nova'),
      ),
      isTrue,
    );
    expect(
      RecommendationMediaJson.hasNoisyVersionMarker(
        song('remix', 'Signal [Remix]', 'Nova'),
      ),
      isTrue,
    );
    expect(
      RecommendationMediaJson.hasNoisyVersionMarker(
        song('official', 'Signal (Official Audio)', 'Nova'),
      ),
      isFalse,
    );
  });

  test('does not treat marker words inside legitimate titles as versions', () {
    expect(
      RecommendationMediaJson.hasNoisyVersionMarker(
        song('live', 'I Live for You', 'Nova'),
      ),
      isFalse,
    );
    expect(
      RecommendationMediaJson.hasNoisyVersionMarker(
        song('cover', 'Cover Me', 'Nova'),
      ),
      isFalse,
    );
  });

  test('detects bracketed and suffixed noisy versions', () {
    final titles = [
      'Signal - Live',
      'Signal (Dance Remix)',
      'Signal [Acoustic Cover]',
      'Signal - Karaoke',
      'Signal (Sped Up)',
      'Signal - Slowed',
      'Signal [Nightcore]',
    ];

    for (final title in titles) {
      expect(
        RecommendationMediaJson.hasNoisyVersionMarker(
          song(title, title, 'Nova'),
        ),
        isTrue,
        reason: title,
      );
    }
  });

  test('normalization preserves letters and numbers across scripts', () {
    expect(
      RecommendationMediaJson.normalizedText(
        '東京 الموسيقى संगीत Українська Љубав ۱۲۳',
      ),
      '東京 الموسيقى संगीत українська љубав ۱۲۳',
    );
  });

  test('station term matching respects word boundaries', () {
    expect(
      RecommendationMediaJson.containsNormalizedTerm('rocket launch', 'rock'),
      isFalse,
    );
    expect(
      RecommendationMediaJson.containsNormalizedTerm(
          'hard rock anthem', 'rock'),
      isTrue,
    );
  });
}
