import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/recommendation_item.dart';
import 'package:harmonymusic/services/recommendation/candidate_pool.dart';

void main() {
  RecommendationCandidate candidate(
    String id,
    String title,
    String source, {
    double sourceScore = 1,
  }) {
    return RecommendationCandidate(
      item: MediaItem(id: id, title: title, artist: 'Artist $title'),
      source: source,
      sourceScore: sourceScore,
    );
  }

  test('round robin keeps later seeds represented', () {
    final result = CandidatePool.roundRobin([
      [
        candidate('a1', 'A1', 'radio'),
        candidate('a2', 'A2', 'radio'),
      ],
      [
        candidate('b1', 'B1', 'radio'),
        candidate('b2', 'B2', 'radio'),
      ],
    ], limit: 4);

    expect(result.map((item) => item.item.id), ['a1', 'b1', 'a2', 'b2']);
  });

  test('canonical duplicates from different sources appear once', () {
    final radio = RecommendationCandidate(
      item: const MediaItem(id: 'video-a', title: 'Signal', artist: 'Nova'),
      source: 'radio',
    );
    final related = RecommendationCandidate(
      item: const MediaItem(
        id: 'video-b',
        title: 'Signal (Official Audio)',
        artist: 'Nova',
      ),
      source: 'related',
    );

    final result = CandidatePool.mergeBuckets([
      CandidateBucket(items: [radio], quota: 1),
      CandidateBucket(items: [related], quota: 1),
    ], limit: 2);

    expect(result, hasLength(1));
  });

  test('canonical duplicate keeps the strongest source candidate', () {
    final weak = RecommendationCandidate(
      item: const MediaItem(id: 'weak', title: 'Signal', artist: 'Nova'),
      source: 'youtube_radio',
      sourceScore: .7,
    );
    final strong = RecommendationCandidate(
      item: const MediaItem(
        id: 'strong',
        title: 'Signal (Official Audio)',
        artist: 'Nova',
      ),
      source: 'lastfm',
      sourceScore: .95,
    );

    final roundRobin = CandidatePool.roundRobin([
      [weak],
      [strong],
    ], limit: 2);
    final bucketed = CandidatePool.mergeBuckets([
      CandidateBucket(items: [weak], quota: 1),
      CandidateBucket(items: [strong], quota: 1),
    ], limit: 2);

    expect(roundRobin.single.source, 'lastfm');
    expect(bucketed.single.source, 'lastfm');
  });

  test('source quotas preserve local and external candidates', () {
    final result = CandidatePool.mergeBuckets([
      CandidateBucket(
        items: List.generate(
          5,
          (index) => candidate('s$index', 'Search $index', 'search'),
        ),
        quota: 2,
      ),
      CandidateBucket(
        items: List.generate(
          5,
          (index) => candidate('l$index', 'Local $index', 'local'),
        ),
        quota: 2,
      ),
    ], limit: 4);

    expect(result.where((item) => item.source == 'search'), hasLength(2));
    expect(result.where((item) => item.source == 'local'), hasLength(2));
  });
}
