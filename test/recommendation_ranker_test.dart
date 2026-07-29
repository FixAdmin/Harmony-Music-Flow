import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/models/taste_profile.dart';
import 'package:harmonymusic/services/recommendation/ranker.dart';

void main() {
  MediaItem song(String id, String title, String artist) {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      artUri: Uri.parse('https://example.com/$id.jpg'),
      extras: {
        'artists': [
          {'name': artist}
        ],
        'thumbnails': [
          {'url': 'https://example.com/$id.jpg'}
        ],
      },
    );
  }

  TasteProfile emptyProfile() {
    return TasteProfile(
      recentSeeds: const [],
      topArtists: const {},
      skippedArtists: const {},
      playedSongIds: const {},
      likedSongIds: const {},
      dismissedSongIds: const {},
    );
  }

  test('rank prefers fresh tracks from preferred artists', () {
    final likedArtist = song('new-a', 'Fresh Song', 'Known Artist');
    final played = song('played', 'Old Song', 'Known Artist');
    final dismissed = song('dismissed', 'Dismissed Song', 'Other Artist');

    final profile = TasteProfile(
      recentSeeds: [song('seed', 'Seed', 'Known Artist')],
      topArtists: {'Known Artist': 5},
      skippedArtists: {},
      playedSongIds: {'played'},
      likedSongIds: {},
      dismissedSongIds: {'dismissed'},
    );

    final ranked = RecommendationRanker().rank([
      RecommendationCandidate(item: played, source: 'youtube_radio'),
      RecommendationCandidate(item: dismissed, source: 'youtube_radio'),
      RecommendationCandidate(item: likedArtist, source: 'youtube_radio'),
    ], profile);

    expect(ranked.first.id, 'new-a');
    expect(ranked.any((item) => item.id == 'dismissed'), isFalse);
  });

  test('deduplicates alternate uploads and honors dismissed song keys', () {
    final original = song('a', 'Signal', 'Nova');
    final alternate = song('b', 'Signal (Official Audio)', 'Nova');
    final dismissedKey = RecommendationMediaJson.normalizedSongKey(original);
    final profile = TasteProfile(
      recentSeeds: const [],
      topArtists: const {},
      skippedArtists: const {},
      playedSongIds: const {},
      likedSongIds: const {},
      dismissedSongIds: const {},
      dismissedSongKeys: {dismissedKey},
    );

    final ranked = RecommendationRanker().rank([
      RecommendationCandidate(item: original, source: 'youtube_radio'),
      RecommendationCandidate(item: alternate, source: 'youtube_related'),
    ], profile);

    expect(ranked, isEmpty);
  });

  test('soft source caps keep related candidates in the final page', () {
    final candidates = <RecommendationCandidate>[
      for (var index = 0; index < 30; index++)
        RecommendationCandidate(
          item: song('radio-$index', 'Radio $index', 'Radio Artist $index'),
          source: 'youtube_radio',
          sourceScore: .9,
          sourceRank: index,
        ),
      for (var index = 0; index < 12; index++)
        RecommendationCandidate(
          item: song(
            'related-$index',
            'Related $index',
            'Related Artist $index',
          ),
          source: 'youtube_related',
          sourceScore: .8,
          sourceRank: index,
        ),
    ];

    final ranked = RecommendationRanker().rank(
      candidates,
      emptyProfile(),
      limit: 24,
    );

    final related = ranked.where(
      (item) => item.extras?['recommendationSource'] == 'youtube_related',
    );
    expect(ranked, hasLength(24));
    expect(related.length, greaterThanOrEqualTo(9));
  });
}
